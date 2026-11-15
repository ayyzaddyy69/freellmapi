#!/usr/bin/env node
// Sends one question to every available chat model in this FreeLLMAPI and
// prints who answered, how fast, and the answer.
//   node .devcontainer/ask-all-models.mjs                 (default question)
//   node .devcontainer/ask-all-models.mjs "your question"
import { readFileSync, writeFileSync } from "node:fs";

const BASE = "http://localhost:3001";
const HOME = process.env.FREELLMAPI_HOME || "/workspaces/.freellmapi";
const QUESTION =
  process.argv.slice(2).join(" ").trim() ||
  "A bat and a ball cost $1.10 in total. The bat costs $1.00 more than the ball. How much does the ball cost? Answer in one short sentence.";
const PARALLEL = 4;
const TIMEOUT_MS = 90_000;
// Not chat models: embeddings, speech, images, safety filters, parsers.
const SKIP = /embed|whisper|tts|transcribe|image|imagen|veo|robotics|guard|moderation|rerank|speech|audio|ocr|lyria|music|riva-translate|content-safety|nemotron-parse|ising-calibration/i;

function readSecrets() {
  const out = {};
  for (const line of readFileSync(`${HOME}/secrets.env`, "utf8").split("\n")) {
    const i = line.indexOf("=");
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  return out;
}

async function getUnifiedKey() {
  const s = readSecrets();
  const login = await fetch(`${BASE}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: s.ADMIN_EMAIL, password: s.ADMIN_PASSWORD }),
  });
  if (!login.ok) throw new Error(`Dashboard login failed (HTTP ${login.status}). Is FreeLLMAPI running? Run: bash .devcontainer/start-freellmapi.sh`);
  const { token } = await login.json();
  const res = await fetch(`${BASE}/api/settings/api-key`, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Could not read the unified key (HTTP ${res.status})`);
  return (await res.json()).apiKey;
}

async function ask(model, key) {
  const started = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${BASE}/v1/chat/completions`, {
      method: "POST",
      signal: ctrl.signal,
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({ model, messages: [{ role: "user", content: QUESTION }] }),
    });
    const via = res.headers.get("x-routed-via") || "";
    const body = await res.json().catch(() => ({}));
    const secs = (Date.now() - started) / 1000;
    const text = body?.choices?.[0]?.message?.content;
    if (res.ok && text) return { model, ok: true, secs, via, text: String(text).trim().replace(/\s+/g, " ") };
    return { model, ok: false, secs, via, text: body?.error?.message || `HTTP ${res.status}` };
  } catch (err) {
    const secs = (Date.now() - started) / 1000;
    return { model, ok: false, secs, via: "", text: err.name === "AbortError" ? `no answer in ${TIMEOUT_MS / 1000}s` : String(err.message) };
  } finally {
    clearTimeout(timer);
  }
}

const key = await getUnifiedKey();
const list = await (await fetch(`${BASE}/v1/models`, { headers: { Authorization: `Bearer ${key}` } })).json();
const models = (list.data || [])
  .filter((m) => m.available && !["auto", "fusion"].includes(m.id) && !SKIP.test(`${m.id} ${m.name || ""}`))
  .map((m) => m.id);

console.log(`Question: ${QUESTION}`);
console.log(`Asking ${models.length} models, ${PARALLEL} at a time...\n`);

const results = [];
let next = 0;
await Promise.all(
  Array.from({ length: PARALLEL }, async () => {
    while (next < models.length) {
      const r = await ask(models[next++], key);
      results.push(r);
      process.stdout.write(r.ok ? "." : "x");
    }
  })
);

results.sort((a, b) => b.ok - a.ok || a.secs - b.secs);
const lines = results.map((r) => {
  const provider = r.via.split("/")[0] || "-";
  return `${r.ok ? "OK " : "ERR"} ${r.secs.toFixed(1).padStart(5)}s  ${r.model}  [${provider}]\n      ${r.text.slice(0, 160)}`;
});
const ok = results.filter((r) => r.ok).length;
const report = `Question: ${QUESTION}\n\n${lines.join("\n")}\n\nAnswered: ${ok} of ${results.length}\n`;
console.log(`\n\n${report}`);
writeFileSync(`${HOME}/ask-all-results.txt`, report);
console.log(`Saved to ${HOME}/ask-all-results.txt`);
