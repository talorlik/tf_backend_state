# Get current AWS account ID and caller identity for unique bucket naming and dynamic principal
data "aws_caller_identity" "current" {}

# Use provided principal_arn or default to current caller's ARN
locals {
  principal_arn = var.principal_arn != null ? var.principal_arn : data.aws_caller_identity.current.arn
}

resource "aws_s3_bucket" "terraform_state" {
  # Include account ID in bucket name to ensure global uniqueness
  bucket        = "${var.prefix}-${data.aws_caller_identity.current.account_id}-s3-tfstate"
  force_destroy = true

  tags = {
    Name      = "${var.prefix}-${data.aws_caller_identity.current.account_id}-s3-tfstate"
    Env       = var.env
    Terraform = true
  }
}

resource "aws_s3_bucket_acl" "terraform_state_acl" {
  bucket     = aws_s3_bucket.terraform_state.bucket
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.terraform_state_acl_ownership]
}

# Resource to avoid error "AccessControlListNotSupported: The bucket does not allow ACLs"
resource "aws_s3_bucket_ownership_controls" "terraform_state_acl_ownership" {
  bucket = aws_s3_bucket.terraform_state.bucket
  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access to the state bucket
resource "aws_s3_bucket_public_access_block" "terraform_state_public_block" {
  bucket = aws_s3_bucket.terraform_state.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "terraform_state_policy" {
  bucket = aws_s3_bucket.terraform_state.bucket
  depends_on = [
    aws_s3_bucket.terraform_state,
    aws_s3_bucket_public_access_block.terraform_state_public_block
  ]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListGetPutDeleteBucketContents"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Principal = {
          AWS = local.principal_arn
        }
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}/*"
        ]
      }
    ]
  })
}

# Add bucket encryption to hide sensitive state data
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
