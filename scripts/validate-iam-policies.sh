#!/bin/bash
set -euo pipefail

# This script finds all directories containing Terraform files and runs a local
# IAM policy validation script if it exists.

# Find all unique directories containing .tf files, excluding 'scripts' directories.
for dir in $(find . -name "*.tf" -path "*/scripts" -prune -o -name "*.tf" -exec dirname {} \; | sort -u); do
  # If a local validation script exists in a 'scripts' subdirectory...
  if [ -f "$dir/scripts/validate-iam-local.sh" ]; then
    echo "Running IAM policy validation in $dir..."
    # ...execute it, passing the directory as an argument.
    "$dir/scripts/validate-iam-local.sh" "$dir"
  fi
done
