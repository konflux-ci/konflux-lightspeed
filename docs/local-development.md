# Local Development

Run the Konflux Lightspeed backend locally using podman-compose.

## Prerequisites

- [podman](https://podman.io/getting-started/installation) and [podman-compose](https://github.com/containers/podman-compose)
- An OpenAI API key from [OpenAI](https://platform.openai.com/api-keys) (default)
- Alternatively, a Gemini API key or a Vertex AI service account

## Quick Start

1. Clone the repository and configure environment:

   ```bash
   git clone https://github.com/konflux-ci/konflux-lightspeed.git
   cd konflux-lightspeed
   cp .env.example .env
   ```

2. Edit `.env` with your OpenAI API key:

   ```bash
   OPENAI_API_KEY=sk-your-key-here
   ```

3. Start the services:

   ```bash
   cd local
   podman-compose up -d
   ```

4. Wait for services to become healthy:

   ```bash
   podman-compose ps
   ```

5. Verify:

   ```bash
   curl http://localhost:8080/liveness
   curl http://localhost:8080/readiness
   curl -s -X POST http://localhost:8080/v1/query \
     -H "Content-Type: application/json" \
     -d '{"query": "What is Konflux?"}' | python3 -m json.tool
   ```

## Services

| Service | Port | Description |
|---------|------|-------------|
| `postgres` | 5432 | PostgreSQL for conversation persistence and Llama Stack storage |
| `kod` | 8000 | KOD (Konflux Offline Documentation) MCP server — serves `search_knowledge` and `get_document` for RAG |
| `lightspeed-stack` | 8080 | Lightspeed-stack API server with embedded Llama Stack (library mode) |

## Configuration Files

All configuration lives in `local/config/`:

- **`lightspeed-stack.yaml`** — Service configuration (auth, conversation cache, inference defaults)
- **`run.yaml`** — Llama Stack configuration (LLM provider, storage backends, models)
- **`system-prompt.txt`** — Konflux-specific system prompt

Changes to these files take effect after restarting lightspeed-stack:

```bash
podman-compose restart lightspeed-stack
```

## Using Vertex AI Instead of OpenAI

Vertex AI requires a GCP service account with `roles/aiplatform.user`.

> **Note:** RAG (tool calling) on Vertex requires lightspeed-stack **0.7+**. The
> image pinned in `local/podman-compose.yml` is 0.6.2, which drops the Gemini 3
> `thought_signature` and returns HTTP 400 on tool replay — so KOD-backed queries
> will fail on this stack. Use the default OpenAI provider for RAG; switch to Vertex
> only for non-RAG testing, or once the pinned image is on 0.7 (OGX-based).

1. Create a service account and download a key:

   ```bash
   gcloud iam service-accounts create konflux-lightspeed \
     --display-name="Konflux Lightspeed Local Dev"

   gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
     --member="serviceAccount:konflux-lightspeed@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"

   gcloud iam service-accounts keys create google-credentials.json \
     --iam-account=konflux-lightspeed@YOUR_PROJECT_ID.iam.gserviceaccount.com
   ```

2. In `.env`, set the Vertex AI vars and comment out `OPENAI_API_KEY`.

3. In `local/config/run.yaml`:
   - Comment out the `openai` provider block
   - Uncomment the `google-vertex` provider block and its model entry

4. In `local/config/lightspeed-stack.yaml`, update:
   ```yaml
   inference:
     default_model: publishers/google/models/gemini-3.1-flash-lite
     default_provider: google-vertex
   ```

5. In `local/podman-compose.yml` under `lightspeed-stack`, uncomment the
   `GOOGLE_APPLICATION_CREDENTIALS` env var and the Vertex AI service-account
   volume mount.

6. Restart: `podman-compose restart lightspeed-stack`

## Using the Gemini API Instead of OpenAI

> **Note:** the Gemini API provider (`remote::gemini`) routes tool calls through
> Google's OpenAI-compatibility endpoint, which drops Gemini 3 `thought_signature`
> values and returns HTTP 400 on tool replay. Tool-backed queries (KOD RAG) will
> fail — use OpenAI, or Vertex AI on lightspeed-stack 0.7+, for RAG.

1. In `.env`, uncomment `GEMINI_API_KEY` and set your key.

2. In `local/config/run.yaml`:
   - Comment out the `openai` provider block
   - Uncomment the `gemini` provider block and its model entry

3. In `local/config/lightspeed-stack.yaml`, update:
   ```yaml
   inference:
     default_model: models/gemini-3.1-flash-lite
     default_provider: gemini
   ```

4. Restart: `podman-compose restart lightspeed-stack`

## Connecting the Konflux UI Frontend

To connect a local Konflux UI to this backend, add a proxy entry in the UI's `webpack.dev.config.js`:

```javascript
'/api/lightspeed': {
  target: 'http://localhost:8080',
  pathRewrite: { '^/api/lightspeed': '' },
}
```

## Viewing Logs

```bash
podman-compose logs -f lightspeed-stack
```

## Cleanup

```bash
podman-compose down       # stop services, keep data
podman-compose down -v    # stop services and delete volumes
```

---

## Deploying to a Kind Cluster

Deploy konflux-lightspeed into a local Konflux kind instance for integration testing with the Konflux UI.

### Prerequisites

- A running Konflux kind cluster (via [konflux-ci](https://github.com/konflux-ci/konflux-ci) `./scripts/deploy-local.sh`)
- `kubectl`, `kustomize`, and `kind` installed
- LLM provider credentials (Gemini API key, Vertex AI, or OpenAI)

### Deploy

```bash
# Gemini API (default)
export GEMINI_API_KEY=your-gemini-api-key-here
./scripts/deploy-to-kind.sh

# Or Vertex AI
export VERTEXAI_PROJECT_ID=your-gcp-project-id
export VERTEX_AI_LOCATION=us-central1
export GCP_CREDENTIALS_PATH=/path/to/google-credentials.json
./scripts/deploy-to-kind.sh

# Or OpenAI
export OPENAI_API_KEY=sk-...
./scripts/deploy-to-kind.sh
```

### Verify

```bash
kubectl --context kind-konflux get pods -n konflux-lightspeed
```

In one terminal, run the port-forward:

```bash
kubectl --context kind-konflux port-forward -n konflux-lightspeed svc/lightspeed-stack 8080:8080
```

Then in another terminal:

```bash
curl http://localhost:8080/liveness
curl http://localhost:8080/readiness
curl -s -X POST http://localhost:8080/v1/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What is Konflux?"}' | python3 -m json.tool
```

### Connecting the Konflux UI

For webpack dev mode, add a proxy entry in `webpack.dev.config.js`:

```javascript
{
  context: (path) => path.includes('/api/lightspeed/'),
  target: 'http://localhost:8080',
}
```

This requires a `kubectl port-forward` running (see Verify above).

### Remove

```bash
./scripts/undeploy-from-kind.sh
```
