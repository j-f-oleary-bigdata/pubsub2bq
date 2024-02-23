// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

/*
resource "google_secret_manager_secret" "secret" {
  project   = data.google_project.project.project_id
  secret_id = "mysql-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret-version-data" {
  secret      = google_secret_manager_secret.secret.name
  secret_data = random_password.db_password.result
}
*/

resource "google_sql_database_instance" "instance" {
  name             = local.mysql_pubsub2bq
  database_version = "MYSQL_8_0"
  region           = var.location
  project          = var.project_id
  settings {
    tier    = "db-f1-micro"
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.default_network.id
      enable_private_path_for_google_cloud_services = true
    }
    backup_configuration {
      enabled = true
      binary_log_enabled = true
    }
  }
  deletion_protection = "true"

  depends_on = [
    google_datastream_private_connection.datastream_cloud-sql-private-connect
    ]

}

resource "google_sql_database" "database" {
  name     = local.mysql_pubsub2bq_dbname
  project  = var.project_id
  instance = google_sql_database_instance.instance.name

  depends_on = [ 
    google_sql_database_instance.instance 
  ]

}

/*
resource "google_sql_database_instance" "default" {
  [...]
  provisioner "local-exec" {
    command = "PGPASSWORD=<password> psql -f schema.sql -p <port> -U <username> <databasename>"
  }
}
*/

resource "google_sql_user" "user" {
  name     = "pubsub2bq"
  project  = var.project_id
  instance = google_sql_database_instance.instance.name
  password = random_password.db_password.result

  depends_on = [google_sql_database.database]
}

locals {
    mysql_password = random_password.db_password.result
}

resource "null_resource" "debezium_downloadv2" {
   provisioner "local-exec" {
    command = <<-EOT
       curl -o debezium.tar.gz  https://repo1.maven.org/maven2/io/debezium/debezium-server-dist/1.9.5.Final/debezium-server-dist-1.9.5.Final.tar.gz
       tar xvf debezium.tar.gz
    EOT
 }
  depends_on = [google_sql_database.database]
}


resource "google_storage_bucket" "bucket-pubsub2bq" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  force_destroy               = true
  uniform_bucket_level_access = true
  depends_on = [null_resource.debezium_downloadv2]
}

resource "null_resource" "create_debezium_properties" {
  provisioner "local-exec" {
    command = <<-EOT
        cp ../conf/debezium.properties  application.properties && \
         sed -i '' -e s/PROJECT_ID/${var.project_id}/g application.properties && \
         sed -i '' -es/MYSQL_PASSWORD/${local.mysql_password}/g application.properties && \
         sed -i '' -es/MYSQL_SERVERNAME/${local.mysql_pubsub2bq}/g application.properties && \
        sed -i '' -es/MYSQL_DATABASENAME/${local.mysql_pubsub2bq_dbname}/g application.properties
    EOT
    interpreter = ["bash", "-c"]
  }
  depends_on = [google_storage_bucket.bucket-pubsub2bq]
}

resource "null_resource" "mysql_script_creation" {
    provisioner "local-exec" {
        command = <<-EOT
            cp ../sql/pubsub2bq.sql pubsub2bq.sql && \
             sed -i '' -e s/MYSQL_DATABASENAME/${local.mysql_pubsub2bq_dbname}/g pubsub2bq.sql && \
            sed -i '' -e s/MYSQL_TABLENAME/${local.mysql_pubsub2bq_tablename}/g pubsub2bq.sql
        EOT
        interpreter = ["bash", "-c"]
    }
  depends_on = [google_storage_bucket.bucket-pubsub2bq]
}



/*
resource "null_resource" "create_debezium_properties {
  provisioner "local-exec" {
    command = <<-EOT
        cp ../conf/debezium.properties  application.properties && \
         sed -i s/PROJECT_ID/${var.project_id}/g application.properties && \
         sed -i s/MYSQL_PASSWORD/${local.mysql_password}/g application.properties && \
         sed -i s/MYSQL_SERVERNAME/${local.mysql_pubsub2bq}/g application.properties && \
        sed -i s/MYSQL_DATABASENAME/${local.mysql_pubsub2bq_dbname}/g application.properties
        cp application.properties ./debezium-server/conf
        gsutil application.properties gs://${local.bucket_name}/
    EOT
    interpreter = ["bash", "-c"]
  }

}

resource "null_resource" "mysql_script_creation" {
    provisioner "local-exec" {
        command = <<-EOT
            cp ../sql/pubsub2bq.sql pubsub2bq.sql && \
            sed -i s/MYSQL_SERVERNAME/${local.mysql_pubsub2bq}/g pubsub2bq.sql && \
            sed -i s/MYSQL_TABLENAME/${local.mysql_pubsub2bq_tablename}/g pubsub2bq.sql
            gsutil pubsub2bq.sql gs://${local.bucket_name}/
        EOT
        interpreter = ["bash", "-c"]
    }
  depends_on = [null_resource.debezium_download]
}
*/

resource "google_compute_instance" "cloudsql_proxy" {
  name         = "sql-reverse-proxy"
  machine_type = "e2-small"
  tags         = ["allow-ssh"]
  zone         = var.compute_zone
  can_ip_forward = true

  boot_disk {
    mode="READ_WRITE"
    auto_delete=true
    initialize_params {
      image = "projects/debian-cloud/global/images/debian-11-bullseye-v20230411"
      type = "type=projects/${var.project_id}/zones/${var.compute_zone}/diskTypes/pd-balanced"
      size = 10
      labels = {
        vm_name = "cloudsql-proxy"
      }
    }
  }

  network_interface {
    network    = google_compute_network.default_network.id
    subnetwork = google_compute_subnetwork.main_subnet.self_link
  }

  metadata = {
      enable-oslogin      = "false"
  }

  metadata_startup_script = <<EOF
  #! /bin/bash

# https://cloud.google.com/datastream/docs/private-connectivity#set-up-reverse-proxy
# Your connection will most likely fail. VM is missing firewall rule allowing TCP ingress traffic from 35.235.240.0/20 on port 22.

export DB_ADDR=${google_sql_database_instance.instance.private_ip_address}
export DB_PORT=3306
export ETH_NAME=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
export LOCAL_IP_ADDR=$(ip -4 addr show $ETH_NAME | grep -Po 'inet \K[\d.]+')
sudo echo 1 > /proc/sys/net/ipv4/ip_forward
sudo iptables -t nat -A PREROUTING -p tcp -m tcp --dport $DB_PORT -j DNAT --to-destination $DB_ADDR:$DB_PORT
sudo iptables -t nat -A POSTROUTING -j SNAT --to-source $LOCAL_IP_ADDR

#get latest repo's and then install mysql client
sudo apt update
sudo apt install default-mysql-client

#get mysql SCRIPTS
gsutil cp gs://${local.bucket_name}/* .

# list tables
# sudo iptables -L -n -t nat

EOF


  service_account {
    email  = "${var.project_nbr}-compute@developer.gserviceaccount.com"
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

   depends_on = [
      null_resource.mysql_script_creation,
      null_resource.create_debezium_properties
   ]


}


