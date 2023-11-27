// Copyright 2021 Google LLC
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
  project          = data.google_project.project.project_id

  backup_configuration = {
    enabled            = true
    binary_log_enabled = true
    start_time         = "00:05"
}

  settings {
    tier = "db-f1-micro"
  }

  deletion_protection = "true"
}

resource "google_sql_database" "database" {
  name     = local.mysql_pubsub2bq_dbname
  project  = data.google_project.project.project_id
  instance = google_sql_database_instance.instance.name
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
  project  = data.google_project.project.project_id
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
  depends_on = [null_resource.debezium_downloadv2]
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
        EOT
        interpreter = ["bash", "-c"]
    }
  depends_on = [null_resource.debezium_download]
}
*/