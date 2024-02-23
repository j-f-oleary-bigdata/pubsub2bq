CREATE OR REPLACE PROCEDURE `data-analytics-golden-v1-share.cleanroom_data.sp_demo_cleanroom`()
BEGIN
/*##################################################################################
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
###################################################################################*/

  
/*
Use Cases:
    - Creates a table that will be used for a clean room in analytics hub

Description: 
    - Shows the pattern of sharing data with views

References:
    - https://cloud.google.com/analytics-hub

Clean up / Reset script:
  DROP TABLE IF EXISTS`data-analytics-golden-v1-share.cleanroom_data.trips`;

*/


-- Create the data-analytics-golden-v1-share.cleanroom_data` dataset if it doesn't exist

-- Load the data to share (this will be the full table)
-- NOTE: You do not have access to run this command (the table is already created)
--       If you want to run this use the dataset "ce_playground_google" or a dataset 
--       in your argolis project

LOAD DATA OVERWRITE `data-analytics-golden-v1-share.cleanroom_data.trip`
CLUSTER BY trip_id
FROM FILES (
 format = 'PARQUET',
 uris = ['gs://sample-shared-data-temp/cleanroom_trip/*']);

-- Create the data-analytics-golden-v1-share.cleanroom_data_publisher` dataset if it doesn't exist
-- View with Privacy Policy
CREATE OR REPLACE VIEW `cleanroom_data_publisher.trip`
OPTIONS(
  privacy_policy= '{"aggregation_threshold_policy": {"threshold": 2, "privacy_unit_columns": "customer_id"}}'
)
AS ( 
select * from `cleanroom_data.trip`
);

-- View without Privacy Policy
CREATE OR REPLACE VIEW `cleanroom_data_publisher.trip_no_pp`
AS ( 
select * from `cleanroom_data.trip`
);

-- Authorize the views to access the source dataset
-- You can do this via the console (ref: https://cloud.google.com/bigquery/docs/authorized-views#console)
--  or via the bq command as shown here: https://cloud.google.com/bigquery/docs/authorized-views#bq


-- Create the data clean room in Analytics Hub and add the cleanroom_data_publisher dataset as a listing
--  ref: https://cloud.google.com/bigquery/docs/data-clean-rooms

-- Set subscription permissions by setting the Analytics Hub Subscription Owner and Analytics Hub Subscription Viewer
--  both will be have the 'DaGoldenDemoDataShare@argolis-tools.altostrat.com' group added to them

-- Ensure that the user or group that is added above has the `analyticshub.dataExchanges.subscribe` permission


END;