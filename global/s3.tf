# S3 bucket for backups
resource "aws_s3_bucket" "backups" {
  bucket = "meteogate-backups"
}

resource "aws_s3_bucket_lifecycle_configuration" "backups_lifecycle_rules" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id = "delete-old-backups"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
