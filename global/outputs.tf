output "hosted_zone_ids" {
  description = "Map of Route 53 zone IDs by domain name"
  value       = { for k, z in aws_route53_zone.hosted_zones : k => z.id }
}