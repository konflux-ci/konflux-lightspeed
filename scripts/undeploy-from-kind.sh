#!/usr/bin/env bash
#
# Remove konflux-lightspeed from the local Konflux kind cluster.
#
# Usage:
#   ./scripts/undeploy-from-kind.sh

set -euo pipefail

NAMESPACE="konflux-lightspeed"
KIND_CLUSTER="${KIND_CLUSTER:-konflux}"
KUBECTL="kubectl --context kind-${KIND_CLUSTER}"

echo "==> Deleting namespace ${NAMESPACE}..."
${KUBECTL} delete namespace "${NAMESPACE}" --ignore-not-found

echo "==> Konflux Lightspeed removed."
