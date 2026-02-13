#!/usr/bin/env bash
# Wrapper for pre-commit: generates a terraform plan with placeholder
# variables, then validates IAM policies via Access Analyzer.
#
# Usage: ./validate-iam-local.sh <terraform-dir>

set -euo pipefail

DIR="${1:?Usage: $0 <terraform-dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLAN_FILE=$(mktemp)
PLAN_JSON=$(mktemp)
trap 'rm -f "$PLAN_FILE" "$PLAN_JSON"' EXIT

terraform -chdir="$DIR" plan \
  -var="domain_name=placeholder.example.com" \
  -var="access_token=placeholder" \
  -input=false \
  -out="$PLAN_FILE" \
  > /dev/null 2>&1

terraform -chdir="$DIR" show -json "$PLAN_FILE" > "$PLAN_JSON"

"$SCRIPT_DIR/validate-iam-policies.sh" "$PLAN_JSON"
