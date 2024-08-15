resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.prefix}-s3-tfstate"
  force_destroy = true

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name      = "${var.prefix}-s3-tfstate"
    Env       = var.env
    Terraform = true
  }
}

resource "aws_s3_bucket_acl" "terraform_state_acl" {
  bucket = aws_s3_bucket.terraform_state.bucket
  acl    = "private"
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

resource "aws_s3_bucket_policy" "terraform_state_policy" {
  bucket = aws_s3_bucket.terraform_state.bucket
  depends_on = [aws_s3_bucket.terraform_state]
  policy = <<EOF
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "ListGetPutDeleteBucketContents",
			"Effect": "Allow",
			"Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
			"Principal": {
 			  "AWS": "${var.principal_arn}"
 		  },
			"Resource": [
        "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}",
        "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}/*"
      ]
		}
	]
}
EOF
}

# resource "aws_s3_bucket_policy" "terraform_state_policy" {
#   bucket = aws_s3_bucket.terraform_state.bucket
#   depends_on = [aws_s3_bucket.terraform_state]
#   policy = <<EOF
# {
# 	"Version": "2012-10-17",
# 	"Statement": [
# 		{
# 			"Sid": "ListBucketContents",
# 			"Effect": "Allow",
# 			"Action": "s3:ListBucket",
# 			"Resource": "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}",
# 			"Principal": {
# 				"AWS": "${var.principal_arn}"
# 			}
# 		},
# 		{
# 			"Sid": "GetPutDeleteObjects",
# 			"Effect": "Allow",
# 			"Action": [
# 				"s3:GetObject",
# 				"s3:PutObject",
# 				"s3:DeleteObject"
# 			],
# 			"Resource": "arn:aws:s3:::${aws_s3_bucket.terraform_state.bucket}/*",
# 			"Principal": {
# 				"AWS": "${var.principal_arn}"
# 			}
# 		}
# 	]
# }
# EOF
# }

# Add bucket encryption to hide sensitive state data
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "${var.prefix}-terraform-lock-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Name      = "${var.prefix}-terraform-lock-table"
    Env       = var.env
    Terraform = true
  }
}

resource "aws_dynamodb_resource_policy" "terraform_lock_policy" {
  resource_arn = aws_dynamodb_table.terraform_lock.arn
  depends_on = [aws_dynamodb_table.terraform_lock]
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/${aws_dynamodb_table.terraform_lock.name}",
      "Principal": { "AWS": "arn:aws:iam::019273956931:user/talorlik" }
    }
  ]
}
EOF
}
