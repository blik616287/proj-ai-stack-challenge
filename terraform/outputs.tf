output "region" {
  value = var.region
}

output "account_id" {
  value = local.account_id
}

output "mantle_base_url" {
  description = "OpenAI-compatible endpoint for OpenCode + omp"
  value       = "https://bedrock-mantle.${var.region}.api.aws/v1"
}

output "qwen3_model_id" {
  value = var.qwen3_model_id
}

output "qwen3_coder_model_id" {
  value = var.qwen3_coder_model_id
}

output "agent_invoke_role_arn" {
  value = aws_iam_role.agent_invoke.arn
}

output "cmi_import_role_arn" {
  description = "Role Bedrock assumes to read weights during CreateModelImportJob"
  value       = aws_iam_role.cmi_import.arn
}

output "weights_bucket" {
  description = "S3 bucket to stage DeepSeek weights into before import"
  value       = aws_s3_bucket.weights.bucket
}

output "imported_model_name" {
  value = var.imported_model_name
}

output "kms_key_arn" {
  value = var.enable_governance ? aws_kms_key.cmi[0].arn : ""
}

output "importer_instance_profile" {
  description = "Instance profile for the EC2 weights importer (line item 2)"
  value       = aws_iam_instance_profile.importer.name
}

output "importer_ssm_token_name" {
  value = var.importer_ssm_token_name
}
