# Local Development

Run the Konflux Lightspeed backend locally using podman-compose.

## Prerequisites

- [podman](https://podman.io/getting-started/installation) and [podman-compose](https://github.com/containers/podman-compose)
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey) (default)
- Alternatively, a Vertex AI service account or OpenAI API key

## Quick Start

1. Clone the repository and configure environment:

   ```bash
   git clone https://github.com/konflux-ci/konflux-lightspeed.git
   cd konflux-lightspeed
   cp .env.example .env
   ```

2. Edit `.env` with your Gemini API key:

   ```bash
   GEMINI_API_KEY=your-gemini-api-key-here
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

## Using Vertex AI Instead of Gemini API

Vertex AI requires a GCP service account with `roles/aiplatform.user`.

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

2. In `.env`, set the Vertex AI vars and comment out `GEMINI_API_KEY`.

3. In `local/config/run.yaml`:
   - Comment out the `gemini` provider block
   - Uncomment the `google-vertex` provider block and its model entry

4. In `local/config/lightspeed-stack.yaml`, update:
   ```yaml
   inference:
     default_model: publishers/google/models/gemini-2.5-flash
     default_provider: google-vertex
   ```

5. Add a volume mount to `local/podman-compose.yml` under `lightspeed-stack.volumes`:
   ```yaml
   - ${GCP_CREDENTIALS_PATH}:/etc/gcp/credentials.json:ro,Z
   ```

6. Restart: `podman-compose restart lightspeed-stack`

## Using OpenAI Instead of Gemini API

1. In `.env`, uncomment `OPENAI_API_KEY` and set your key.

2. In `local/config/run.yaml`:
   - Comment out the `gemini` provider block
   - Uncomment the `openai` provider block and its model entry

3. In `local/config/lightspeed-stack.yaml`, update:
   ```yaml
   inference:
     default_model: gpt-4o-mini
     default_provider: openai
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
