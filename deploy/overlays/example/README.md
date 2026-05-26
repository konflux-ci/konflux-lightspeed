# Example Overlay

This overlay demonstrates how to customize the base manifests for a real deployment. It configures:

- JWK authentication against an SSO JWKS endpoint
- PostgreSQL connection for conversation persistence
- Vertex AI (Gemini) as the LLM provider
- Environment variables sourced from Kubernetes Secrets

## Prerequisites

The following Secrets must exist in the `konflux-lightspeed` namespace before applying:

### lightspeed-tls

TLS certificate and key for HTTPS. Typically provisioned by cert-manager:

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

### lightspeed-postgres

PostgreSQL connection credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: lightspeed-postgres
  namespace: konflux-lightspeed
stringData:
  password: "<your-postgres-password>"
```

### llm-provider-credentials

LLM provider credentials. For Vertex AI:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: llm-provider-credentials
  namespace: konflux-lightspeed
stringData:
  vertexai-project-id: "<your-gcp-project-id>"
  vertex-ai-location: "us-central1"
  credentials.json: |
    <your GCP service account JSON>
```

## Usage

```bash
kustomize build deploy/overlays/example/
```

## Using as a remote base

To deploy konflux-lightspeed in your own cluster, reference `deploy/base/` as a Kustomize remote base and add your own patches:

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
