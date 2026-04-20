#!/usr/bin/env bash
# Restore +x on provider binaries (S3 sync / archive restore often drops execute bit).
# Without this, Terraform fails: fork/exec ... terraform-provider-aws_* permission denied
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "chmod +x terraform-provider-* under $ROOT ..."
find "$ROOT" -name 'terraform-provider-*' -type f -exec chmod +x {} +
echo "Done."
