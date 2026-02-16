#!/usr/bin/env bash
# Validates IAM identity policies from a Terraform plan JSON file
# using AWS IAM Access Analyzer.
#
# Usage: ./validate-iam-policies.sh <terraform-plan.json>
#
# Exits non-zero if any policy has ERROR or SECURITY_WARNING findings.
# Skips policies with unresolved values (unknown at plan time).

set -euo pipefail

PLAN_JSON="${1:?Usage: $0 <terraform-plan.json>}"
ERRORS=0
CHECKED=0
SKIPPED=0

# Extract identity policies (aws_iam_role_policy, aws_iam_policy)
# from the plan JSON and validate each one.
for row in $(jq -c '.resource_changes[] | select((.type == "aws_iam_role_policy" or .type == "aws_iam_policy") and .change.actions != ["delete"])' "$PLAN_JSON" | base64); do
  decoded=$(echo "$row" | base64 -d)
  address=$(echo "$decoded" | jq -r '.address')
  policy=$(echo "$decoded" | jq -r '.change.after.policy // empty')

  if [[ -z "$policy" ]]; then
    echo "SKIP $address — policy contains unresolved values (unknown at plan time)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "---- $address ----"
  CHECKED=$((CHECKED + 1))

  findings=$(echo "$policy" | aws accessanalyzer validate-policy \
    --policy-type IDENTITY_POLICY \
    --policy-document file:///dev/stdin \
    --output json 2>&1) || true

  count=$(echo "$findings" | jq '.findings | length')
  if [[ "$count" -eq 0 ]]; then
    echo "  OK"
    continue
  fi

  echo "$findings" | jq -r '.findings[] | "  \(.findingType): \(.issueCode) - \(.findingDetails)"'

  if echo "$findings" | jq -e '.findings[] | select(.findingType == "ERROR" or .findingType == "SECURITY_WARNING")' > /dev/null 2>&1; then
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""
echo "Checked: $CHECKED  Skipped: $SKIPPED  Failed: $ERRORS"

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi
