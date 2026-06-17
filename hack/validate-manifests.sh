#!/usr/bin/env bash
set -euo pipefail

for cmd in kustomize kubeconform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd not found. Please install it first." >&2
    exit 1
  fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGETS=("${REPO_ROOT}/deploy/base")
for d in "${REPO_ROOT}"/deploy/overlays/*/; do
  [[ -f "${d}kustomization.yaml" ]] && TARGETS+=("$d")
done

rc=0
for target in "${TARGETS[@]}"; do
  label="${target#"${REPO_ROOT}/"}"
  label="${label%/}"

  echo "==> Building ${label}..."
  if ! output=$(kustomize build "$target" 2>&1); then
    echo "FAIL: kustomize build ${label}"
    echo "$output"
    rc=1
    continue
  fi

  echo "==> Validating ${label} with kubeconform..."
  if ! echo "$output" | kubeconform -strict -summary; then
    echo "FAIL: kubeconform ${label}"
    rc=1
  fi
done

exit $rc
