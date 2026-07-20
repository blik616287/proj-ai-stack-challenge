variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "coaa"
}

variable "region" {
  description = "Single region for all three line items (must support managed Qwen, Mantle, and Custom Model Import)."
  type        = string
  default     = "us-east-1"
}

variable "qwen3_model_id" {
  description = "Managed Qwen3 model id (line item 1)"
  type        = string
  default     = "qwen.qwen3-32b-v1:0"
}

variable "qwen3_coder_model_id" {
  description = "Managed Qwen3-Coder model id (line item 3)"
  type        = string
  default     = "qwen.qwen3-coder-30b-a3b-v1:0"
}

variable "imported_model_name" {
  description = "Name for the Custom-Imported DeepSeek model (line item 2)"
  type        = string
  default     = "deepseek-r1-distill-llama-70b"
}

variable "enable_governance" {
  description = "Provision the PrivateLink VPC endpoint + KMS + CloudTrail governance layer (line item 2)"
  type        = bool
  default     = true
}

variable "governance_vpc_id" {
  description = "Existing VPC id for the bedrock-runtime PrivateLink endpoint (line item 2). Leave empty to skip endpoint creation."
  type        = string
  default     = ""
}

variable "governance_subnet_ids" {
  description = "Subnet ids for the interface VPC endpoint"
  type        = list(string)
  default     = []
}

variable "importer_ssm_token_name" {
  description = "SSM SecureString parameter name holding the HF token for the EC2 weights importer"
  type        = string
  default     = "/coaa/hf_token"
}
