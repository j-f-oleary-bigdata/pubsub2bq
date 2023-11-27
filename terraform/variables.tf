variable "project_id" {
  type        = string
  description = "project id required"
}

variable "project_nbr" {
  type        = string
  description = "project id required"
}

variable "location" {
 description = "Location/region to be used"
 default = "us-central1"
}

variable "ip_range" {
 description = "IP Range used for the network for this demo"
 default = "10.6.0.0/24"
}

variable "user_ip_range" {
 description = "IP range for the user running the demo"
 default = "10.6.0.0/24"
}


