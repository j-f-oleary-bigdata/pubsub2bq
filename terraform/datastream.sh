#!/bin/bash

####################################################################################
# Copyright 2024 Google LLC
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

PROJECT_ID=`gcloud config list --format "value(core.project)" 2>/dev/null`
PROJECT_NBR=`gcloud projects describe $PROJECT_ID | grep projectNumber | cut -d':' -f2 |  tr -d "'" | xargs`
ROOT_PASSWORD=$(sed -n "/^debezium.source.database.password=/p" application.properties | sed "s/^debezium.source.database.password=//")

DATASTREAM_REGION="us-central1"
DATABASE_NAME="datastream_test"
BIGQUERY_REGION="us-central1"

echo "PROJECT_ID: ${PROJECT_ID}"
echo "DATASTREAM_REGION: ${DATASTREAM_REGION}"
echo $ROOT_PASSWORD


# Get ip address (of this node)
reverse_proxy_vm_ip_address=$(gcloud compute instances list --filter="NAME=sql-reverse-proxy" --project="${PROJECT_ID}" --format="value(INTERNAL_IP)")
echo "reverse_proxy_vm_ip_address: ${reverse_proxy_vm_ip_address}"


# Create the Datastream source
# https://cloud.google.com/sdk/gcloud/reference/datastream/connection-profiles/create
gcloud datastream connection-profiles create mysql-private-ip-connection \
    --location=${DATASTREAM_REGION} \
    --type=mysql \
    --mysql-password=${ROOT_PASSWORD} \
    --mysql-username=pubsub2bq \
    --display-name=mysql-private-ip-connection \
    --mysql-hostname=${reverse_proxy_vm_ip_address} \
    --mysql-port=3306 \
    --private-connection=cloud-sql-private-connect  \
    --project="${PROJECT_ID}"


# Create the Datastream destination
gcloud datastream connection-profiles create bigquery-private-ip-connection \
    --location=${DATASTREAM_REGION} \
    --type=bigquery \
    --display-name=bigquery-private-ip-connection \
    --project="${PROJECT_ID}"


# Do we need a wait statement here while the connections get created
# Should call apis to test for sure
echo "Sleep 90"
sleep 90


# Postgres source JSON/YAML
# https://cloud.google.com/datastream/docs/reference/rest/v1/projects.locations.streams#PostgresqlTable
source_config_json=$(cat <<EOF
 {
    "includeObjects":  {
      "mysqlDatabases": [
          {
            "database":"datastream_test",
            "mysqlTables": [
              {
                "table": "people",
              }
            ]
          }
        ]
      }
  }
EOF
)

# Write to file
echo ${source_config_json} > source_private_ip_config.json
echo "source_config_json: ${source_config_json}"


# BigQuery destination JSON/YAML
destination_config_json=$(cat <<EOF
{
  "sourceHierarchyDatasets": {
    "datasetTemplate": {
      "location": "${BIGQUERY_REGION}",
      "datasetIdPrefix": "cdc_",
    }
  },
  "dataFreshness": "0s"
}
EOF
)

# Write to file
echo ${destination_config_json} > destination_private_ip_config.json
echo "destination_config_json: ${destination_config_json}"


# Create DataStream "Stream"
# https://cloud.google.com/sdk/gcloud/reference/datastream/streams/create
gcloud datastream streams create datastream-demo-private-ip-stream \
    --location="${DATASTREAM_REGION}" \
    --display-name=datastream-demo-private-ip-stream \
    --source=mysql-private-ip-connection \
    --mysql-source-config=source_private_ip_config.json \
    --destination=bigquery-private-ip-connection \
    --bigquery-destination-config=destination_private_ip_config.json \
    --backfill-all \
    --project="${PROJECT_ID}"


echo "Sleep 60"
sleep 60

# Show the stream attributes
gcloud datastream streams describe datastream-demo-private-ip-stream --location="${DATASTREAM_REGION}" --project="${PROJECT_ID}"


echo "Sleep 60"
sleep 60

# Start the stream
gcloud datastream streams update datastream-demo-private-ip-stream --location="${DATASTREAM_REGION}" --state=RUNNING --update-mask=state --project="${PROJECT_ID}"