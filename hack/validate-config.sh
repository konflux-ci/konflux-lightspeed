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

  # ogx must have either use_as_library_client or url
  if ! echo "$config" | yq -e '.ogx.use_as_library_client // .ogx.url' >/dev/null 2>&1; then
    echo "  FAIL: missing required field: .ogx (need use_as_library_client or url)"
    rc=1
  fi

  # Unified library mode requires a config.profile path. library_client_config_path
  # is deprecated and removed in lightspeed-stack 0.8.
  if [[ "$(echo "$config" | yq '.ogx.use_as_library_client' 2>/dev/null)" == "true" ]]; then
    if [[ -z "$(echo "$config" | yq '.ogx.config.profile // ""' 2>/dev/null)" ]]; then
      echo "  FAIL: .ogx.use_as_library_client is true but .ogx.config.profile is not set"
      rc=1
    fi
  fi

  return $rc
}

# run.yaml must enable the responses API and provider — query handling on
# lightspeed-stack 0.7+ (OGX) depends on it.
validate_run_config() {
  local label="$1"
  local run="$2"
  local rc=0

  if [[ -z "$run" || "$run" == "null" ]]; then
    echo "  FAIL: run.yaml not found"
    return 1
  fi

  if ! echo "$run" | yq -e '.apis[] | select(. == "responses")' >/dev/null 2>&1; then
    echo "  FAIL: run.yaml apis is missing 'responses'"
    rc=1
  fi
  if ! echo "$run" | yq -e '.providers.responses' >/dev/null 2>&1; then
    echo "  FAIL: run.yaml providers.responses is not defined"
    rc=1
  fi

  return $rc
}

# A container with a read-only root filesystem must redirect unified-mode library
# synthesis to a writable path via --synthesized-config-output, otherwise it
# crashes at startup writing ./.generated/run.yaml under the read-only workdir.
validate_deployment() {
  local label="$1"
  local built="$2"
  local rc=0

  local offenders
  offenders=$(echo "$built" | yq '
    select(.kind == "Deployment")
    | .spec.template.spec.containers[]
    | select(.securityContext.readOnlyRootFilesystem == true)
    | select((.args // []) | contains(["--synthesized-config-output"]) | not)
    | .name' 2>/dev/null || true)

  if [[ -n "$offenders" && "$offenders" != "null" ]]; then
    echo "  FAIL: read-only container(s) missing --synthesized-config-output arg: ${offenders//$'\n'/, }"
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

  ok=1
  validate_config "$label" "$config" || ok=0

  run=$(echo "$built" | yq 'select(.kind == "ConfigMap" and .metadata.name == "run-config") | .data["run.yaml"]')
  validate_run_config "$label" "$run" || ok=0

  validate_deployment "$label" "$built" || ok=0

  if [[ "$ok" -eq 1 ]]; then
    echo "  PASS"
  else
    rc=1
  fi
done

# Validate local config (standalone files, not in a ConfigMap)
LOCAL_CONFIG="${REPO_ROOT}/local/config/lightspeed-stack.yaml"
LOCAL_RUN="${REPO_ROOT}/local/config/run.yaml"
if [[ -f "$LOCAL_CONFIG" ]]; then
  echo "==> Validating config in local/config..."
  ok=1
  validate_config "local" "$(cat "$LOCAL_CONFIG")" || ok=0
  if [[ -f "$LOCAL_RUN" ]]; then
    validate_run_config "local" "$(cat "$LOCAL_RUN")" || ok=0
  else
    # The local config's ogx.config.profile points at run.yaml, so a missing
    # file is a failure, not a skip.
    validate_run_config "local" "" || ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    echo "  PASS"
  else
    rc=1
  fi
fi

exit $rc
