#!/usr/bin/env bash
# generate-docs.sh — universal agentic documentation generator
#
# Reads the codebase at runtime, generates core documents via Gemini CLI,
# and saves them to .ai/docs/ ready for Wiki.js publishing on merge to main.
#
# Usage:  scripts/generate-docs.sh [doc-type] [--auto-commit]
#         doc-type: architecture | developer | testing | all (default)
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
      '*.tf' '*.py' '*.sh' '*.md' '*.yml' '*.yaml' 'Dockerfile*' 'docker-compose*' 2>/dev/null \
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

## Critical constraint
Output ONLY the raw markdown text as your response. Do not use any tools,
file operations, shell commands, or external actions of any kind. Do not
attempt to write, create, or save files. Your entire response is the document.

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
  files=$(collect_files '\.tf$' 'entrypoint.*\.py$' 'main\.py$' 'docker-compose.*\.ya?ml$' 'Dockerfile' \
                        '\.sh$' '\.github/workflows/.*\.ya?ml$' '\.pre-commit-config\.ya?ml$')
  generate "architecture" "Architecture Overview" "$files" \
    "Generate an architecture overview document for a technical audience.
Include: system overview, ASCII component diagram, data flow end-to-end,
AWS services and their roles (if applicable), infrastructure design decisions, deployment model,
environment differences (dev/prod if visible), and any notable design patterns."
}

doc_developer() {
  header "Developer Guide"
  local files
  files=$(collect_files '\.py$' '\.tf$' 'docker.*\.ya?ml$' 'Dockerfile' 'pyproject\.toml$' \
                        'requirements.*\.txt$' '\.pre-commit-config\.ya?ml$' \
                        '\.sh$' '\.github/workflows/.*\.ya?ml$' 'package\.json$' 'Makefile$')
  generate "developer-guide" "Developer Guide" "$files" \
    "Generate a developer guide for engineers onboarding to this codebase.
Include: repository structure, local setup instructions, environment variables and config,
how to run the application locally, how to run tests, deployment process, branching and
PR conventions, code architecture walkthrough (key modules and their responsibilities),
and common development tasks."
}

doc_testing() {
  header "Test Procedures"
  local files
  files=$(collect_files 'test.*\.py$' '.*_test\.py$' 'tftest\.hcl$' '.*spec.*' \
                        'test.*\.sh$' '.*_test\.sh$' '\.bats$')
  generate "testing" "Test Procedures" "$files" \
    "Generate a testing document for a QA or developer audience.
Include: current test coverage (what is tested, what is not), how to run existing tests,
test environment requirements, a description of each test file and what it validates,
gaps in coverage, and recommendations for additional tests that would improve confidence."
}

# ── helper: does this repo have test files? ───────────────────────────────────
has_tests() {
  git -C "${REPO_ROOT}" ls-files 2>/dev/null \
    | grep -qE 'test.*\.(py|sh|hcl|bats)$|.*_test\.(py|sh)$|.*spec\.'
}

# ── main ──────────────────────────────────────────────────────────────────────
bold ""
bold "=== Documentation Generator (Gemini CLI) ==="
info "Repo: ${REPO_NAME} | Stack: ${STACK} | Output: ${DOCS_DIR}"
bold ""

FAILED=0

case "${TARGET}" in
  architecture)  doc_architecture  || FAILED=$((FAILED + 1)) ;;
  developer)     doc_developer     || FAILED=$((FAILED + 1)) ;;
  testing)       doc_testing       || FAILED=$((FAILED + 1)) ;;
  all)
    gemini_preflight
    doc_architecture || FAILED=$((FAILED + 1))
    doc_developer    || FAILED=$((FAILED + 1))
    if has_tests; then
      doc_testing    || FAILED=$((FAILED + 1))
    else
      info "No test files found — skipping Test Procedures"
    fi
    ;;
  *)
    warn "Unknown doc type: ${TARGET}"
    echo "Valid types: architecture | developer | testing | all"
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
