# Deployment Guide

Deploy Konflux Lightspeed to a Kubernetes or OpenShift cluster.

## Architecture Overview

Lightspeed-stack runs as a Deployment in the `konflux-lightspeed` namespace. It has no public Route — traffic is proxied through the Konflux UI's nginx pod, which forwards `/api/lightspeed/*` to the internal ClusterIP Service.

```
Browser → Konflux UI (nginx) → lightspeed-stack Service (ClusterIP)
                                       ↓
                                  LLM Provider (outbound HTTPS)
                                       ↓
                                  PostgreSQL (conversation persistence)
```

## Prerequisites

- A Kubernetes or OpenShift cluster
- [cert-manager](https://cert-manager.io/) for TLS certificate provisioning
- A PostgreSQL instance (managed or self-hosted)
- An SSO/OIDC provider with a JWKS endpoint
- LLM provider credentials (Vertex AI, OpenAI, or other supported provider)

## Deployment Options

### Option A: Reference as a remote base (recommended)

Create a Kustomize overlay in your deployment repository that references the base manifests:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/konflux-ci/konflux-lightspeed/deploy/base?ref=<commit-sha>
patches:
  - path: patch-lightspeed-stack-config.yaml
  - path: patch-run-config.yaml
  - path: patch-deployment.yaml
images:
  - name: quay.io/lightspeed-core/lightspeed-stack
    newName: quay.io/lightspeed-core/lightspeed-stack
    newTag: <pinned-image-tag>
namespace: konflux-lightspeed
```

See `deploy/overlays/example/` for a complete example of the patches.

### Option B: Direct apply

```bash
# Customize the example overlay for your environment
cp -r deploy/overlays/example deploy/overlays/my-cluster
# Edit the patches with your actual values
kustomize build deploy/overlays/my-cluster | kubectl apply -f -
```

## Required Secrets

Create these Secrets in the `konflux-lightspeed` namespace before deploying:

### TLS Certificate

Use cert-manager to provision a TLS certificate:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lightspeed-tls
  namespace: konflux-lightspeed
spec:
  secretName: lightspeed-tls
  issuerRef:
    name: your-cluster-issuer
    kind: ClusterIssuer
  dnsNames:
    - lightspeed-stack.konflux-lightspeed.svc
```

### PostgreSQL Credentials

```bash
kubectl create secret generic lightspeed-postgres \
  -n konflux-lightspeed \
  --from-literal=password='<your-password>'
```

### LLM Provider Credentials

For Vertex AI:

```bash
kubectl create secret generic llm-provider-credentials \
  -n konflux-lightspeed \
  --from-literal=vertexai-project-id='<project-id>' \
  --from-literal=vertex-ai-location='us-central1' \
  --from-file=credentials.json='<path-to-service-account.json>'
```

## Configuring Authentication

Update the JWKS URL in your lightspeed-stack config patch to point to your SSO provider's JWKS endpoint:

```yaml
authentication:
  module: jwk-token
  skip_for_health_probes: true
  jwk_config:
    url: https://your-sso.example.com/realms/konflux/protocol/openid-connect/certs
```

## Configuring the Konflux UI Proxy

The Konflux UI's nginx must proxy `/api/lightspeed/*` to the lightspeed-stack Service. Add to the nginx configuration:

```nginx
location /api/lightspeed/ {
    proxy_pass https://lightspeed-stack.konflux-lightspeed.svc/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
    proxy_send_timeout 120s;
}
```

## Verifying the Deployment

```bash
# Check pod status
kubectl get pods -n konflux-lightspeed

# Check liveness
kubectl exec -n konflux-lightspeed deploy/lightspeed-stack -- \
  curl -sk https://localhost:8443/liveness

# Check readiness
kubectl exec -n konflux-lightspeed deploy/lightspeed-stack -- \
  curl -sk https://localhost:8443/readiness
```

## Feature Discovery

The Konflux UI detects lightspeed-stack availability by probing the `/liveness` endpoint through the nginx proxy. If the endpoint responds, the AI assistant feature flag is enabled and the chat sidebar is shown.
