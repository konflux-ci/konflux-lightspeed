#!/usr/bin/env bash
set -euo pipefail

if ! command -v shellcheck &>/dev/null; then
  echo "ERROR: shellcheck not found. Please install it first." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SCRIPTS=()
for dir in "${REPO_ROOT}/scripts" "${REPO_ROOT}/hack"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r f; do
      SCRIPTS+=("$f")
    done < <(find "$dir" -name '*.sh' -type f)
  fi
done

if [[ ${#SCRIPTS[@]} -eq 0 ]]; then
  echo "No shell scripts found."
  exit 0
fi

echo "==> Running shellcheck on ${#SCRIPTS[@]} scripts..."
shellcheck --severity=warning "${SCRIPTS[@]}"
echo "PASS: all scripts passed shellcheck"
