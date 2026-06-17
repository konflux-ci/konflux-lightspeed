# konflux-lightspeed

Deployment configuration for the Konflux UI AI Agent backend, powered by [lightspeed-stack](https://github.com/lightspeed-core/lightspeed-stack).

This repository provides base Kustomize manifests and configuration templates that can be customized for any Konflux installation. It does not contain application code — it configures and deploys the upstream lightspeed-stack container image.

## Repository Layout

| Directory | Description |
|-----------|-------------|
| `deploy/base/` | Base Kustomize manifests (Deployment, Service, ConfigMaps) |
| `deploy/overlays/example/` | Example overlay showing how to customize for a real deployment |
| `deploy/overlays/kind/` | Overlay for local kind cluster deployment |
| `scripts/` | Deployment and cleanup scripts for kind clusters |
| `hack/` | Validation scripts used by CI and `make validate` |
| `local/` | Local development setup using podman-compose |
| `docs/` | Documentation |

## Quick Start

See [Local Development](docs/local-development.md) to run the stack locally, or [Deployment Guide](docs/deployment-guide.md) to deploy to a Kubernetes/OpenShift cluster.

## How It Works

The lightspeed-stack service is fully config-driven. This repository provides:

- **Configuration templates** for authentication (JWK), conversation persistence (PostgreSQL), LLM provider selection, and a Konflux-specific system prompt.
- **Kustomize base manifests** that deployers reference and customize via overlays. See `deploy/overlays/example/` for a complete example.
- **Local development setup** with noop authentication for rapid iteration.

## Validation

Run `make validate` to check manifests, scripts, and configs locally. The same checks run in CI on PRs that change deployment, script, or workflow files.

```bash
make validate              # run all checks
make validate-manifests    # kustomize build + kubeconform on all overlays
make validate-scripts      # shellcheck on all shell scripts
make validate-config       # required fields in lightspeed-stack.yaml configs
```

Required tools: [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/), [kubeconform](https://github.com/yannh/kubeconform), [shellcheck](https://www.shellcheck.net/), [yq](https://github.com/mikefarah/yq/).

## License

Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
