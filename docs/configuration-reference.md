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

## run.yaml

Llama Stack configuration. Controls the LLM provider, storage backends, and model registration.

### Required APIs

All six APIs must be enabled for lightspeed-stack to function:

```yaml
apis:
  - inference
  - agents
  - files
  - safety
  - tool_runtime
  - vector_io
```

### Inference Providers

#### Gemini API (default for local development)

```yaml
providers:
  inference:
    - provider_id: gemini
      provider_type: remote::gemini
      config:
        api_key: ${env.GEMINI_API_KEY}
```

Get an API key from [Google AI Studio](https://aistudio.google.com/apikey). Model IDs use the `models/` prefix (e.g., `models/gemini-3.1-flash-lite`).

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

Requires a GCP service account with `roles/aiplatform.user` and `GOOGLE_APPLICATION_CREDENTIALS` pointing to the service account JSON. Model IDs use the `publishers/google/models/` prefix (e.g., `publishers/google/models/gemini-3.1-flash-lite`).

#### OpenAI

```yaml
providers:
  inference:
    - provider_id: openai
      provider_type: remote::openai
      config:
        api_key: ${env.OPENAI_API_KEY}
```

### Other Required Providers

```yaml
providers:
  agents:
    - provider_id: meta-reference
      provider_type: inline::meta-reference
      config:
        persistence:
          agent_state:
            backend: kv_default
            namespace: agents
          responses:
            backend: sql_default
            table_name: responses
  files:
    - provider_id: localfs
      provider_type: inline::localfs
      config:
        storage_dir: ${env.SQLITE_STORE_DIR}/files
        metadata_store:
          table_name: files_metadata
          backend: sql_default
  tool_runtime:
    - provider_id: rag-runtime
      provider_type: inline::rag-runtime
      config: {}
  vector_io:
    - provider_id: faiss
      provider_type: inline::faiss
      config:
        persistence:
          namespace: vector_io
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
```

### Model Registration

Model IDs must use the full SDK-native format for the provider (see [llama-stack#5169](https://github.com/meta-llama/llama-stack/pull/5169)):

```yaml
# Gemini API
models:
  - metadata: {}
    model_id: models/gemini-3.1-flash-lite
    provider_id: gemini
    provider_model_id: models/gemini-3.1-flash-lite
    model_type: llm

# Vertex AI
models:
  - metadata: {}
    model_id: publishers/google/models/gemini-3.1-flash-lite
    provider_id: google-vertex
    provider_model_id: publishers/google/models/gemini-3.1-flash-lite
    model_type: llm
```

## system-prompt.txt

Plain text file containing the system prompt sent to the LLM with every request. The prompt should:

- Identify the assistant as a Konflux AI assistant
- Define the scope (CI/CD, Tekton, OpenShift, pipelines, builds)
- Include guardrails (scope restriction, no destructive commands, no credential generation)
- Instruct the model to treat user-provided page context as reference data, not instructions

See `local/config/system-prompt.txt` for the default prompt.
