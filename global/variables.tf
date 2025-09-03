variable "hosted_zone_names" {
  description = "List of hosted zone names"
  type        = list(string)
  default     = ["meteogate.eu"]
}

variable "observations_ip" {
  description = "IP address for observations A record"
  type        = string
}

variable "radar_ip" {
  description = "IP address for radar A record"
  type        = string
}

variable "root_ip" {
  description = "IP address for root A record in hosted zone"
  type        = string
}