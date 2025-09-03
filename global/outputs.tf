output "hosted_zone_ids" {
  description = "Map of Route 53 zone IDs by domain name"
  value       = { for k, z in aws_route53_zone.hosted_zones : k => z.id }
}

output "certmgr_extdns_aws_access_key_id" {
  description = "AWS access key for cert-manager + external-dns"
  value     = aws_iam_access_key.certmgr_extdns.id
  sensitive = true
}

output "certmgr_extdns_aws_secret_access_key" {
  description = "AWS secret access key for cert-manager + external-dns"
  value     = aws_iam_access_key.certmgr_extdns.secret
  sensitive = true
}
