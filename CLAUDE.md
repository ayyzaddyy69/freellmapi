# Notes for Claude sessions

## My FreeLLMAPI gateway (access to other LLMs)

I use this project as a personal LLM gateway. When I ask you to "use other
LLMs", "call a model", or "test the models", start the gateway inside the
session and call it locally. The `/llm` command does this.

### Start it

```bash
scripts/session-gateway.sh            # start, or confirm it is running
scripts/session-gateway.sh restart    # stop and start again
scripts/session-gateway.sh stop
```

It prints the local address and the path of a file holding the gateway's API
key. Read the key from that file in commands; never print it.

- **Address:** `http://127.0.0.1:3001` (OpenAI-compatible)
  - `GET /v1/models` lists models; each entry has an `available` flag.
  - `POST /v1/chat/completions` runs a chat request.
- **Key file:** `~/.freellmapi-session/unified-key`
- **Log:** `~/.freellmapi-session/server.log`

### How provider keys work

- Sessions must use the `llm-gateway` cloud environment. My provider keys are
  saved there as network secrets, one per provider API host, and are attached
  to outgoing requests automatically.
- The server is seeded with the placeholder key `proxy-injected` for each
  provider. That is expected; do not replace it with a real key and do not ask
  me to paste keys into chat.
- Providers enabled by default: `groq`, `nvidia`, `openrouter`, `google`,
  `zhipu`. A provider whose key is missing or rejected is marked invalid and
  skipped. To enable
  another, save its key for its API host through the secure credential form,
  then start with `GATEWAY_PLATFORMS="groq nvidia openrouter google zhipu <name>"`.
- Google reads its key from the `x-goog-api-key` header, which the credential
  form cannot save; that secret has to be added in the environment settings.
- In the Default environment the provider hosts are blocked, so the gateway
  starts but every model call fails.

### Good default models

- `auto` lets the router pick the best available model.
- `qwen3.8-27b` and `gpt-oss-120b` (Groq) and `nemotron-3-ultra-550b` (NVIDIA)
  were fast and reliable when last tested.
- Models listed as available can still be removed or rate-limited upstream,
  so fall back to `auto` if a specific model fails.
- Send requests one at a time or with low concurrency; free provider quotas
  rate-limit quickly.
