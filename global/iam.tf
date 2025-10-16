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

# Create Identity Provider, Role etc for Github OIDC
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:EUMETNET/api-management-tool-poc:*"]
    }
  }
}
resource "aws_iam_role" "github_oidc" {
  name               = "api-mgmt-tool-gha-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json
}

resource "aws_iam_role_policy" "github_oidc_policy" {
  name = "api-mgmt-tool-gha-role-policy"
  role = aws_iam_role.github_oidc.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:Describe*",
          "ssm:Get*",
          "ssm:List*"
        ],
        Resource = "*"
      }
    ]
  })
}
