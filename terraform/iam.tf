data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # ARNs the agents are allowed to invoke. Managed models are addressed by foundation-model ARN;
  # the imported model by its imported-model ARN (created out-of-band by the import job).
  managed_model_arns = [
    "arn:aws:bedrock:${var.region}::foundation-model/${var.qwen3_model_id}",
    "arn:aws:bedrock:${var.region}::foundation-model/${var.qwen3_coder_model_id}",
  ]
  imported_model_arn = "arn:aws:bedrock:${var.region}:${local.account_id}:imported-model/*"
}

# ---- Role the client agents assume to call Bedrock (least-privilege invoke) ----
data "aws_iam_policy_document" "agent_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "agent_invoke" {
  name               = "BedrockAgentInvoke"
  assume_role_policy = data.aws_iam_policy_document.agent_assume.json
}

data "aws_iam_policy_document" "agent_invoke" {
  statement {
    sid = "InvokeManagedAndImported"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = concat(local.managed_model_arns, [local.imported_model_arn])
  }
  statement {
    sid       = "ListForSmokeTests"
    actions   = ["bedrock:ListFoundationModels", "bedrock:ListImportedModels", "bedrock:GetImportedModel"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "agent_invoke" {
  name   = "bedrock-invoke"
  role   = aws_iam_role.agent_invoke.id
  policy = data.aws_iam_policy_document.agent_invoke.json
}

# ---- Execution role Bedrock assumes to read weights from S3 during the import job ----
data "aws_iam_policy_document" "import_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "cmi_import" {
  name               = "BedrockCustomModelImport"
  assume_role_policy = data.aws_iam_policy_document.import_assume.json
}

data "aws_iam_policy_document" "cmi_import" {
  statement {
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.weights.arn, "${aws_s3_bucket.weights.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = var.enable_governance ? [aws_kms_key.cmi[0].arn] : ["*"]
  }
}

resource "aws_iam_role_policy" "cmi_import" {
  name   = "read-weights"
  role   = aws_iam_role.cmi_import.id
  policy = data.aws_iam_policy_document.cmi_import.json
}
