# IAM user for cert-manager + external-dns
resource "aws_iam_user" "certmgr_extdns" {
  name = "cert-manager-external-dns"
}

# IAM access key
resource "aws_iam_access_key" "certmgr_extdns" {
  user = aws_iam_user.certmgr_extdns.name
}

# IAM policy document
data "aws_iam_policy_document" "certmgr_extdns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:GetChange"
    ]
    resources = [
      for zone in aws_route53_zone.hosted_zones : zone.arn
    ]
  }

  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }
}

# Attach inline policy
resource "aws_iam_user_policy" "certmgr_extdns" {
  name   = "cert-manager-external-dns-policy"
  user   = aws_iam_user.certmgr_extdns.name
  policy = data.aws_iam_policy_document.certmgr_extdns.json
}
