# S3 bucket that holds the HuggingFace weights staged for Custom Model Import (line item 2).
resource "aws_s3_bucket" "weights" {
  bucket_prefix = "coaa-cmi-weights-"
}

resource "aws_s3_bucket_public_access_block" "weights" {
  bucket                  = aws_s3_bucket.weights.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Governance layer (line item 2 compliance story). Toggle with var.enable_governance ----

resource "aws_kms_key" "cmi" {
  count                   = var.enable_governance ? 1 : 0
  description             = "CMK for staged model weights + Bedrock artifacts"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "cmi" {
  count         = var.enable_governance ? 1 : 0
  name          = "alias/coaa-bedrock-cmi"
  target_key_id = aws_kms_key.cmi[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "weights" {
  count  = var.enable_governance ? 1 : 0
  bucket = aws_s3_bucket.weights.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cmi[0].arn
    }
  }
}

# PrivateLink interface endpoint so inference traffic never touches the public internet.
resource "aws_security_group" "bedrock_vpce" {
  count       = var.enable_governance && var.governance_vpc_id != "" ? 1 : 0
  name        = "coaa-bedrock-vpce"
  description = "Allow HTTPS to bedrock-runtime VPC endpoint"
  vpc_id      = var.governance_vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "bedrock_runtime" {
  count               = var.enable_governance && var.governance_vpc_id != "" ? 1 : 0
  vpc_id              = var.governance_vpc_id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.governance_subnet_ids
  security_group_ids  = [aws_security_group.bedrock_vpce[0].id]
  private_dns_enabled = true
}

# CloudTrail capturing every InvokeModel as a data event for auditability.
resource "aws_s3_bucket" "trail" {
  count         = var.enable_governance ? 1 : 0
  bucket_prefix = "coaa-bedrock-trail-"
  force_destroy = true
}

data "aws_iam_policy_document" "trail" {
  count = var.enable_governance ? 1 : 0
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]
  }
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count  = var.enable_governance ? 1 : 0
  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail[0].json
}

resource "aws_cloudtrail" "bedrock" {
  count                         = var.enable_governance ? 1 : 0
  name                          = "coaa-bedrock-invoke-trail"
  s3_bucket_name                = aws_s3_bucket.trail[0].id
  include_global_service_events = false
  depends_on                    = [aws_s3_bucket_policy.trail]

  advanced_event_selector {
    name = "Bedrock InvokeModel data events"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::Bedrock::Model"]
    }
  }
}
