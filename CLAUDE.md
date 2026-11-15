# Notes for Claude sessions

## My FreeLLMAPI gateway (access to other LLMs)

I run this project as a personal LLM gateway. When I ask you to "use other
LLMs", "call a model", or "test the models", use this gateway.

- **Address:** `https://advertising-reliable-inbox-powder.trycloudflare.com`
  - This is a temporary Cloudflare quick-tunnel address. It changes whenever
    the tunnel restarts. If it stops answering, ask me for the current
    address instead of guessing, then update this line.
- **API:** OpenAI-compatible.
  - `GET /v1/models` lists models; each entry has an `available` flag.
  - `POST /v1/chat/completions` runs a chat request.
- **Auth:** my API key is saved as a network secret on the cloud environment
  and is attached to requests automatically. Do not ask me to paste the key
  into chat, and do not add an auth header yourself. A new address needs the
  key saved again through the secure credential form.

### Check it is reachable

```bash
curl -sS -m 30 https://advertising-reliable-inbox-powder.trycloudflare.com/v1/models | head -c 300
```

### Known quirks

- The GitHub Codespaces forwarded address
  (`…-3001.app.github.dev`) returns an empty `404` from cloud sessions even
  when the port is public. Use the tunnel address instead.
- Requests that take longer than about 30 seconds to start responding fail
  with `502 upstream request failed`.
- The gateway only works while the server and the tunnel are running
  (`npm run dev`, then `./cloudflared tunnel --url http://localhost:3001`).
- Send requests one at a time or with low concurrency; free provider quotas
  rate-limit quickly.

### Good default models

- `auto` lets the router pick the best available model.
- `qwen3.8-27b` and `gpt-oss-120b` were fast and reliable when last tested.
- Models listed as available can still be removed or rate-limited upstream,
  so fall back to `auto` if a specific model fails.
