####################################################################################
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
####################################################################################
  
# Datastream ingress rules for SQL Reverse Proxy communication
resource "google_compute_firewall" "datastream_ingress_rule_firewall_rule" {
  project = var.project_id
  name    = "datastream-ingress-rule"
  network = google_compute_network.default_network.id

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  direction = "INGRESS"

  source_ranges = ["10.6.0.0/16", "10.7.0.0/29"]

  depends_on = [
    google_compute_network.default_network
  ]
}


# Datastream egress rules for SQL Reverse Proxy communication
resource "google_compute_firewall" "datastream_egress_rule_firewall_rule" {
  project = var.project_id
  name    = "datastream-egress-rule"
  network = google_compute_network.default_network.id

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  direction = "EGRESS"

  destination_ranges = ["10.6.0.0/16", "10.7.0.0/29"]

  depends_on = [
    google_compute_network.default_network
  ]
}


# Create the Datastream Private Connection (takes a while so it is done here and not created on the fly in Airflow)
resource "google_datastream_private_connection" "datastream_cloud-sql-private-connect" {
  project               = var.project_id
  display_name          = "cloud-sql-private-connect"
  location              = var.datastream_region
  private_connection_id = "cloud-sql-private-connect"

  vpc_peering_config {
    vpc    = google_compute_network.default_network.id
    subnet = "10.7.0.0/29"
  }

  depends_on = [
    google_compute_network.default_network
  ]
}

# For Cloud SQL / Datastream demo 
# Allocate an IP address range
# https://cloud.google.com/sql/docs/mysql/configure-private-services-access#allocate-ip-address-range   
resource "google_compute_global_address" "google_compute_global_address_vpc_main" {
  project       = var.project_id
  name          = "google-managed-services-default"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.default_network.id

  depends_on = [
    google_compute_network.default_network
  ]
}

# Create a private connection
# https://cloud.google.com/sql/docs/mysql/configure-private-services-access#create_a_private_connection
resource "google_service_networking_connection" "google_service_networking_connection_default" {
  # project                 = var.project_id
  network                 = google_compute_network.default_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.google_compute_global_address_vpc_main.name]

  depends_on = [
    google_compute_network.default_network,
    google_compute_global_address.google_compute_global_address_vpc_main
  ]
}


# Force the service account to get created so we can grant permisssions
resource "google_project_service_identity" "service_identity_servicenetworking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
  provider = google-beta

  depends_on = [
    google_compute_network.default_network,
    google_service_networking_connection.google_service_networking_connection_default
  ]
}

resource "time_sleep" "service_identity_servicenetworking_time_delay" {
  depends_on      = [google_project_service_identity.service_identity_servicenetworking]
  create_duration = "30s"
}

