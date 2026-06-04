#!/usr/bin/env bash
#
# Deploy konflux-lightspeed to a local Konflux kind cluster.
#
# Prerequisites:
#   - A running Konflux kind cluster (via konflux-ci/scripts/deploy-local.sh)
#   - kubectl configured to use the kind cluster context
#   - kustomize installed
#   - LLM provider credentials (Gemini API key, Vertex AI, or OpenAI)
#
# Usage:
#   # Gemini API (default)
#   export GEMINI_API_KEY=your-api-key
#   ./scripts/deploy-to-kind.sh
#
#   # Vertex AI
#   export VERTEXAI_PROJECT_ID=my-project
#   export VERTEX_AI_LOCATION=us-central1
#   export GCP_CREDENTIALS_PATH=/path/to/credentials.json
#   ./scripts/deploy-to-kind.sh
#
#   # OpenAI
#   export OPENAI_API_KEY=sk-...
#   ./scripts/deploy-to-kind.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NAMESPACE="konflux-lightspeed"
KIND_CLUSTER="${KIND_CLUSTER:-konflux}"

echo "==> Checking prerequisites..."

if ! command -v kubectl &>/dev/null; then
    echo "ERROR: kubectl not found. Install it first."
    exit 1
fi

if ! command -v kustomize &>/dev/null; then
    echo "ERROR: kustomize not found. Install it first."
    exit 1
fi

if ! kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
    echo "ERROR: kind cluster '${KIND_CLUSTER}' not found."
    echo "Start a Konflux instance first: cd konflux-ci && ./scripts/deploy-local.sh"
    exit 1
fi

KUBECTL="kubectl --context kind-${KIND_CLUSTER}"

echo "==> Creating namespace ${NAMESPACE}..."
${KUBECTL} create namespace "${NAMESPACE}" --dry-run=client -o yaml | ${KUBECTL} apply -f -

echo "==> Creating LLM provider credentials secret..."
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
    ${KUBECTL} create secret generic llm-provider-credentials \
        -n "${NAMESPACE}" \
        --from-literal=GEMINI_API_KEY="${GEMINI_API_KEY}" \
        --dry-run=client -o yaml | ${KUBECTL} apply -f -
    echo "    Using Gemini API provider"
elif [[ -n "${GCP_CREDENTIALS_PATH:-}" && -f "${GCP_CREDENTIALS_PATH}" ]]; then
    ${KUBECTL} create secret generic llm-provider-credentials \
        -n "${NAMESPACE}" \
        --from-file=credentials.json="${GCP_CREDENTIALS_PATH}" \
        --from-literal=VERTEXAI_PROJECT_ID="${VERTEXAI_PROJECT_ID:-}" \
        --from-literal=VERTEX_AI_LOCATION="${VERTEX_AI_LOCATION:-us-central1}" \
        --dry-run=client -o yaml | ${KUBECTL} apply -f -
    echo "    Using Vertex AI provider"
    echo "    NOTE: Update the run.yaml ConfigMap to use the Vertex AI provider block"
elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    ${KUBECTL} create secret generic llm-provider-credentials \
        -n "${NAMESPACE}" \
        --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY}" \
        --dry-run=client -o yaml | ${KUBECTL} apply -f -
    echo "    Using OpenAI provider"
    echo "    NOTE: Update the run.yaml ConfigMap to use the OpenAI provider block"
else
    echo "WARNING: No LLM credentials found. Set GEMINI_API_KEY, GCP_CREDENTIALS_PATH, or OPENAI_API_KEY."
    echo "         The stack will start but inference requests will fail."
fi

echo "==> Applying Kustomize manifests..."
kustomize build "${REPO_ROOT}/deploy/overlays/kind" | ${KUBECTL} apply -f -

echo "==> Waiting for PostgreSQL to be ready..."
${KUBECTL} rollout status statefulset/lightspeed-postgres -n "${NAMESPACE}" --timeout=120s

echo "==> Waiting for lightspeed-stack to be ready..."
${KUBECTL} rollout status deployment/lightspeed-stack -n "${NAMESPACE}" --timeout=180s

echo ""
echo "==> Konflux Lightspeed deployed successfully!"
echo ""
echo "    Namespace:  ${NAMESPACE}"
echo "    Service:    lightspeed-stack.${NAMESPACE}.svc:8080"
echo ""
echo "    To test from your host, run the port-forward in one terminal:"
echo "      kubectl --context kind-${KIND_CLUSTER} port-forward -n ${NAMESPACE} svc/lightspeed-stack 8080:8080"
echo ""
echo "    Then in another terminal:"
echo "      curl http://localhost:8080/liveness"
echo "      curl http://localhost:8080/readiness"
echo "      curl -s -X POST http://localhost:8080/v1/query \\"
echo "        -H 'Content-Type: application/json' \\"
echo "        -d '{\"query\": \"What is Konflux?\"}' | python3 -m json.tool"
echo ""
echo "    To connect the Konflux UI (webpack dev mode), add to webpack.dev.config.js:"
echo "      { context: (path) => path.includes('/api/lightspeed/'), target: 'http://localhost:8080' }"
echo ""
echo "    To remove: ./scripts/undeploy-from-kind.sh"
