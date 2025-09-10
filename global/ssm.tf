######################################################
# Fetching values from SSM Parameter Store
######################################################

data "aws_ssm_parameter" "observations_ip" {
  name = "/route53/observations_ip"
}

data "aws_ssm_parameter" "radar_ip" {
  name = "/route53/radar_ip"
}

data "aws_ssm_parameter" "root_ip" {
  name = "/route53/root_ip"
}

data "aws_ssm_parameter" "hosted_zone_names" {
  name = "/route53/hosted_zone_names"
}

######################################################
# Putting values into SSM Parameter Store
######################################################

resource "aws_ssm_parameter" "hosted_zone_ids" {
  for_each = aws_route53_zone.hosted_zones
  name     = "/route53/hosted_zone_id/${each.value.name}"
  description = "Route 53 hosted zone ID for ${each.value.name}"
  type     = "String"
  value    = each.value.id
}

resource "aws_ssm_parameter" "certmgr_extdns_aws_access_key_id" {
  name     = "/iam/certmgr_extdns/access_key"
  description = "Access key for cert-manager + external-dns"
  type     = "SecureString"
  value    = aws_iam_access_key.certmgr_extdns.id
}

resource "aws_ssm_parameter" "certmgr_extdns_aws_secret_access_key" {
  name     = "/iam/certmgr_extdns/secret_access_key"
  description = "Secret access key for cert-manager + external-dns"
  type     = "SecureString"
  value    = aws_iam_access_key.certmgr_extdns.secret
}

# Parameters for backup related things

resource "aws_ssm_parameter" "backup_aws_access_key_id" {
  name     = "/iam/backups/access_key"
  description = "Access key for backup and restore jobs"
  type     = "SecureString"
  value    = aws_iam_access_key.backups.id
}

resource "aws_ssm_parameter" "backup_aws_secret_access_key" {
  name     = "/iam/backups/secret_access_key"
  description = "Secret access key for backup and restore jobs"
  type     = "SecureString"
  value    = aws_iam_access_key.backups.secret
}

resource "aws_ssm_parameter" "backup_bucket_name" {
  name     = "/s3/backups/bucket_name"
  description = "S3 bucket name for backup and restore jobs"
  type     = "String"
  value    = aws_s3_bucket.backups.bucket
}
