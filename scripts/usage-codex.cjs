#!/usr/bin/env node

// Codex usage collector: appends the newest Codex plan-limit reading as
// shared usage rows to <root>/.brain/usage/<account>.jsonl, for status.cjs.
//
// Reads only `event_msg` / `token_count` events from
// $CODEX_HOME/sessions/**/*.jsonl, and only their `rate_limits` object. Those
// events name no account: `plan_type` is the plan at that moment, not an
// identity. So the account is labelled by CODEX_HOME (~/.codex = codex-main),
// and a second account needs its own CODEX_HOME.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const WINDOWS = { 300: "5h", 10080: "7d" };

function account(home) {
  const name = path.basename(path.resolve(home)).replace(/^\.+/, "");
  return name === "codex" ? "codex-main" : name;
}

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(file);
    return entry.isFile() && entry.name.endsWith(".jsonl") ? [file] : [];
  });
}

function rollouts(dir) {
  return walk(dir)
    .map((file) => ({ file, mtime: fs.statSync(file).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
}

// Newest `codex` rate_limits event by its own timestamp. A file is never
// written after its last event, so once a file's mtime predates the best
// event so far, no older-mtime file can hold a newer one.
function newest(files) {
  let best = null;
  for (const { file, mtime } of files) {
    if (best && mtime < Date.parse(best.timestamp)) break;
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      if (!line.includes('"rate_limits"')) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      const limits = event.type === "event_msg" && event.payload?.type === "token_count" && event.payload.rate_limits;
      if (!limits || limits.limit_id !== "codex" || Number.isNaN(Date.parse(event.timestamp))) continue;
      if (!best || Date.parse(event.timestamp) > Date.parse(best.timestamp)) best = { timestamp: event.timestamp, limits };
    }
  }
  return best;
}

function rows(name, { timestamp, limits }) {
  return [limits.primary, limits.secondary]
    .filter((window) => window && typeof window.used_percent === "number")
    .map((window) => ({
      account: name,
      provider: "codex",
      window: WINDOWS[window.window_minutes] || `${window.window_minutes}m`,
      used: window.used_percent,
      limit: 100,
      unit: "pct",
      resets_at: new Date(window.resets_at * 1000).toISOString(),
      source: `codex-rollout plan=${limits.plan_type}`,
      accuracy: "server",
      observed_at: new Date(timestamp).toISOString()
    }))
    .sort((a, b) => a.window.localeCompare(b.window));
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length !== 2 || argv[0] !== "--root") throw new Error("usage: usage-codex.cjs --root R");
  const home = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
  const event = newest(rollouts(path.join(home, "sessions")));
  const found = event ? rows(account(home), event) : [];
  if (found.length === 0) throw new Error(`no codex rate_limits event under ${home}/sessions`);
  const dir = path.join(path.resolve(argv[1]), ".brain", "usage");
  fs.mkdirSync(dir, { recursive: true });
  const text = found.map((row) => `${JSON.stringify(row)}\n`).join("");
  fs.appendFileSync(path.join(dir, `${found[0].account}.jsonl`), text);
  process.stdout.write(text);
}

try {
  main();
} catch (error) {
  process.stderr.write(`usage-codex: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
