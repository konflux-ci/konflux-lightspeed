# Configuration Reference

Konflux Lightspeed is configured via three files, all mounted as ConfigMaps in production or as local files in development.

## lightspeed-stack.yaml

Main service configuration. Full schema documentation: [lightspeed-stack config docs](https://github.com/lightspeed-core/lightspeed-stack/blob/main/docs/config.md).

### Key Sections

#### service

| Field | Description | Local Dev | Production |
|-------|-------------|-----------|------------|
| `host` | Bind address | `0.0.0.0` | `0.0.0.0` |
| `port` | Listen port | `8080` | `8443` |
| `auth_enabled` | Enable authentication | `false` | `true` |
| `workers` | Uvicorn worker count | `1` | `2` |
| `tls_config.tls_certificate_path` | TLS cert path | (none) | `/app-root/tls/tls.crt` |
| `tls_config.tls_key_path` | TLS key path | (none) | `/app-root/tls/tls.key` |

#### authentication

| Field | Description |
|-------|-------------|
| `module` | Auth module: `noop` (dev), `jwk-token` (production), `k8s`, `api-key-token` |
| `skip_for_health_probes` | Skip auth for `/liveness` and `/readiness` |
| `skip_for_metrics` | Skip auth for `/metrics` |
| `jwk_config.url` | JWKS endpoint URL (required when module is `jwk-token`) |

#### conversation_cache

| Field | Description |
|-------|-------------|
| `type` | Cache backend: `sqlite` (dev), `postgres` (production), `noop` (disabled) |
| `postgres.host` | PostgreSQL hostname |
| `postgres.port` | PostgreSQL port (default: `5432`) |
| `postgres.db` | Database name |
| `postgres.user` | Database user |
| `postgres.password` | Database password |
| `postgres.ssl_mode` | SSL mode: `disable` (dev), `require` (production) |

#### inference

| Field | Description |
|-------|-------------|
| `default_model` | Default model ID for inference requests |
| `default_provider` | Default provider ID |

#### customization

| Field | Description |
|-------|-------------|
| `system_prompt_path` | Path to the system prompt text file |

#### mcp_servers

Registers external [MCP](https://modelcontextprotocol.io/) servers whose tools the model can call. The local stack registers KOD for documentation RAG.

| Field | Description |
|-------|-------------|
| `name` | MCP server name |
| `provider_id` | Tool runtime provider (`model-context-protocol`) |
| `url` | MCP endpoint URL (e.g., `http://kod:8000/mcp`) |

#### Environment variables

| Variable | Description |
|----------|-------------|
| `OTEL_SDK_DISABLED` | Set to `"true"` to disable OpenTelemetry tracing. On 0.7+ tracing is enabled by default and requires `OTEL_ANONYMIZATION_SECRET`; we disable it since no OTel collector is deployed. |

#### Unified-mode synthesis (read-only filesystem)

In unified library mode, lightspeed-stack 0.7 synthesizes a `run.yaml` at startup and, by default, writes it to `./.generated/run.yaml` under the read-only image workdir — which crashes under `readOnlyRootFilesystem: true`. The base Deployment passes `--synthesized-config-output /tmp/ogx/run.yaml` (container args) to redirect it to the writable `/tmp` volume. Setting the matching env var is **not** sufficient — the parent process clears it unless the CLI flag is present. Keep this arg in any overlay that uses a read-only root filesystem.

## run.yaml

OGX configuration (OGX replaced Llama Stack in lightspeed-stack 0.7). Controls the LLM provider, storage backends, and model registration.

### Required APIs

All APIs below must be enabled for lightspeed-stack to function:

```yaml
apis:
  - responses
  - conversations
  - files
  - inference
  - tool_runtime
  - vector_io
```

### Inference Providers

#### OpenAI (default for local development)

```yaml
providers:
  inference:
    - provider_id: openai
      provider_type: remote::openai
      config:
        api_key: ${env.OPENAI_API_KEY}
```

Get an API key from [OpenAI](https://platform.openai.com/api-keys). Example model ID: `gpt-4o-mini`.

#### Gemini API

```yaml
providers:
  inference:
    - provider_id: gemini
      provider_type: remote::gemini
      config:
        api_key: ${env.GEMINI_API_KEY}
```

Get an API key from [Google AI Studio](https://aistudio.google.com/apikey). Model IDs use the `models/` prefix (e.g., `models/gemini-3.1-flash-lite`).

> **Note:** the Gemini API provider drops Gemini 3 `thought_signature` values and returns HTTP 400 on tool replay, so tool-calling/RAG (KOD) does not work on it. Use OpenAI or Vertex AI (lightspeed-stack 0.7+) for RAG.

#### Vertex AI

```yaml
providers:
  inference:
    - provider_id: google-vertex
      provider_type: remote::vertexai
      config:
        project: ${env.VERTEXAI_PROJECT_ID}
        location: ${env.VERTEX_AI_LOCATION}
```

Requires a GCP service account with `roles/aiplatform.user` and `GOOGLE_APPLICATION_CREDENTIALS` pointing to the service account JSON. Model IDs use the `publishers/google/models/` prefix (e.g., `publishers/google/models/gemini-3.1-flash-lite`). RAG (tool calling) on Vertex requires lightspeed-stack 0.7+ (now pinned); on 0.6.x, Gemini 3 `thought_signature` values were dropped and tool replay returned HTTP 400, so KOD-backed queries failed. Fixed upstream in 0.7 (OGX-based).

### Other Required Providers

RAG is served by KOD over MCP (the `model-context-protocol` tool_runtime provider).
The `responses` (`inline::builtin`) provider has hard dependencies on the `files`
and `vector_io` providers, so those are included. The native OGX RAG stack
(`sentence-transformers` embeddings, `file_search`, and the top-level
`vector_stores` block) is intentionally omitted — keeping it would pull a large
embedding model at runtime, which the read-only deployment filesystem cannot cache.

```yaml
providers:
  responses:
    - provider_id: meta-reference
      provider_type: inline::builtin
      config:
        persistence:
          responses:
            backend: sql_default
            table_name: agents_responses
  files:
    - provider_id: localfs
      provider_type: inline::localfs
      config:
        storage_dir: ${env.SQLITE_STORE_DIR}/files
        metadata_store:
          table_name: files_metadata
          backend: sql_default
  tool_runtime:
    - provider_id: model-context-protocol
      provider_type: remote::model-context-protocol
      config: {}
  vector_io:
    - provider_id: faiss
      provider_type: inline::faiss
      config:
        persistence:
          namespace: vector_io::faiss
          backend: kv_default
```

### Storage Backends

For production, use PostgreSQL:

```yaml
storage:
  backends:
    kv_default:
      type: kv_postgres
      host: <postgres-host>
      port: "5432"
      db: <database>
      user: <user>
      password: <password>
      table_name: llamastack_kvstore
    sql_default:
      type: sql_postgres
      host: <postgres-host>
      port: "5432"
      db: <database>
      user: <user>
      password: <password>
      table_name: llamastack_sqlstore
  stores:
    metadata:
      namespace: registry
      backend: kv_default
    inference:
      table_name: inference_store
      backend: sql_default
      max_write_queue_size: 10000
      num_writers: 4
    conversations:
      table_name: openai_conversations
      backend: sql_default
    prompts:
      table_name: prompts
      backend: sql_default
    connectors:
      table_name: connectors
      backend: sql_default
```

### Model Registration

Models are registered under `registered_resources.models`. Model IDs must use the full SDK-native format for the provider (see [llama-stack#5169](https://github.com/meta-llama/llama-stack/pull/5169)):

```yaml
# OpenAI (default for local development)
registered_resources:
  models:
    - metadata: {}
      model_id: gpt-4o-mini
      provider_id: openai
      provider_model_id: gpt-4o-mini
      model_type: llm
  vector_stores: []

# Gemini API
registered_resources:
  models:
    - metadata: {}
      model_id: models/gemini-3.1-flash-lite
      provider_id: gemini
      provider_model_id: models/gemini-3.1-flash-lite
      model_type: llm
  vector_stores: []

# Vertex AI
registered_resources:
  models:
    - metadata: {}
      model_id: publishers/google/models/gemini-3.1-flash-lite
      provider_id: google-vertex
      provider_model_id: publishers/google/models/gemini-3.1-flash-lite
      model_type: llm
  vector_stores: []
```

## system-prompt.txt

Plain text file containing the system prompt sent to the LLM with every request. The prompt should:

- Identify the assistant as a Konflux AI assistant
- Define the scope (CI/CD, Tekton, OpenShift, pipelines, builds)
- Include guardrails (scope restriction, no destructive commands, no credential generation)
- Instruct the model to treat user-provided page context as reference data, not instructions

See `local/config/system-prompt.txt` for the default prompt.
