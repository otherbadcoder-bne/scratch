#!/usr/bin/env bash
# ai-review.sh — universal agentic pre-push review via Gemini CLI
#
# Dynamically discovers project context at runtime (tech stack, existing docs,
# active pre-commit hooks). No hardcoded project knowledge — drop into any repo.
#
# Usage (automatic):  pre-commit install --hook-type pre-push
# Usage (manual):     scripts/ai-review.sh
# Skip:               git push --no-verify
# Change base:        AI_REVIEW_BASE=develop git push

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn()  { printf '\033[33m⚠  %s\033[0m\n' "$*" >&2; }
info()  { printf '\033[36m   %s\033[0m\n' "$*"; }

# ── guard: gemini must be available ──────────────────────────────────────────
if ! command -v gemini &>/dev/null; then
  warn "gemini CLI not found — skipping AI review (install: https://github.com/google-gemini/gemini-cli)"
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="${AI_REVIEW_BASE:-main}"

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  exit 0
fi

# ── context discovery ─────────────────────────────────────────────────────────

# 1. Read existing human-written context files (capped to avoid prompt bloat)
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
  echo "$out"
}

# 2. Detect tech stack from tracked files and well-known config files
discover_stack() {
  local stack=()
  local files
  files=$(git -C "${REPO_ROOT}" ls-files 2>/dev/null)

  # IaC
  echo "$files" | grep -q '\.tf$'          && stack+=("Terraform")
  echo "$files" | grep -q '\.pulumi\|Pulumi\.yaml' && stack+=("Pulumi")
  [[ -f "${REPO_ROOT}/cdk.json" ]]          && stack+=("AWS CDK")
  echo "$files" | grep -q '\.bicep$'        && stack+=("Bicep/Azure")
  echo "$files" | grep -q 'ansible'         && stack+=("Ansible")
  echo "$files" | grep -q 'Chart\.yaml'     && stack+=("Helm")
  echo "$files" | grep -q '\.k8s\.ya\?ml\|kubernetes' && stack+=("Kubernetes")

  # Languages
  [[ -f "${REPO_ROOT}/go.mod" ]]            && stack+=("Go")
  [[ -f "${REPO_ROOT}/Cargo.toml" ]]        && stack+=("Rust")
  [[ -f "${REPO_ROOT}/package.json" ]]      && stack+=("Node.js")
  [[ -f "${REPO_ROOT}/pyproject.toml" || -f "${REPO_ROOT}/requirements.txt" ]] && stack+=("Python")
  [[ -f "${REPO_ROOT}/Gemfile" ]]           && stack+=("Ruby")
  [[ -f "${REPO_ROOT}/pom.xml" || -f "${REPO_ROOT}/build.gradle" ]] && stack+=("Java/JVM")
  echo "$files" | grep -q '\.cs$'           && stack+=(".NET")
  echo "$files" | grep -q '\.rs$' && [[ ! " ${stack[*]} " =~ "Rust" ]] && stack+=("Rust")
  echo "$files" | grep -q '\.swift$'        && stack+=("Swift")

  # Containers / CI
  [[ -f "${REPO_ROOT}/Dockerfile" || -f "${REPO_ROOT}/docker-compose.yml" ]] && stack+=("Docker")
  [[ -d "${REPO_ROOT}/.github/workflows" ]] && stack+=("GitHub Actions")
  [[ -f "${REPO_ROOT}/.gitlab-ci.yml" ]]    && stack+=("GitLab CI")

  local IFS=", "
  echo "${stack[*]:-unknown}"
}

# 3. Extract hook IDs/names from .pre-commit-config.yaml so Claude doesn't repeat them
discover_precommit_hooks() {
  local config="${REPO_ROOT}/.pre-commit-config.yaml"
  [[ ! -f "$config" ]] && echo "" && return

  grep -E '^\s+- id:|^\s+name:' "$config" \
    | sed 's/.*id: //; s/.*name: //' \
    | sort -u \
    | grep -v '^ai.review$' \
    | paste -sd ', ' -
}

# 4. Lightweight file tree for structural context
discover_file_tree() {
  git -C "${REPO_ROOT}" ls-files 2>/dev/null \
    | grep -v '^\.' \
    | head -n 60 \
    | sed "s|^|  |"
}

# ── gather ────────────────────────────────────────────────────────────────────
info "Discovering project context..."

CONTEXT_FILES=$(discover_context_files)
STACK=$(discover_stack)
PRECOMMIT_HOOKS=$(discover_precommit_hooks)
FILE_TREE=$(discover_file_tree)
REPO_NAME=$(basename "${REPO_ROOT}")

DIFF=$(git diff "${BASE_BRANCH}...HEAD" 2>/dev/null || true)
COMMIT_LOG=$(git log "${BASE_BRANCH}...HEAD" --oneline 2>/dev/null || true)

if [[ -z "$DIFF" ]]; then
  info "No changes vs ${BASE_BRANCH} — skipping AI review"
  exit 0
fi

# Cap diff size
DIFF_CHARS=${#DIFF}
if (( DIFF_CHARS > 40000 )); then
  DIFF="(truncated — full diff is ${DIFF_CHARS} chars; showing first 40 000)
${DIFF:0:40000}"
fi
DIFF_LINES=$(echo "$DIFF" | wc -l | tr -d ' ')

# ── prompt ────────────────────────────────────────────────────────────────────
PROMPT=$(cat <<PROMPT
You are performing a pre-push code review. Reason about what static analysis and linters cannot catch.

## Discovered project context

**Repository:** ${REPO_NAME}
**Detected stack:** ${STACK}

### File tree (sample)
${FILE_TREE}

${CONTEXT_FILES:+### Human-written context files (auto-discovered)
${CONTEXT_FILES}}

## What has already run automatically — do NOT re-flag these
${PRECOMMIT_HOOKS:+Pre-commit hooks already executed this commit: ${PRECOMMIT_HOOKS}.
Assume these passed. Do not repeat findings they would have caught.}
${PRECOMMIT_HOOKS:-No pre-commit config detected. Apply general best practices for the detected stack.}

## Your review focus — what static tools miss
1. **Intent vs implementation** — does the change do what the commit messages describe?
2. **Logic and semantic errors** — code that is syntactically valid but behaviourally wrong
3. **Security reasoning** — policy or permission logic that passes rule-checkers but violates least-privilege or defence-in-depth in context
4. **Architectural drift** — patterns inconsistent with what the rest of the codebase establishes
5. **Operational gaps** — missing observability, silent failure modes, no rollback path, new SPOFs
6. **Surprising side effects** — changes that affect more than the author likely intended
7. **Stack-specific pitfalls** — known gotchas for: ${STACK}

## Commits being pushed
${COMMIT_LOG}

## Diff (${DIFF_LINES} lines)
\`\`\`
${DIFF}
\`\`\`

## Response format
- Bullet points only, no preamble
- Tag every finding: [BLOCK] [WARN] [INFO]
- If blocking issues exist, your first line must be exactly: BLOCK: <one-line reason>
- If nothing to flag: respond with exactly: LGTM
PROMPT
)

# ── call gemini ───────────────────────────────────────────────────────────────
bold ""
bold "=== AI Review (Gemini CLI) ==="
info "Repo: ${REPO_NAME} | Stack: ${STACK} | Branch: ${CURRENT_BRANCH} vs ${BASE_BRANCH} | ${DIFF_LINES} lines"
echo ""

# Write prompt to temp file — avoids pipe/TTY detection issues with gemini CLI
PROMPT_FILE=$(mktemp /tmp/ai-review-prompt.XXXXXX)
printf '%s' "$PROMPT" > "${PROMPT_FILE}"
trap 'rm -f "${PROMPT_FILE}"' EXIT

# macOS-compatible timeout via perl (no GNU coreutils required)
TIMEOUT=120
RESULT=$(perl -e "alarm(${TIMEOUT}); exec(@ARGV)" -- gemini -p "$(cat "${PROMPT_FILE}")" 2>/dev/null) || {
  CODE=$?
  if [[ $CODE -eq 142 ]]; then
    warn "gemini timed out after ${TIMEOUT}s — skipping AI review (push continues)"
  else
    warn "gemini returned non-zero (exit ${CODE}) — skipping AI review (push continues)"
  fi
  exit 0
}

echo "$RESULT"
echo ""
bold "=============================="
echo ""

# ── persist to .ai/review-log/ ───────────────────────────────────────────────
SHA=$(git rev-parse --short HEAD)
LOG_DIR="${REPO_ROOT}/.ai/review-log"
# Sanitise branch name for use in filename
SAFE_BRANCH="${CURRENT_BRANCH//\//-}"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d)-${SAFE_BRANCH}-${SHA}.md"

mkdir -p "${LOG_DIR}"

# Use printf to avoid heredoc issues with special characters in $RESULT
{
  printf '# AI Review — %s @ %s\n' "${CURRENT_BRANCH}" "${SHA}"
  printf 'Date: %s\n' "$(date -u +"%Y-%m-%d %H:%M UTC")"
  printf 'Stack: %s\n' "${STACK}"
  printf 'Diff: %s lines vs %s\n\n' "${DIFF_LINES}" "${BASE_BRANCH}"
  printf '## Commits\n%s\n\n' "${COMMIT_LOG}"
  printf '## Findings\n%s\n' "${RESULT}"
} > "${LOG_FILE}" || warn "Could not write review log to ${LOG_FILE}"

[[ -f "${LOG_FILE}" ]] && info "Review saved → ${LOG_FILE}"

# ── gate ──────────────────────────────────────────────────────────────────────
if echo "$RESULT" | head -1 | grep -q "^BLOCK:"; then
  echo "Push blocked by AI review. Fix the issue above, then push again."
  echo "To override: git push --no-verify"
  exit 1
fi

exit 0
