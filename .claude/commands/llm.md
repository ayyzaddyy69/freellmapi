---
description: Start the FreeLLMAPI gateway inside this session and confirm other LLMs are reachable
---

Start my FreeLLMAPI gateway in this session so you can call other LLMs.

1. Run `scripts/session-gateway.sh` from the root of the freellmapi repository
   (pass `restart` only if I ask for a restart). It installs and builds if
   needed, starts the server on `http://127.0.0.1:3001`, and prints the path
   of the file holding the local API key.
2. Confirm it works with one small request to `/v1/chat/completions` using
   model `auto`, reading the key from that file with `$(cat <key file>)`.
   Never print the key.
3. Tell me in two or three lines: that it is running, how many models are
   available, and which model answered the test.

If a provider call fails with a blocked connection or a 401, the provider's
key is missing from this environment's network secrets. Say which provider
and offer the secure credential form; do not ask me to paste a key into chat.

$ARGUMENTS
