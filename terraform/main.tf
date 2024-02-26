/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  prefix = "pubsub2bq"
  _project_number           = var.project_nbr
  bucket_name               = format("%s-%s", local.prefix, var.project_nbr)
  pubsub2bq_dataset_name    = format("%s_dataset", local.prefix) 
  pubsub2bq_table_name      = "people"
  pubsub2bq_dead_letter     = format("%s-dead-letter", local.prefix)
  pubsub2bq_nobq_sub        = format("%s-nobq-sub", local.prefix)
  pubsub2bq_bq_sub          = format("%s-bq-sub", local.prefix)
  mysql_pubsub_topic        = "mysql-pubsub2bq"
  mysql_pubsub_sub          = "mysql-sub"
  mysql_pubsub2bq           = "mysql-pubsub2bq"
  mysql_pubsub2bq_dbname    = "debezium_test"
  mysql_pubsub2bq_tablename = "people"
  mysql_datastream2bq_dbname  = "datastream_test"
  pubsub2bq_pubsub_topic    = format("%s.%s.%s", local.mysql_pubsub2bq, local.mysql_pubsub2bq_dbname, local.pubsub2bq_table_name)
  pubsub_schemaname         = format("%s-schema", local.prefix)
  gmsa_fqn                  = "${var.project_nbr}-compute@developer.gserviceaccount.com"
  activate_apis = [
    "cloudbilling.googleapis.com",
    "oslogin.googleapis.com",
    "serviceusage.googleapis.com",
    "datastream.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com", 
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "sqladmin.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com"
    ]
}

provider "google" {
  project = var.project_id
  region  = var.location
}

/*
resource "google_project" "project" {
  name                = var.project_id
  project_id          = var.project_id
  auto_create_network = false
  skip_delete         = true
  billing_account     = "${var.account_id}"

}
*/

####################################################################################
# Enable serviceusageapi                                                           #
####################################################################################

resource "google_project_service" "project_serviceusage" {
  project                    = var.project_id
  service                    = "serviceusage.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

/*******************************************
Introducing sleep to minimize errors from
dependencies having not completed
********************************************/
resource "time_sleep" "sleep_after_activate_serviceusage" {
  create_duration = "60s"

  depends_on = [
    google_project_service.project_serviceusage
  ]
}

####################################################################################
# Enable APIs                                                                      #
####################################################################################
resource "google_project_service" "project_services" {
  for_each                   = toset(local.activate_apis)
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = true
  disable_dependent_services = true

  depends_on = [
    time_sleep.sleep_after_activate_serviceusage
  ]
}

/*******************************************
Introducing sleep to minimize errors from
dependencies having not completed
********************************************/
resource "time_sleep" "sleep_after_activate_service_apis" {
  create_duration = "60s"

  depends_on = [
    google_project_service.project_services
  ]
}

####################################################################################
# Resource for Network Creation                                                    #
# The project was not created with the default network.                            #
# This creates just the network/subnets we need.                                   #
####################################################################################
resource "google_compute_network" "default_network" {
  project                 = var.project_id
  name                    = "default"
  description             = "Default network"
  auto_create_subnetworks = false
  mtu                     = 1460
  depends_on = [
    time_sleep.sleep_after_activate_service_apis
  ]
}

####################################################################################
# Resource for Subnet                                                              #
#This creates just the subnets we need                                             #
####################################################################################

resource "google_compute_subnetwork" "main_subnet" {
  project       = var.project_id
  name          = "default"    #format("%s-misc-subnet", local._prefix)
  ip_cidr_range = var.ip_range
  region        = var.location
  network       = google_compute_network.default_network.id
  private_ip_google_access = true
  depends_on = [
    google_compute_network.default_network
  ]
}

####################################################################################
# Resource for Firewall rule                                                       #
####################################################################################

resource "google_compute_firewall" "firewall_rule" {
  project  = var.project_id
  name     = "allow-intra-default"    #format("allow-intra-%s-misc-subnet", local._prefix)
  network  = google_compute_network.default_network.id

  direction = "INGRESS"

  allow {
    protocol = "all"
  }
  
  source_ranges = [ var.ip_range ]
  depends_on = [
    google_compute_subnetwork.main_subnet
  ]
}

resource "google_compute_firewall" "user_firewall_rule" {
  project  = var.project_id
  name     = "allow-ingress-from-office-default"   #format("allow-ingress-from-office-%s", local._prefix)
  network  = google_compute_network.default_network.id

  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  source_ranges = [ var.user_ip_range ]
  depends_on = [
    google_compute_subnetwork.main_subnet
  ]
}


# Firewall for NAT Router
resource "google_compute_firewall" "subnet_firewall_rule" {
  project = var.project_id
  name    = "subnet-nat-firewall"
  network = google_compute_network.default_network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
  source_ranges = [var.ip_range]

  depends_on = [
    google_compute_subnetwork.main_subnet
  ]
}

resource "google_compute_router" "nat-router" {
  project = var.project_id
  name    = "nat-router"
  region  = var.location
  network = google_compute_network.default_network.id

  depends_on = [
    google_compute_firewall.subnet_firewall_rule
  ]
}

resource "google_compute_router_nat" "nat-config" {
  project                            = var.project_id
  name                               = "nat-config"
  router                             = google_compute_router.nat-router.name
  region                             = var.location
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  depends_on = [
    google_compute_router.nat-router
  ]
}


#data "google_compute_network" "default_network" {
#  name = "default"
#}

# Firewall rule for Cloud Shell to SSH in Compute VMs
# A compute VM will be deployed as a SQL Reverse Proxy for Datastream private connectivity
resource "google_compute_firewall" "cloud_shell_ssh_firewall_rule" {
  project = var.project_id
  name    = "cloud-shell-ssh-firewall-rule"
  network = google_compute_network.default_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  direction   = "INGRESS"
  target_tags = ["allow-ssh"]

  source_ranges = ["35.235.240.0/20"]

  depends_on = [
    google_compute_network.default_network
  ]
}


/*******************************************
Introducing sleep to minimize errors from
dependencies having not completed
********************************************/
resource "time_sleep" "sleep_after_network_and_iam_steps" {
  create_duration = "120s"
  depends_on = [
                google_compute_firewall.user_firewall_rule,
                google_compute_firewall.cloud_shell_ssh_firewall_rule
              ]
}


####################################################################################
# Create BigQuery Datasets
####################################################################################

resource "google_bigquery_dataset" "pubsub2bq_dataset" {
  project                     = var.project_id
  dataset_id                  = local.pubsub2bq_dataset_name
  friendly_name               = local.pubsub2bq_dataset_name
  description                 = "Dataset for pubsub2bq"
  location                   = var.location
  delete_contents_on_destroy  = true
  
  depends_on = [time_sleep.sleep_after_network_and_iam_steps]
}


####################################################################################
# Create BigQuery Table
####################################################################################

resource "google_bigquery_table" "people_table" {
  project                     = var.project_id
  dataset_id                  = google_bigquery_dataset.pubsub2bq_dataset.dataset_id
  table_id                    = local.pubsub2bq_table_name
  schema      = <<EOF
    [
    {
        "mode": "NULLABLE",
        "name": "id",
        "type": "INTEGER"
      },
      {
        "mode": "NULLABLE",
        "name": "first_name",
        "type": "STRING"
      },
      {
        "mode": "NULLABLE",
        "name": "last_name",
        "type": "STRING"
      },
      {
        "mode": "NULLABLE",
        "name": "email",
        "type": "STRING"
      },
      {
        "mode": "NULLABLE",
        "name": "zipcode",
        "type": "INTEGER"
      },
      {
        "mode": "NULLABLE",
        "name": "city",
        "type": "STRING"
      },
      {
        "mode": "NULLABLE",
        "name": "country",
        "type": "STRING"
      },
      {
        "mode": "NULLABLE",
        "name": "__deleted",
        "type": "STRING"
      }      
    ]
    EOF
  depends_on = [google_bigquery_dataset.pubsub2bq_dataset]
}

resource "google_pubsub_topic" "dead_letter" {
  name = local.pubsub2bq_dead_letter

  depends_on = [time_sleep.sleep_after_network_and_iam_steps]  
}

resource "google_pubsub_schema" "pubsub2bq_schema" {
  name = local.pubsub_schemaname
  type = "AVRO"
  definition = "{\n \"type\": \"record\",\n \"name\": \"Avro\",\n \"fields\": [\n {\n \"name\": \"id\",\n \"type\": \"int\"\n },\n {\n \"name\": \"first_name\",\n \"type\": \"string\"\n },\n {\n \"name\": \"last_name\",\n \"type\": \"string\"\n },\n {\n \"name\": \"email\",\n \"type\": \"string\"\n },\n {\n \"name\": \"zipcode\",\n \"type\": \"int\"\n },\n {\n \"name\": \"city\",\n \"type\": \"string\"\n },\n {\n \"name\": \"country\",\n \"type\": \"string\"\n },\n {\n \"name\": \"__deleted\",\n \"type\": \"string\"\n }\n ]\n }\n"

  depends_on = [time_sleep.sleep_after_network_and_iam_steps]
}

resource "google_pubsub_topic" "pubsub2bq_topic" {
  name = local.pubsub2bq_pubsub_topic
  schema_settings {
    schema = "projects/${var.project_id}/schemas/${local.pubsub_schemaname}"
    encoding = "JSON"
  }

  depends_on = [google_pubsub_schema.pubsub2bq_schema]
}

resource "google_pubsub_subscription" "pubsub2bq-nobq-subscription" {
  name = local.pubsub2bq_nobq_sub
  topic                      = google_pubsub_topic.pubsub2bq_topic.name
  message_retention_duration = "1200s"
  retain_acked_messages      = true
  ack_deadline_seconds       = 60
  expiration_policy {
    ttl = "86400s"
  }

  depends_on = [google_pubsub_topic.pubsub2bq_topic]
}

resource "google_pubsub_subscription" "bigquery_sub" {
  name  = local.pubsub2bq_bq_sub
  topic = resource.google_pubsub_topic.pubsub2bq_topic.name

  bigquery_config {
        drop_unknown_fields = false
        table               = "${google_bigquery_table.people_table.project}.${google_bigquery_table.people_table.dataset_id}.${google_bigquery_table.people_table.table_id}"
        use_topic_schema     = true
        write_metadata      = false
  }  

  retain_acked_messages = true
  message_retention_duration = "604800s"
  retry_policy {
    minimum_backoff = "60s"
  }

  dead_letter_policy {
    dead_letter_topic     = resource.google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  depends_on = [
    google_pubsub_topic.pubsub2bq_topic,
    google_bigquery_table.people_table
  ]
}

resource "google_pubsub_topic" "mysql_topic" {
  name = local.mysql_pubsub_topic
  
  depends_on = [time_sleep.sleep_after_network_and_iam_steps]
}

resource "google_pubsub_subscription" "mysql_subscription" {
  name = local.mysql_pubsub_topic
  topic                      = google_pubsub_topic.mysql_topic.name
  message_retention_duration = "1200s"
  retain_acked_messages      = true
  ack_deadline_seconds       = 60
  expiration_policy {
    ttl = "86400s"
  }

  depends_on = [google_pubsub_topic.mysql_topic]

}

resource "google_project_iam_member" "service_account_worker_role" {
  project  = var.project_id
  role     = "roles/bigquery.dataEditor"
  member   = "serviceAccount:service-${var.project_nbr}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [time_sleep.sleep_after_network_and_iam_steps]
}

resource "google_project_organization_policy" "list_policies" {
  for_each = {
    "compute.vmCanIpForward" : true,
    "compute.vmExternalIpAccess" : true,
    "compute.restrictVpcPeering" : true
  }
  project     = var.project_id
  constraint = format("constraints/%s", each.key)
  list_policy {
    allow {
      all = each.value
    }
  }

  depends_on = [
    time_sleep.sleep_after_activate_service_apis
  ]

}

resource "google_project_organization_policy" "bool-policies" {
  for_each = {
    "compute.requireOsLogin" : false,
    "compute.disableSerialPortLogging" : false,
    "compute.requireShieldedVm" : false
  }
  project    = var.project_id
  constraint = format("constraints/%s", each.key)
  boolean_policy {
    enforced = each.value
  }

  depends_on = [
    time_sleep.sleep_after_activate_service_apis
  ]

}

