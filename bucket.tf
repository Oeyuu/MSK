resource "aws_s3_bucket" "distributions" {
  bucket = "${local.full_prefix}-distributions"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kms" {
  depends_on = [ aws_kms_key.msk, aws_s3_bucket.distributions ]
  bucket = "${local.full_prefix}-distributions"

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.msk.arn
      sse_algorithm     = "aws:kms"
    }
  }
}
