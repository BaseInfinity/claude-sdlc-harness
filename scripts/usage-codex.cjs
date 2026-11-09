#!/usr/bin/env node

// Codex usage collector: appends each Codex account's newest plan-limit
// reading as shared usage rows to <root>/.brain/usage/codex-<id>.jsonl, for
// status.cjs.
//
// Reads two things from $CODEX_HOME/sessions/**/*.jsonl and nothing else: the
// first line's session_meta.creator_account_id, and `event_msg`/`token_count`
// events' `rate_limits`. The account is the first 6 characters of
// creator_account_id; status.cjs maps it to a name via accounts.json.
//
// creator_account_id is fixed when a thread is created. A thread resumed
// under a different login keeps its creator but reports the new login's
// rate_limits, and no line in a rollout names the login that wrote it. So a
// reading can never be proven to be its creator's: every row is marked
// accuracy "unattributed". A thread whose readings change plan_type shows a
// login change and is skipped, as is a thread with no creator_account_id.
//
// Follow-up: Codex's app-server `account/rateLimits/read` returns an
// accountId with its limits. That is the account-bound source, but it needs a
// live app-server call, which this file-only collector does not make.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const WINDOWS = { 300: "5h", 10080: "7d" };

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

// The first line only, read in chunks so a large transcript is never loaded.
function firstLine(file) {
  const fd = fs.openSync(file, "r");
  try {
    const chunks = [];
    const buffer = Buffer.alloc(65536);
    for (;;) {
      const read = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (read === 0) break;
      const end = buffer.subarray(0, read).indexOf(10);
      chunks.push(Buffer.from(buffer.subarray(0, end === -1 ? read : end)));
      if (end !== -1) break;
    }
    return Buffer.concat(chunks).toString("utf8");
  } finally {
    fs.closeSync(fd);
  }
}

function creator(file) {
  try {
    const meta = JSON.parse(firstLine(file));
    const id = meta.payload?.creator_account_id;
    return typeof id === "string" && id.length >= 6 ? `codex-${id.slice(0, 6)}` : null;
  } catch {
    return null;
  }
}

// Null when the thread's codex readings span more than one plan_type.
function newestIn(file) {
  let best = null;
  const plans = new Set();
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
    plans.add(limits.plan_type);
    if (!best || Date.parse(event.timestamp) > Date.parse(best.timestamp)) best = { timestamp: event.timestamp, limits };
  }
  return plans.size > 1 ? null : best;
}

// Newest `codex` rate_limits event per account, by the event's own timestamp.
// A file is never written after its last event, so a file whose mtime
// predates its account's best event so far cannot hold a newer one.
function newestPerAccount(files) {
  const best = new Map();
  for (const { file, mtime } of files) {
    const account = creator(file);
    if (!account) continue;
    const held = best.get(account);
    if (held && mtime < Date.parse(held.timestamp)) continue;
    const found = newestIn(file);
    if (found && (!held || Date.parse(found.timestamp) > Date.parse(held.timestamp))) best.set(account, found);
  }
  return best;
}

function rows(account, { timestamp, limits }) {
  return [limits.primary, limits.secondary]
    .filter((window) => window && typeof window.used_percent === "number")
    .map((window) => ({
      account,
      provider: "codex",
      window: WINDOWS[window.window_minutes] || `${window.window_minutes}m`,
      used: window.used_percent,
      limit: 100,
      unit: "pct",
      resets_at: new Date(window.resets_at * 1000).toISOString(),
      source: `codex-rollout plan=${limits.plan_type}`,
      accuracy: "unattributed",
      observed_at: new Date(timestamp).toISOString()
    }))
    .sort((a, b) => a.window.localeCompare(b.window));
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.length !== 2 || argv[0] !== "--root") throw new Error("usage: usage-codex.cjs --root R");
  const home = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
  const found = [...newestPerAccount(rollouts(path.join(home, "sessions")))]
    .map(([account, event]) => rows(account, event))
    .filter((list) => list.length > 0);
  if (found.length === 0) throw new Error(`no attributable codex rate_limits event under ${home}/sessions`);
  const dir = path.join(path.resolve(argv[1]), ".brain", "usage");
  fs.mkdirSync(dir, { recursive: true });
  // Refuse a symlinked output before writing any, so a refused collect writes
  // nothing; O_NOFOLLOW also refuses one planted after the check.
  const outputs = found.map((list) => path.join(dir, `${list[0].account}.jsonl`));
  for (const file of outputs) {
    if (fs.lstatSync(file, { throwIfNoEntry: false })?.isSymbolicLink()) throw new Error(`refusing symlinked ${file}`);
  }
  const { O_WRONLY, O_APPEND, O_CREAT, O_NOFOLLOW } = fs.constants;
  found.forEach((list, index) => {
    const text = list.map((row) => `${JSON.stringify(row)}\n`).join("");
    const fd = fs.openSync(outputs[index], O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o644);
    try {
      fs.writeSync(fd, text);
    } finally {
      fs.closeSync(fd);
    }
    process.stdout.write(text);
  });
}

try {
  main();
} catch (error) {
  process.stderr.write(`usage-codex: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
