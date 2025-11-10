# S3 bucket for default presets json files
resource "aws_s3_bucket" "default_presets" {
  bucket = "meteogate-${var.cluster_name}-default-presets"
}

resource "aws_s3_bucket_public_access_block" "default_presets" {
  bucket = aws_s3_bucket.default_presets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "files" {
  for_each = { for f in fileset("${path.module}/default-presets", "**") : f => f }

  bucket = aws_s3_bucket.default_presets.id
  key    = "default-presets/${each.key}"
  source = "${path.module}/default-presets/${each.value}"
}
