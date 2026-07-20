#!/usr/bin/env bash
# Stream HuggingFace model weights directly to S3 with NO local disk staging.
# Each file is piped curl -> `aws s3 cp -` (multipart upload from stdin), then its
# ContentLength is verified against the HF-reported size. Idempotent: files already
# present in S3 at the right size are skipped, so re-runs resume where they left off.
#
# Usage: stream_hf_to_s3.sh <repo_id> <bucket> <prefix> <region>
# Requires env: HF_TOKEN
set -euo pipefail

REPO="${1:?repo_id}"; BUCKET="${2:?bucket}"; PREFIX="${3:?prefix}"; REGION="${4:?region}"
: "${HF_TOKEN:?HF_TOKEN must be set}"

echo "Listing files for ${REPO}..."
files_json="$(curl -sfL -H "Authorization: Bearer ${HF_TOKEN}" \
  "https://huggingface.co/api/models/${REPO}?blobs=true")"

mapfile -t rows < <(python3 -c "
import sys, json
d = json.load(sys.stdin)
for s in d['siblings']:
    f = s['rfilename']; sz = s.get('size', 0)
    if f.endswith(('.safetensors', '.json', '.model')) or f.startswith('tokenizer'):
        print(f + '\t' + str(sz))
" <<<"$files_json")

echo "Will ensure ${#rows[@]} files are present in s3://${BUCKET}/${PREFIX}/"

for row in "${rows[@]}"; do
  f="${row%%$'\t'*}"; sz="${row##*$'\t'}"
  key="${PREFIX}/${f}"

  existing="$(aws s3api head-object --bucket "$BUCKET" --key "$key" --region "$REGION" \
    --query ContentLength --output text 2>/dev/null || echo missing)"
  if [ "$existing" = "$sz" ]; then
    echo "skip  ${f} (already in S3, ${sz} bytes)"
    continue
  fi

  url="https://huggingface.co/${REPO}/resolve/main/${f}"
  attempt=0
  until [ "$attempt" -ge 3 ]; do
    attempt=$((attempt + 1))
    echo "stream ${f} (${sz} bytes) attempt ${attempt}..."
    exp=()
    [ "$sz" -gt 0 ] 2>/dev/null && exp=(--expected-size "$sz")
    if curl -sfL -H "Authorization: Bearer ${HF_TOKEN}" "$url" \
         | aws s3 cp - "s3://${BUCKET}/${key}" --region "$REGION" "${exp[@]}"; then
      got="$(aws s3api head-object --bucket "$BUCKET" --key "$key" --region "$REGION" \
        --query ContentLength --output text 2>/dev/null || echo 0)"
      if [ "$got" = "$sz" ] || [ "$sz" = "0" ]; then
        echo "ok    ${f}"
        break
      fi
      echo "size mismatch ${f}: got=${got} want=${sz}, retrying"
    else
      echo "transfer failed ${f}, retrying"
    fi
    [ "$attempt" -ge 3 ] && { echo "FAILED ${f} after ${attempt} attempts"; exit 1; }
  done
done

echo "ALL FILES PRESENT in s3://${BUCKET}/${PREFIX}/"
