variable "new_route53_zone_id_filter" {
  description = "New hosted zone ID in route53"
  type        = string
}

variable "observations_ip" {
  description = "IP address for observations A record"
  type        = string
}

variable "radar_ip" {
  description = "IP address for radar A record"
  type        = string
}
