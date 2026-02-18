# Claude Code — Project Instructions

See `AGENTS.md` for full project context, architecture, conventions, and file layout.

## Working in this repo

- Never commit directly to `main` — the `no-commit-to-branch` pre-commit hook will block it
- Work on `develop` or a feature branch; merge via PR
- Before pushing: `pre-commit install --hook-type pre-push` must have been run once to wire up the AI review hook
- Run `pre-commit run --all-files` to validate all hooks locally without committing

## Pre-commit hook pipeline (summary)

Runs at **commit time** (fast, deterministic):
terraform fmt → validate → tflint → terraform-docs → trivy → infracost → file hygiene → gitleaks → checkov

Runs at **push time** (agentic):
`scripts/ai-review.sh` — calls `claude --print` with the branch diff; blocks push on `BLOCK:` response

## Ignore/skip syntax (important — easy to get wrong)

- **Trivy inline**: `#trivy:ignore:AVD-AWS-0011` on the line above the resource
- **Trivy file**: `.trivyignore` — one rule ID per line, always include a comment explaining why
- **Checkov inline**: `#checkov:skip=CKV_AWS_123 reason` (separator is `=` not `:`)
- **Checkov graph checks** (`CKV2_*`): inline skips don't work — use `skip-check` in `.checkov.yml`
- Every ignore/skip must include a documented reason

## AI review script (scripts/ai-review.sh)

When invoked non-interactively as part of the pre-push hook, the script dynamically
discovers context (tech stack, this file, AGENTS.md, pre-commit hooks) and builds the
prompt at runtime — no hardcoded project knowledge in the script itself.

When you receive that prompt:
- Focus only on what static tools cannot catch (intent, logic, architecture, operational gaps)
- Do not re-flag issues the listed pre-commit hooks already cover
- Use the `BLOCK:` / `[BLOCK]` / `[WARN]` / `[INFO]` format specified in the prompt
