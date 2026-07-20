# In-AWS weights importer (line item 2): an EC2 instance profile that lets an ephemeral
# instance stream HuggingFace weights straight into the S3 weights bucket on AWS's backbone
# — no bytes cross the operator's local connection. The instance is launched + torn down by
# ansible/02a-ec2-import-weights.yml.

data "aws_iam_policy_document" "importer_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "importer" {
  name               = "coaa-cmi-importer"
  assume_role_policy = data.aws_iam_policy_document.importer_assume.json
}

data "aws_iam_policy_document" "importer" {
  statement {
    sid = "S3Write"
    actions = [
      "s3:PutObject", "s3:GetObject", "s3:ListBucket",
      "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
    ]
    resources = [aws_s3_bucket.weights.arn, "${aws_s3_bucket.weights.arn}/*"]
  }

  statement {
    sid       = "SsmToken"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter${var.importer_ssm_token_name}"]
  }

  # KMS is only needed when the weights bucket is CMK-encrypted (governance on).
  dynamic "statement" {
    for_each = var.enable_governance ? [1] : []
    content {
      sid       = "Kms"
      actions   = ["kms:GenerateDataKey", "kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      resources = [aws_kms_key.cmi[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "importer" {
  name   = "importer"
  role   = aws_iam_role.importer.id
  policy = data.aws_iam_policy_document.importer.json
}

resource "aws_iam_instance_profile" "importer" {
  name = "coaa-cmi-importer"
  role = aws_iam_role.importer.name
}
