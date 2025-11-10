# IAM user for presets to read from S3 bucket
resource "aws_iam_user" "presets_reader" {
  name = "${var.cluster_name}-geoweb-presets-reader"
}

# IAM access keys
resource "aws_iam_access_key" "presets_reader" {
  user = aws_iam_user.presets_reader.name
}

data "aws_iam_policy_document" "presets_reader" {
  statement {
    sid = "AllowReadGeowebPresets"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.default_presets.arn,
      "${aws_s3_bucket.default_presets.arn}/*",
    ]
  }
}

# Create a managed IAM policy
resource "aws_iam_policy" "presets_reader" {
  name        = "${var.cluster_name}-geoweb-presets-reader-policy"
  description = "S3 read access for geoweb presets"
  policy      = data.aws_iam_policy_document.presets_reader.json
}

resource "aws_iam_user_policy_attachment" "presets_reader" {
  user       = aws_iam_user.presets_reader.name
  policy_arn = aws_iam_policy.presets_reader.arn
}
