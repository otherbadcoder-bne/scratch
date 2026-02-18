#!/usr/bin/env bash
# generate-docs.sh — universal agentic documentation generator
#
# Reads the codebase at runtime, generates 8 standard documents via Gemini CLI,
# and saves them to .ai/docs/ ready for Wiki.js publishing on merge to main.
#
# Usage:  scripts/generate-docs.sh [doc-type]
#         doc-type: architecture | features | developer | support |
#                   testing | bugs | performance | ai-plan | all (default)
#
# Output: .ai/docs/*.md
# Publish: handled by publish-docs.yml on merge to main

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m⚠  %s\033[0m\n' "$*" >&2; }
info()  { printf '\033[36m   %s\033[0m\n' "$*"; }
ok()    { printf '\033[32m✓  %s\033[0m\n' "$*"; }
header(){ printf '\033[1;34m\n[%s]\033[0m\n' "$*"; }

# ── guard ─────────────────────────────────────────────────────────────────────
if ! command -v gemini &>/dev/null; then
  warn "gemini CLI not found (install: https://github.com/google-gemini/gemini-cli)"
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
DOCS_DIR="${REPO_ROOT}/.ai/docs"
mkdir -p "${DOCS_DIR}"

TARGET="${1:-all}"
TIMEOUT=300  # doc generation needs more time than review

# ── context discovery (same as ai-review.sh) ─────────────────────────────────

discover_stack() {
  local stack=() files
  files=$(git -C "${REPO_ROOT}" ls-files 2>/dev/null)

  echo "$files" | grep -q '\.tf$'                                          && stack+=("Terraform")
  [[ -f "${REPO_ROOT}/go.mod" ]]                                           && stack+=("Go")
  [[ -f "${REPO_ROOT}/Cargo.toml" ]]                                       && stack+=("Rust")
  [[ -f "${REPO_ROOT}/package.json" ]]                                     && stack+=("Node.js")
  [[ -f "${REPO_ROOT}/pyproject.toml" || -f "${REPO_ROOT}/requirements.txt" ]] && stack+=("Python")
  [[ -f "${REPO_ROOT}/Gemfile" ]]                                          && stack+=("Ruby")
  [[ -f "${REPO_ROOT}/pom.xml" || -f "${REPO_ROOT}/build.gradle" ]]       && stack+=("Java/JVM")
  [[ -f "${REPO_ROOT}/Dockerfile" || -f "${REPO_ROOT}/docker-compose.yml" ]] && stack+=("Docker")
  [[ -d "${REPO_ROOT}/.github/workflows" ]]                                && stack+=("GitHub Actions")
  [[ -f "${REPO_ROOT}/cdk.json" ]]                                         && stack+=("AWS CDK")

  local IFS=", "; echo "${stack[*]:-unknown}"
}

read_context_files() {
  local out=""
  for f in AGENTS.md README.md CONTRIBUTING.md ARCHITECTURE.md; do
    [[ -f "${REPO_ROOT}/${f}" ]] && out+="$(head -n 80 "${REPO_ROOT}/${f}")"$'\n\n'
  done
  printf '%s' "$out"
}

collect_files() {
  # Collect content of tracked files matching given patterns, capped per file
  local total="" cap=800  # lines per file
  for pattern in "$@"; do
    while IFS= read -r f; do
      [[ -f "${REPO_ROOT}/${f}" ]] || continue
      total+="### ${f}"$'\n'
      total+='```'$'\n'
      total+="$(head -n ${cap} "${REPO_ROOT}/${f}")"$'\n'
      total+='```'$'\n\n'
    done < <(git -C "${REPO_ROOT}" ls-files "${REPO_ROOT}" 2>/dev/null | grep -E "${pattern}" | head -n 20)
  done
  printf '%s' "$total"
}

STACK=$(discover_stack)
CONTEXT=$(read_context_files)
REPO_NAME=$(basename "${REPO_ROOT}")

# ── gemini call with timeout ──────────────────────────────────────────────────
call_gemini() {
  local prompt_file="$1"
  perl -e "alarm(${TIMEOUT}); exec(@ARGV)" -- \
    gemini -p "$(cat "${prompt_file}")" 2>/dev/null
}

# ── document generator ────────────────────────────────────────────────────────
generate() {
  local slug="$1"      # filename stem
  local title="$2"     # human title for output
  local files="$3"     # pre-collected file content
  local instruction="$4"  # what to generate

  local output="${DOCS_DIR}/${slug}.md"
  local prompt_file
  prompt_file=$(mktemp /tmp/gendoc-prompt.XXXXXX)
  trap 'rm -f "${prompt_file}"' RETURN

  cat > "${prompt_file}" << PROMPT
You are a technical writer generating documentation for a software project.

## Project
Repository: ${REPO_NAME}
Stack: ${STACK}

## Project context
${CONTEXT}

## Source files
${files}

## Your task
${instruction}

## Output format
- Write in clean Markdown suitable for a Wiki.js page
- Use ## for sections, ### for subsections
- Be accurate — only describe what you can see in the source files
- Do not speculate about features not evidenced in the code
- Audience and tone are specified in the task above
PROMPT

  info "Generating: ${title}..."
  local result
  result=$(call_gemini "${prompt_file}") || {
    warn "Gemini failed for '${title}' — skipping"
    return 1
  }

  printf '%s\n' "${result}" > "${output}"
  ok "${title} → ${output}"
}

# ── document definitions ──────────────────────────────────────────────────────

doc_architecture() {
  header "Architecture Overview"
  local files
  files=$(collect_files '\.tf$' 'entrypoint.*\.py$' 'main\.py$' 'docker-compose.*\.ya?ml$' 'Dockerfile')
  generate "architecture" "Architecture Overview" "$files" \
    "Generate an architecture overview document for a technical audience.
Include: system overview, component diagram (ASCII or Mermaid), data flow end-to-end,
AWS services and their roles, infrastructure design decisions, deployment model,
environment differences (dev/prod if visible), and any notable design patterns."
}

doc_features() {
  header "Feature List"
  local files
  files=$(collect_files 'main\.py$' 'config\.py$' '\.tf$' 'README\.md$')
  generate "features" "Feature List" "$files" \
    "Generate a feature list document for a Product and Marketing audience — no code, no jargon.
Include: what the product does in plain English, key capabilities grouped by theme,
integration points with external systems (named clearly), configuration options visible
to end users, and operational behaviours (notifications, error handling, etc.)."
}

doc_developer() {
  header "Developer Guide"
  local files
  files=$(collect_files '\.py$' '\.tf$' 'docker.*\.ya?ml$' 'Dockerfile' 'pyproject\.toml$' 'requirements.*\.txt$' '\.pre-commit-config\.yaml$')
  generate "developer-guide" "Developer Guide" "$files" \
    "Generate a developer guide for engineers onboarding to this codebase.
Include: repository structure, local setup instructions, environment variables and config,
how to run the application locally, how to run tests, deployment process, branching and
PR conventions, code architecture walkthrough (key modules and their responsibilities),
and common development tasks."
}

doc_support() {
  header "Support Guide"
  local files
  files=$(collect_files 'traceback.*\.py$' 'email.*\.py$' 'logger\.py$' 'config\.py$' 'main\.py$')
  generate "support-guide" "Support Guide" "$files" \
    "Generate a support guide for a support team with no deep technical background.
Include: how the system works in plain language, what can go wrong and why,
how to identify and interpret errors or failure states, what actions support can take
vs what requires a developer, key log/monitoring locations, and an FAQ of common issues."
}

doc_testing() {
  header "Test Procedures"
  local files
  files=$(collect_files 'test.*\.py$' '.*_test\.py$' 'tftest\.hcl$' '.*spec.*')
  generate "testing" "Test Procedures" "$files" \
    "Generate a testing document for a QA or developer audience.
Include: current test coverage (what is tested, what is not), how to run existing tests,
test environment requirements, a description of each test file and what it validates,
gaps in coverage, and recommendations for additional tests that would improve confidence."
}

doc_bugs() {
  header "Bug List & Recommendations"
  local files
  files=$(collect_files '\.py$' '\.tf$' '\.sh$')
  generate "bug-list" "Bug List & Recommendations" "$files" \
    "Review the codebase for bugs, risks, and code quality issues.
For each finding include: description, affected file and line if possible, severity
(Critical/High/Medium/Low), and a recommended fix. Group by severity.
Also include a section on technical debt and code quality patterns worth addressing."
}

doc_performance() {
  header "Performance Improvements"
  local files
  files=$(collect_files 'entrypoint.*\.py$' 'main\.py$' '\.tf$' 'config\.py$' 'docker-compose.*\.ya?ml$')
  generate "performance" "Performance Improvements" "$files" \
    "Analyse the codebase for performance characteristics and improvement opportunities.
Include: current performance profile (timeouts, resource allocations, concurrency model),
identified bottlenecks or risks, specific recommendations with rationale, infrastructure
sizing observations, and any quick wins vs longer-term improvements."
}

doc_ai_plan() {
  header "AI Agentic Development Plan"
  local files
  files=$(collect_files '\.py$' '\.tf$' 'pyproject\.toml$' 'requirements.*\.txt$')
  generate "ai-development-plan" "AI Agentic Development Plan" "$files" \
    "Generate a plan for adopting AI-assisted and agentic development practices in this project.
Include: current AI/LLM usage in the codebase, opportunities to expand AI assistance
(code generation, review, testing, documentation), recommended tooling (Claude Code,
Gemini CLI, etc.), proposed workflow changes, risks and mitigations, and a phased
roadmap from current state to a mature AI-augmented development practice."
}

# ── main ──────────────────────────────────────────────────────────────────────
bold ""
bold "=== Documentation Generator (Gemini CLI) ==="
info "Repo: ${REPO_NAME} | Stack: ${STACK} | Output: ${DOCS_DIR}"
bold ""

case "${TARGET}" in
  architecture)   doc_architecture ;;
  features)       doc_features ;;
  developer)      doc_developer ;;
  support)        doc_support ;;
  testing)        doc_testing ;;
  bugs)           doc_bugs ;;
  performance)    doc_performance ;;
  ai-plan)        doc_ai_plan ;;
  all)
    doc_architecture
    doc_features
    doc_developer
    doc_support
    doc_testing
    doc_bugs
    doc_performance
    doc_ai_plan
    ;;
  *)
    warn "Unknown doc type: ${TARGET}"
    echo "Valid types: architecture | features | developer | support | testing | bugs | performance | ai-plan | all"
    exit 1
    ;;
esac

bold ""
bold "=== Done ==="
info "Review files in ${DOCS_DIR} before committing."
info "On merge to main, publish-docs.yml will push them to Wiki.js."
