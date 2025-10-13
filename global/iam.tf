# IAM user for cert-manager + external-dns
resource "aws_iam_user" "certmgr_extdns" {
  name = "cert-manager-external-dns"
}

# IAM access key
resource "aws_iam_access_key" "certmgr_extdns" {
  user = aws_iam_user.certmgr_extdns.name
}

data "aws_iam_policy_document" "certmgr_extdns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      for zone in aws_route53_zone.hosted_zones : zone.arn
    ]
  }

  statement {
    actions = [
      "route53:GetChange",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }
}

# Create a managed IAM policy
resource "aws_iam_policy" "certmgr_extdns" {
  name        = "cert-manager-external-dns-policy"
  description = "Route53 access for cert-manager and external-dns"
  policy      = data.aws_iam_policy_document.certmgr_extdns.json
}

resource "aws_iam_user_policy_attachment" "certmgr_extdns" {
  user       = aws_iam_user.certmgr_extdns.name
  policy_arn = aws_iam_policy.certmgr_extdns.arn
}

# IAM user for backups
resource "aws_iam_user" "backups" {
  name = "backups"
}

# IAM access key
resource "aws_iam_access_key" "backups" {
  user = aws_iam_user.backups.name
}

data "aws_iam_policy_document" "backups" {
  statement {
    sid = "AllowReadWriteBackups"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.backups.arn,
      "${aws_s3_bucket.backups.arn}/*",
    ]
  }
}

# Create a managed IAM policy
resource "aws_iam_policy" "backups" {
  name        = "backups-policy"
  description = "S3 access for backups"
  policy      = data.aws_iam_policy_document.backups.json
}

resource "aws_iam_user_policy_attachment" "backups" {
  user       = aws_iam_user.backups.name
  policy_arn = aws_iam_policy.backups.arn
}
