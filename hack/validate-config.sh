#!/usr/bin/env bash
set -euo pipefail

for cmd in kustomize yq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd not found. Please install it first." >&2
    exit 1
  fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REQUIRED_FIELDS=(
  ".service.host"
  ".service.port"
  ".authentication.module"
)

validate_config() {
  local label="$1"
  local config="$2"
  local rc=0

  for field in "${REQUIRED_FIELDS[@]}"; do
    if ! echo "$config" | yq -e "$field" >/dev/null 2>&1; then
      echo "  FAIL: missing required field: ${field}"
      rc=1
    fi
  done

  # llama_stack must have either use_as_library_client or url
  if ! echo "$config" | yq -e '.llama_stack.use_as_library_client // .llama_stack.url' >/dev/null 2>&1; then
    echo "  FAIL: missing required field: .llama_stack (need use_as_library_client or url)"
    rc=1
  fi

  return $rc
}

rc=0

# Validate overlay configs extracted from kustomize build output
for d in "${REPO_ROOT}"/deploy/overlays/*/; do
  [[ -f "${d}kustomization.yaml" ]] || continue
  label="${d#"${REPO_ROOT}/"}"
  label="${label%/}"

  echo "==> Validating config in ${label}..."

  if ! built=$(kustomize build "$d" 2>&1); then
    echo "  FAIL: kustomize build failed (run validate-manifests first)"
    rc=1
    continue
  fi

  config=$(echo "$built" | yq 'select(.kind == "ConfigMap" and .metadata.name == "lightspeed-stack-config") | .data["lightspeed-stack.yaml"]')

  if [[ -z "$config" || "$config" == "null" ]]; then
    echo "  FAIL: lightspeed-stack-config ConfigMap not found in build output"
    rc=1
    continue
  fi

  if ! validate_config "$label" "$config"; then
    rc=1
  else
    echo "  PASS"
  fi
done

# Validate local config (standalone file, not in a ConfigMap)
LOCAL_CONFIG="${REPO_ROOT}/local/config/lightspeed-stack.yaml"
if [[ -f "$LOCAL_CONFIG" ]]; then
  echo "==> Validating config in local/config/lightspeed-stack.yaml..."
  if ! validate_config "local" "$(cat "$LOCAL_CONFIG")"; then
    rc=1
  else
    echo "  PASS"
  fi
fi

exit $rc
