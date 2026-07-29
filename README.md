# coaa-bedrock-agents

Reproducible IaC for three "open model on AWS Bedrock + open terminal/agent framework"
deliverables. Terraform owns the cloud-side, stateful pieces (IAM, governance, the
custom-import pipeline scaffolding). Ansible owns everything reproducible and client-side
(agent install, config templating, model-access enablement, smoke tests). Each line item
has one standalone, idempotent playbook.

All three pinned to **`us-east-1`** — the one region that has the managed Qwen models, the
Mantle OpenAI endpoint, **and** Bedrock Custom Model Import.

| # | Model | Hosting | Agent | Playbook |
|---|-------|---------|-------|----------|
| 1 | Qwen3 (Apache-2.0) — `qwen.qwen3-32b-v1:0` | Bedrock **managed** | OpenCode (MIT) | `ansible/01-qwen3-opencode.yml` |
| 2 | DeepSeek-R1-Distill-Llama-70B (MIT) | Bedrock **Custom Import** | LangGraph (MIT) | `ansible/02-deepseek-langgraph.yml` |
| 3 | Qwen3-Coder (Apache-2.0) — `qwen.qwen3-coder-30b-a3b-v1:0` | Bedrock **managed** | omp / oh-my-pi (MIT) | `ansible/03-qwen3coder-omp.yml` |

## Why these exact choices

- **Verified against account `376129860391` (profile `coaa`)**: `qwen.qwen3-32b-v1:0`,
  `qwen.qwen3-235b-a22b-2507-v1:0`, `qwen.qwen3-coder-*` and `deepseek.v3.2` are all live.
- **DeepSeek V3.2 cannot be Custom-Imported** — Bedrock Custom Model Import only accepts
  Llama / Mistral / Mixtral / Qwen / Flan / GPT-OSS architectures, not V3.2's 671B MoE.
  We import `deepseek-ai/DeepSeek-R1-Distill-Llama-70B` (Llama arch, MIT, DeepSeek weights)
  so the BYO-open-weights compliance story is literally true. Managed `deepseek.v3.2` is
  available too and can be swapped in via `group_vars` if the client accepts managed hosting.
- **Custom Model Import is only in `us-east-1` / `us-west-2`** — so `us-east-1` is the single
  region that works for all three line items, and everything is pinned there.
- **Bedrock "Mantle" OpenAI-compatible endpoint** (`https://bedrock-mantle.<region>.api.aws/v1`)
  is how OpenCode and omp connect with zero adapter code.

## Quick start

```bash
# 0. secrets (never committed)
cp secrets/secrets.example.yml secrets/secrets.yml   # then fill in HF token, or use vault
ansible-vault encrypt secrets/secrets.yml            # optional but recommended

# 1. baseline + governance infra
cd terraform && terraform init && terraform apply
cd ..

# 2. install collections/deps
ansible-galaxy collection install -r ansible/requirements.yml

# 3. run any line item (idempotent, standalone). Pass -e for the terraform outputs LI2 needs.
ansible-playbook ansible/01-qwen3-opencode.yml
ansible-playbook ansible/03-qwen3coder-omp.yml

# Line item 2 is two steps. 02a streams ~141 GB HF -> S3 from an ephemeral EC2 instance on
# AWS's backbone (never touches your uplink), then self-terminates. 02 runs the Custom Model
# Import job + LangGraph app; its own local-streaming step no-ops once 02a has staged S3.
WB=$(cd terraform && terraform output -raw weights_bucket)
RA=$(cd terraform && terraform output -raw cmi_import_role_arn)
ansible-playbook ansible/02a-ec2-import-weights.yml -e weights_bucket=$WB   # AWS-side transfer
ansible-playbook ansible/02-deepseek-langgraph.yml  -e weights_bucket=$WB -e cmi_import_role_arn=$RA
```

## Security

- The HuggingFace token was shared in plaintext during setup — **rotate it** at
  https://huggingface.co/settings/tokens and store the new one only in `secrets/secrets.yml`
  (gitignored) or an ansible-vault file. It is never written to a committed file.
- IAM policies are scoped to specific model / imported-model ARNs — no `bedrock:*` wildcards.
- Line item 2 routes inference through a `bedrock-runtime` PrivateLink VPC endpoint and logs
  every `InvokeModel` as a CloudTrail data event (see `terraform/governance.tf`).
# proj-ai-stack-challenge

## License

[MIT](LICENSE) © 2026 Martin Forde <mforde84@gmail.com>, [Blik Labs](https://bliklabs.com).
