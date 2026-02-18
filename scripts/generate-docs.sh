#!/usr/bin/env bash
# generate-docs.sh — universal agentic documentation generator
#
# Reads the codebase at runtime, generates 8 standard documents via Gemini CLI,
# and saves them to .ai/docs/ ready for Wiki.js publishing on merge to main.
#
# Usage:  scripts/generate-docs.sh [doc-type] [--auto-commit]
#         doc-type: architecture | features | developer | support |
#                   testing | bugs | performance | ai-plan | all (default)
# Flags:  --auto-commit   commit and push generated docs (used by CI)
#
# Output: .ai/docs/*.md
# Publish: handled by generate-and-publish-docs.yml on merge to main

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

# Shared helpers: discover_stack, discover_context_files
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

# ── parse args ────────────────────────────────────────────────────────────────
TARGET="all"
AUTO_COMMIT=false
for arg in "$@"; do
  case "$arg" in
    --auto-commit) AUTO_COMMIT=true ;;
    *)             TARGET="$arg" ;;
  esac
done

# ── freshness check (interactive only) ───────────────────────────────────────
if [[ "${AUTO_COMMIT}" == "false" ]] && [[ -t 1 ]]; then
  LAST_COMMIT=$(git -C "${REPO_ROOT}" log -1 --format="%H" -- ".ai/docs" 2>/dev/null || true)
  if [[ -n "$LAST_COMMIT" ]]; then
    LAST_TS=$(git -C "${REPO_ROOT}" log -1 --format="%ct" -- ".ai/docs" 2>/dev/null)
    AGE_DAYS=$(( ( $(date +%s) - LAST_TS ) / 86400 ))
    LAST_DATE=$(git -C "${REPO_ROOT}" log -1 --format="%cd" --date=short -- ".ai/docs" 2>/dev/null)

    CHANGED=$(git -C "${REPO_ROOT}" diff --name-only "${LAST_COMMIT}..HEAD" -- \
      '*.tf' '*.py' '*.sh' '*.md' 'Dockerfile*' 'docker-compose*' 2>/dev/null \
      | grep -v '^\.ai/' || true)

    bold ""
    bold "=== Doc Freshness ==="
    info "Last generated: ${LAST_DATE} (${AGE_DAYS} day(s) ago)"

    if [[ -n "$CHANGED" ]]; then
      CHANGED_COUNT=$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ')
      info "Source changes since last generation (${CHANGED_COUNT} file(s)):"
      printf '%s\n' "$CHANGED" | sed 's/^/     /'
      DEFAULT_ANSWER="Y"
    elif (( AGE_DAYS > 14 )); then
      info "No source changes, but docs are ${AGE_DAYS} days old."
      DEFAULT_ANSWER="Y"
    else
      info "Docs are current — ${AGE_DAYS} day(s) old, no source changes."
      DEFAULT_ANSWER="N"
    fi

    printf '\n'
    read -r -p "  Regenerate? [${DEFAULT_ANSWER}] " USER_ANSWER < /dev/tty || USER_ANSWER="${DEFAULT_ANSWER}"
    USER_ANSWER="${USER_ANSWER:-${DEFAULT_ANSWER}}"
    if [[ ! "${USER_ANSWER}" =~ ^[Yy]$ ]]; then
      info "Skipping."
      exit 0
    fi
    bold ""
  fi
fi

TIMEOUT=300  # doc generation needs more time than review

# ── context collection ────────────────────────────────────────────────────────
collect_files() {
  local total="" cap=800
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
CONTEXT=$(discover_context_files)
REPO_NAME=$(basename "${REPO_ROOT}")

# ── gemini call with timeout ──────────────────────────────────────────────────

# Quick preflight — one cheap call to catch quota exhaustion before spawning jobs.
# Exits the whole script with a clear message and reset time if quota is hit.
gemini_preflight() {
  local out
  out=$(gemini -m gemini-2.5-flash -p "Say OK" 2>&1) || {
    if printf '%s' "$out" | grep -qi "exhausted\|quota\|capacity"; then
      local reset
      reset=$(printf '%s' "$out" | grep -oE 'reset after [0-9hm ]+s' | head -1 || true)
      warn "Gemini quota exhausted.${reset:+ Your quota will reset after ${reset}.}"
      exit 1
    fi
  }
}

call_gemini() {
  local prompt_file="$1"
  local err_file
  err_file=$(mktemp)
  trap 'rm -f "${err_file}"; trap - RETURN' RETURN

  # Pipe via stdin to avoid shell-expanding special chars (${var}, backticks)
  # in source file content. -p "" enables headless mode; stdin is the prompt.
  perl -e "
    alarm(${TIMEOUT});
    open(STDIN, '<', \$ARGV[0]) or die \"cannot open: \$!\";
    exec('gemini', '-m', 'gemini-2.5-flash', '-p', '');
  " -- "${prompt_file}" 2>"${err_file}" || {
    local err
    err=$(cat "${err_file}")
    if printf '%s' "$err" | grep -qi "exhausted\|quota\|capacity"; then
      local reset
      reset=$(printf '%s' "$err" | grep -oE 'reset after [0-9hm ]+s' | head -1 || true)
      warn "Gemini quota exhausted.${reset:+ Your quota will reset after ${reset}.}"
      exit 1
    fi
    [[ -s "${err_file}" ]] && warn "$(cat "${err_file}")"
    return 1
  }
}

# ── document generator ────────────────────────────────────────────────────────
generate() {
  local slug="$1"
  local title="$2"
  local files="$3"
  local instruction="$4"

  local output="${DOCS_DIR}/${slug}.md"
  local prompt_file
  prompt_file=$(mktemp)
  trap 'rm -f "${prompt_file}"; trap - RETURN' RETURN

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
- For diagrams, use ASCII art only — do NOT use Mermaid or any fenced code block
  diagram syntax, as the target Wiki.js instance does not support it
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
Include: system overview, ASCII component diagram, data flow end-to-end,
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

FAILED=0

case "${TARGET}" in
  architecture)  doc_architecture  || FAILED=$((FAILED + 1)) ;;
  features)      doc_features      || FAILED=$((FAILED + 1)) ;;
  developer)     doc_developer     || FAILED=$((FAILED + 1)) ;;
  support)       doc_support       || FAILED=$((FAILED + 1)) ;;
  testing)       doc_testing       || FAILED=$((FAILED + 1)) ;;
  bugs)          doc_bugs          || FAILED=$((FAILED + 1)) ;;
  performance)   doc_performance   || FAILED=$((FAILED + 1)) ;;
  ai-plan)       doc_ai_plan       || FAILED=$((FAILED + 1)) ;;
  all)
    gemini_preflight

    if [[ "${CI:-false}" == "true" ]]; then
      # In CI, run sequentially to stay within free-tier rate limits (10 RPM).
      # Parallel mode fires 8 simultaneous requests and exhausts the per-minute quota.
      info "CI detected — running docs sequentially (rate-limit safe)"
      doc_architecture  || FAILED=$((FAILED + 1))
      doc_features      || FAILED=$((FAILED + 1))
      doc_developer     || FAILED=$((FAILED + 1))
      doc_support       || FAILED=$((FAILED + 1))
      doc_testing       || FAILED=$((FAILED + 1))
      doc_bugs          || FAILED=$((FAILED + 1))
      doc_performance   || FAILED=$((FAILED + 1))
      doc_ai_plan       || FAILED=$((FAILED + 1))
    else
      # Locally, run all 8 docs in parallel; capture output per-doc then print in order.
      PARALLEL_OUTDIR=$(mktemp -d)

      doc_architecture > "${PARALLEL_OUTDIR}/1.out" 2>&1 & PIDS=($!)
      doc_features     > "${PARALLEL_OUTDIR}/2.out" 2>&1 & PIDS+=($!)
      doc_developer    > "${PARALLEL_OUTDIR}/3.out" 2>&1 & PIDS+=($!)
      doc_support      > "${PARALLEL_OUTDIR}/4.out" 2>&1 & PIDS+=($!)
      doc_testing      > "${PARALLEL_OUTDIR}/5.out" 2>&1 & PIDS+=($!)
      doc_bugs         > "${PARALLEL_OUTDIR}/6.out" 2>&1 & PIDS+=($!)
      doc_performance  > "${PARALLEL_OUTDIR}/7.out" 2>&1 & PIDS+=($!)
      doc_ai_plan      > "${PARALLEL_OUTDIR}/8.out" 2>&1 & PIDS+=($!)

      for i in "${!PIDS[@]}"; do
        wait "${PIDS[$i]}" || FAILED=$((FAILED + 1))
        cat "${PARALLEL_OUTDIR}/$((i + 1)).out"
      done
      rm -rf "${PARALLEL_OUTDIR}"
    fi
    ;;
  *)
    warn "Unknown doc type: ${TARGET}"
    echo "Valid types: architecture | features | developer | support | testing | bugs | performance | ai-plan | all"
    exit 1
    ;;
esac

bold ""
bold "=== Done ==="

if (( FAILED > 0 )); then
  warn "${FAILED} document(s) failed to generate."
fi

# ── auto-commit ───────────────────────────────────────────────────────────────
if [[ "${AUTO_COMMIT}" == "true" ]]; then
  git -C "${REPO_ROOT}" add "${DOCS_DIR}" 2>/dev/null || true
  if ! git -C "${REPO_ROOT}" diff --cached --quiet 2>/dev/null; then
    git -C "${REPO_ROOT}" commit --no-verify \
      -m "docs: auto-generate documentation [skip ci]"
    REMOTE=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null \
      | cut -d/ -f1)
    REMOTE="${REMOTE:-origin}"
    BRANCH=$(git -C "${REPO_ROOT}" branch --show-current)
    git -C "${REPO_ROOT}" push --no-verify "${REMOTE}" "${BRANCH}"
    info "Docs committed and pushed."
  else
    info "Docs unchanged — nothing to commit."
  fi
else
  info "Review files in ${DOCS_DIR} then commit."
  info "On merge to main, generate-and-publish-docs.yml will push them to Wiki.js."
fi

[[ $FAILED -eq 0 ]]
