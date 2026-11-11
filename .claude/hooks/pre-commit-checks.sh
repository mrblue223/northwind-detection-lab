#!/usr/bin/env bash
# PreToolUse hook for the Bash tool.
#
# Blocks `git commit` (exit 2) unless `terraform fmt -check`, `tflint`, and
# `ansible-lint` all pass. Any other command passes straight through (exit 0).
#
# Fails CLOSED: if a required linter is not installed, the commit is blocked
# with an install hint, rather than silently skipping enforcement.
#
# Contract: reads the hook JSON payload on stdin, writes blocking reasons to
# stderr, and exits 2 to deny the tool call. Exit 0 allows it.

set -uo pipefail

payload="$(cat)"

# Extract the Bash command from the payload (tolerate missing jq).
if command -v jq >/dev/null 2>&1; then
  command_str="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
else
  command_str="$(printf '%s' "$payload" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
fi

# Only gate actual `git commit` invocations. Match `git ... commit` as a
# subcommand while avoiding obvious false positives like `git log`.
if ! printf '%s' "$command_str" | grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

# Resolve repo root (the hook may run from anywhere).
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT" || { echo "pre-commit-checks: cannot cd to repo root ($REPO_ROOT)" >&2; exit 2; }

failures=()

# --- terraform fmt -check ---------------------------------------------------
if [ -d terraform ]; then
  if command -v terraform >/dev/null 2>&1; then
    fmt_out="$(terraform fmt -check -recursive terraform 2>&1)"
    if [ $? -ne 0 ]; then
      failures+=("terraform fmt: the following files are not formatted (run \`terraform fmt -recursive terraform\`):"$'\n'"$fmt_out")
    fi
  else
    failures+=("terraform fmt: terraform is not installed (required to validate formatting before commit).")
  fi
fi

# --- tflint (per stack) -----------------------------------------------------
if [ -d terraform ]; then
  if command -v tflint >/dev/null 2>&1; then
    # Install configured plugins once; non-fatal if offline and already cached.
    tflint --chdir=terraform --init >/dev/null 2>&1 || true
    while IFS= read -r stack; do
      [ -n "$stack" ] || continue
      tf_out="$(tflint --chdir="$stack" 2>&1)"
      if [ $? -ne 0 ]; then
        failures+=("tflint ($stack):"$'\n'"$tf_out")
      fi
    done < <(find terraform -mindepth 1 -maxdepth 1 -type d | sort)
  else
    failures+=("tflint is not installed. Install it: https://github.com/terraform-linters/tflint (e.g. \`curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash\`).")
  fi
fi

# --- ansible-lint -----------------------------------------------------------
if [ -d ansible ]; then
  if command -v ansible-lint >/dev/null 2>&1; then
    al_out="$(ansible-lint ansible/ 2>&1)"
    if [ $? -ne 0 ]; then
      failures+=("ansible-lint (ansible/):"$'\n'"$al_out")
    fi
  else
    failures+=("ansible-lint is not installed. Install it: \`pipx install ansible-lint\` (or \`pip install ansible-lint\`).")
  fi
fi

if [ "${#failures[@]}" -gt 0 ]; then
  {
    echo "BLOCKED: pre-commit validation failed. Fix these before committing (see CLAUDE.md rule 2):"
    echo
    for f in "${failures[@]}"; do
      echo "• $f"
      echo
    done
  } >&2
  exit 2
fi

exit 0
