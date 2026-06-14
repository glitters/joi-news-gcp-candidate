locals {
  gcr_url = "us-central1-docker.pkg.dev/${var.project}/images"
}

# the dedicated service account that the compute instances will use
resource "google_service_account" "joi-news-instances" {
  account_id   = "${var.prefix}-compute"
  display_name = "${var.prefix} Service Account"
}

# grant the compute service account read access to Artifact Registry
resource "google_artifact_registry_repository_iam_binding" "viewer" {
  provider   = google-beta
  repository = "images"
  location   = "us-central1"
  role       = "roles/artifactregistry.admin"

  members = [
    "serviceAccount:${google_service_account.joi-news-instances.email}",
  ]
}

data "google_compute_network" "default" {
  name = "vpc-news4321"
}

data "google_compute_subnetwork" "subnet" {
  name = "subnet-news4321"
}

#################################################
# FRONT END
#################################################

resource "google_compute_instance" "front_end" {
  name         = "${var.prefix}-front-end"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  tags         = ["ssh-enabled", "web"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-125-lts"
    }
  }

  metadata_startup_script = templatefile("${path.module}/provision-front_end.sh", {
    docker_image         = "${local.gcr_url}/front_end:latest"
    quote_service_url    = "http://${google_compute_instance.quotes.network_interface.0.network_ip}:8082"
    newsfeed_service_url = "http://${google_compute_instance.newsfeed.network_interface.0.network_ip}:8081"
    static_url           = "https://storage.googleapis.com/${google_storage_bucket.news.name}"
  })

  network_interface {
    subnetwork = data.google_compute_subnetwork.subnet.self_link

    access_config {}
  }

  service_account {
    email  = google_service_account.joi-news-instances.email
    scopes = var.service_account_scopes
  }
}

resource "google_compute_firewall" "front_end" {
  name    = "front-end-firewall"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

#################################################
# QUOTES
#################################################

resource "google_compute_instance" "quotes" {
  name         = "${var.prefix}-quotes"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  tags         = ["ssh-enabled", "quotes"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-125-lts"
    }
  }

  metadata_startup_script = templatefile("${path.module}/provision-quotes.sh", {
    docker_image = "${local.gcr_url}/quotes:latest"
  })

  network_interface {
    subnetwork = data.google_compute_subnetwork.subnet.self_link
    access_config {}
  }

  service_account {
    email  = google_service_account.joi-news-instances.email
    scopes = var.service_account_scopes
  }
}

resource "google_compute_firewall" "quotes" {
  name    = "quotes-firewall"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8082"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["quotes"]
}

#################################################
# NEWSFEED
#################################################

resource "google_compute_instance" "newsfeed" {
  name         = "${var.prefix}-newsfeed"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  tags         = ["ssh-enabled", "newsfeed"]

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-125-lts"
    }
  }

  metadata_startup_script = templatefile("${path.module}/provision-newsfeed.sh", {
    docker_image = "${local.gcr_url}/newsfeed:latest"
  })

  network_interface {
    subnetwork = data.google_compute_subnetwork.subnet.self_link
    access_config {}
  }

  service_account {
    email  = google_service_account.joi-news-instances.email
    scopes = var.service_account_scopes
  }
}

resource "google_compute_firewall" "newsfeed" {
  name    = "newsfeed-firewall"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["8081"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["newsfeed"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # or restrict to YOUR_IP/32 for safety

  target_tags = ["ssh-enabled"]
}

#################################################
# OUTPUT
#################################################

output "frontend_url" {
  value = "http://${google_compute_instance.front_end.network_interface.0.access_config.0.nat_ip}:8080"
}