#!/usr/bin/env bash
# lib.sh — shared helpers sourced by generate-docs.sh and ai-review.sh
#
# Requires: REPO_ROOT to be set by the caller before sourcing.

# Comprehensive stack detection — covers IaC, languages, containers, CI
discover_stack() {
  local stack=() files
  files=$(git -C "${REPO_ROOT}" ls-files 2>/dev/null)

  # IaC
  echo "$files" | grep -q '\.tf$'                     && stack+=("Terraform")
  echo "$files" | grep -q '\.pulumi\|Pulumi\.yaml'    && stack+=("Pulumi")
  [[ -f "${REPO_ROOT}/cdk.json" ]]                    && stack+=("AWS CDK")
  echo "$files" | grep -q '\.bicep$'                  && stack+=("Bicep/Azure")
  echo "$files" | grep -q 'ansible'                   && stack+=("Ansible")
  echo "$files" | grep -q 'Chart\.yaml'               && stack+=("Helm")
  echo "$files" | grep -q '\.k8s\.ya\?ml\|kubernetes' && stack+=("Kubernetes")

  # Languages
  [[ -f "${REPO_ROOT}/go.mod" ]]                                              && stack+=("Go")
  [[ -f "${REPO_ROOT}/Cargo.toml" ]]                                          && stack+=("Rust")
  [[ -f "${REPO_ROOT}/package.json" ]]                                        && stack+=("Node.js")
  [[ -f "${REPO_ROOT}/pyproject.toml" || -f "${REPO_ROOT}/requirements.txt" ]] && stack+=("Python")
  [[ -f "${REPO_ROOT}/Gemfile" ]]                                             && stack+=("Ruby")
  [[ -f "${REPO_ROOT}/pom.xml" || -f "${REPO_ROOT}/build.gradle" ]]          && stack+=("Java/JVM")
  echo "$files" | grep -q '\.cs$'                                             && stack+=(".NET")
  echo "$files" | grep -q '\.swift$'                                          && stack+=("Swift")

  # Containers / CI
  [[ -f "${REPO_ROOT}/Dockerfile" || -f "${REPO_ROOT}/docker-compose.yml" ]] && stack+=("Docker")
  [[ -d "${REPO_ROOT}/.github/workflows" ]]                                   && stack+=("GitHub Actions")
  [[ -f "${REPO_ROOT}/.gitlab-ci.yml" ]]                                      && stack+=("GitLab CI")

  local IFS=", "
  echo "${stack[*]:-unknown}"
}

# Read well-known context files capped to avoid prompt bloat
discover_context_files() {
  local out=""
  local candidates=(
    CLAUDE.md AGENTS.md .ai-review.md
    README.md CONTRIBUTING.md ARCHITECTURE.md
    .github/PULL_REQUEST_TEMPLATE.md
    .ai/docs/architecture.md
    .ai/docs/features.md
    .ai/docs/developer-guide.md
    .ai/docs/bug-list.md
  )
  for f in "${candidates[@]}"; do
    local path="${REPO_ROOT}/${f}"
    if [[ -f "$path" ]]; then
      local content
      content=$(head -n 80 "$path")
      out+="### ${f}
${content}

"
    fi
  done
  printf '%s' "$out"
}
