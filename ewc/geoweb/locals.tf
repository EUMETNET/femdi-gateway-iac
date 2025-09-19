locals {
  presets_backend_base_path  = "/presets"
  location_backend_base_path = "/location-backend"

  alternative_hosted_zone_names = [for name in var.hosted_zone_names : name if name != var.dns_zone]
}