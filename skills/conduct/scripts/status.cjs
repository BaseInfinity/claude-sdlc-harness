#!/usr/bin/env node

// Fleet status: one row per controller workstream in <root>/.brain/fleet.json,
// rendered as a plain-text view, under a [USAGE] section built from the
// account-usage rows that collectors append to <root>/.brain/usage/*.jsonl. Sibling of conduct.cjs, which stays
// byte-identical to the Codex upstream helper.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const LABELS = ["CONDUCTOR", "HARNESS", "MEESEEKS", "ANTICHEAT", "CODEX", "ROBBIE", "WINDOWS"];
const STATES = ["in_flight", "blocked", "planned", "done"];
const COLORS = { HARNESS: "38;5;208", CONDUCTOR: "31", ANTICHEAT: "38;5;213", CODEX: "32" };
const STALE_MS = 24 * 60 * 60 * 1000;
const USAGE_STALE_MS = 6 * 60 * 60 * 1000;
const BASE_ACCOUNTS = ["claude-main"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function fail(message) {
  process.stderr.write(`status: ${message}\n`);
  process.exitCode = 1;
}

function usage() {
  process.stdout.write(`Usage:
  status.cjs set --root R --controller LABEL --workstream NAME --percent N
                 --state in_flight|blocked|done|planned [--blocker-owner X]
                 [--next STEP] [--evidence PATH_OR_LINK]
  status.cjs [--root R] [--controller LABEL] [--now ISO]

Labels: ${LABELS.join(", ")}
set replaces the whole row keyed LABEL/slug(workstream) and stamps updated_at.
--blocker-owner is required with --state blocked and refused otherwise.
The full view opens with [USAGE]: the newest row per account/provider/window
from <root>/.brain/usage/*.jsonl, STALE past 6h, and "unknown" for an account
with no pct row. Rows in any other unit are not rendered; a row with accuracy
"unattributed" says so. <root>/.brain/usage/accounts.json renames raw labels, e.g.
{"codex-56c919": "codex-main"}; every name it maps to is expected.
`);
}

function parseArgs(argv, allowed) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) throw new Error(`unexpected argument: ${arg}`);
    const key = arg.slice(2);
    if (!allowed.includes(key)) throw new Error(`unknown option: ${arg}`);
    const value = argv[index + 1];
    if (value === undefined || (key !== "percent" && value.startsWith("--"))) {
      throw new Error(`${arg} requires a value`);
    }
    if (Object.hasOwn(args, key)) throw new Error(`${arg} may be provided only once`);
    args[key] = value;
    index += 1;
  }
  return args;
}

function label(value) {
  const upper = String(value || "").toUpperCase();
  if (!LABELS.includes(upper)) throw new Error(`controller must be one of ${LABELS.join(", ")}`);
  return upper;
}

function slug(name) {
  const value = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  if (!value) throw new Error("workstream must contain a letter or digit");
  return value;
}

function fleetPath(root) {
  const base = path.resolve(root || process.cwd());
  const file = path.join(base, ".brain", "fleet.json");
  for (const target of [path.dirname(file), file]) {
    try {
      if (fs.lstatSync(target).isSymbolicLink()) throw new Error(`state path must not be a symbolic link: ${target}`);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  return file;
}

function load(file) {
  if (!fs.existsSync(file)) return { v: 1, rows: {} };
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!data || typeof data.rows !== "object") throw new Error(`${file} has no rows object`);
  return data;
}

function withLock(file, callback) {
  const lockPath = `${file}.lock`;
  try {
    fs.mkdirSync(lockPath);
  } catch (error) {
    if (error && error.code === "EEXIST") {
      throw new Error(`fleet lock exists: ${lockPath}; remove it only if no writer is running`);
    }
    throw error;
  }
  try {
    return callback();
  } finally {
    fs.rmdirSync(lockPath);
  }
}

function set(args) {
  if (!args.root) throw new Error("set requires --root");
  const controller = label(args.controller);
  const workstream = String(args.workstream || "").trim();
  const key = `${controller}/${slug(workstream)}`;
  if (!/^(0|[1-9][0-9]?|100)$/.test(args.percent || "")) {
    throw new Error("percent must be an integer from 0 to 100");
  }
  if (!STATES.includes(args.state)) throw new Error(`state must be one of ${STATES.join(", ")}`);
  const owner = String(args["blocker-owner"] || "").trim();
  if (args.state === "blocked" && !owner) throw new Error("--state blocked requires --blocker-owner");
  if (args.state !== "blocked" && owner) throw new Error("--blocker-owner is allowed only with --state blocked");

  const file = fleetPath(args.root);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  return withLock(file, () => {
    const data = load(file);
    data.rows[key] = {
      controller,
      workstream,
      percent: Number(args.percent),
      state: args.state,
      blocker_owner: owner,
      next_step: args.next || "",
      updated_at: new Date().toISOString(),
      evidence: args.evidence || ""
    };
    // Random name, exclusive create: a path planted in advance, symlink or
    // not, is never written through; a collision fails with EEXIST.
    const temp = `${file}.${crypto.randomBytes(8).toString("hex")}.tmp`;
    fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`, { flag: "wx" });
    fs.renameSync(temp, file);
    return { key, row: data.rows[key] };
  });
}

function bar(percent) {
  // Floor, so only 100 fills the bar; any nonzero percent shows one cell.
  const cells = percent === 0 ? 0 : Math.max(1, Math.floor(percent / 10));
  return "█".repeat(cells) + "░".repeat(10 - cells);
}

function age(ms) {
  const hours = Math.floor(ms / 3600000);
  return hours >= 48 ? `${Math.floor(hours / 24)}d` : `${hours}h`;
}

// accounts.json maps a raw row label (codex-56c919) to the name to print
// (codex-main). Every name it maps to is an expected account.
function loadAliases(dir) {
  const file = path.join(dir, "accounts.json");
  if (!fs.existsSync(file)) return {};
  let aliases;
  try {
    aliases = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new Error(`${file}: ${error.message}`);
  }
  const valid = aliases && typeof aliases === "object" && !Array.isArray(aliases)
    && Object.values(aliases).every((name) => typeof name === "string" && name);
  if (!valid) throw new Error(`${file} must map each raw account label to a non-empty name`);
  return aliases;
}

function loadUsage(root) {
  const dir = path.join(path.resolve(root || process.cwd()), ".brain", "usage");
  const names = fs.existsSync(dir) ? fs.readdirSync(dir).filter((name) => name.endsWith(".jsonl")).sort() : [];
  const files = names.map((name) => ({
    account: name.slice(0, -".jsonl".length),
    lines: fs.readFileSync(path.join(dir, name), "utf8").split("\n")
  }));
  return { files, aliases: loadAliases(dir) };
}

function parseUsage(text) {
  try {
    const row = JSON.parse(text);
    const valid = row && typeof row.account === "string" && typeof row.provider === "string"
      && typeof row.window === "string" && typeof row.used === "number"
      && !Number.isNaN(Date.parse(row.observed_at));
    return valid ? row : null;
  } catch {
    return null;
  }
}

// Newest pct row per account/provider/window, after aliasing; rows in any
// other unit are dropped unconverted, and their account still lists. A file
// named for an account that holds no valid row still lists that account, as
// does every alias target, so each renders as unknown.
function latestUsage({ files, aliases }) {
  const name = (account) => (Object.hasOwn(aliases, account) ? aliases[account] : account);
  const accounts = new Set([...BASE_ACCOUNTS, ...Object.values(aliases)]);
  const latest = new Map();
  for (const file of files) {
    accounts.add(name(file.account));
    for (const parsed of file.lines.map(parseUsage).filter(Boolean)) {
      const row = { ...parsed, account: name(parsed.account) };
      accounts.add(row.account);
      if (row.unit !== "pct") continue;
      const key = `${row.account}\u0000${row.provider}\u0000${row.window}`;
      const held = latest.get(key);
      if (!held || Date.parse(row.observed_at) > Date.parse(held.observed_at)) latest.set(key, row);
    }
  }
  return { accounts: [...accounts].sort(), rows: [...latest.values()] };
}

function localTime(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "unknown";
  const pad = (value) => String(value).padStart(2, "0");
  return `${DAYS[date.getDay()]} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function renderUsage({ accounts, rows }, now) {
  const lines = ["[USAGE]"];
  for (const account of accounts) {
    const own = rows.filter((row) => row.account === account)
      .sort((a, b) => a.provider.localeCompare(b.provider) || a.window.localeCompare(b.window));
    if (own.length === 0) lines.push(`  ${account} unknown`);
    for (const row of own) {
      const used = Math.max(0, Math.min(100, Math.floor(row.used)));
      const old = now - Date.parse(row.observed_at);
      const stale = old > USAGE_STALE_MS ? `  STALE ${age(old)}` : "";
      const unattributed = row.accuracy === "unattributed" ? " · unattributed" : "";
      lines.push(`  ${account} ${row.provider} ${row.window}  ${bar(used)} ${used}% · resets ${localTime(row.resets_at)}${unattributed}${stale}`);
    }
  }
  return `${lines.join("\n")}\n`;
}

function render(data, { controller, now, color }) {
  const paint = (code, text) => (color && code ? `\u001b[${code}m${text}\u001b[0m` : text);
  const rows = Object.values(data.rows);
  const lines = [];
  for (const name of controller ? [label(controller)] : LABELS) {
    const own = rows
      .filter((row) => row.controller === name)
      .sort((a, b) => STATES.indexOf(a.state) - STATES.indexOf(b.state)
        || a.workstream.localeCompare(b.workstream));
    if (own.length === 0) continue;
    if (lines.length) lines.push("");
    lines.push(paint(COLORS[name], `[${name}]`));
    for (const row of own) {
      const old = now - Date.parse(row.updated_at);
      const stale = old > STALE_MS ? `  STALE ${age(old)}` : "";
      lines.push(`  ${paint(COLORS[name], bar(row.percent))} ${String(row.percent).padStart(3)}% ${row.workstream}${stale}`);
      const state = row.state === "blocked" ? `blocked on ${row.blocker_owner}` : row.state.replace("_", " ");
      const next = row.next_step ? ` · next: ${row.next_step}` : "";
      const evidence = row.evidence ? ` · ${row.evidence}` : "";
      lines.push(`                  ${state}${next}${evidence}`);
    }
  }
  return lines.length ? `${lines.join("\n")}\n` : "no fleet rows\n";
}

function main() {
  const [first, ...rest] = process.argv.slice(2);
  if (first === "--help" || first === "-h") {
    usage();
    return;
  }
  if (first === "set") {
    const args = parseArgs(rest, ["root", "controller", "workstream", "percent", "state", "blocker-owner", "next", "evidence"]);
    process.stdout.write(`${JSON.stringify(set(args))}\n`);
    return;
  }
  const args = parseArgs(process.argv.slice(2), ["root", "controller", "now"]);
  const now = args.now ? Date.parse(args.now) : Date.now();
  if (Number.isNaN(now)) throw new Error("--now must be an ISO timestamp");
  const color = Boolean(process.stdout.isTTY) && !process.env.NO_COLOR;
  const fleet = render(load(fleetPath(args.root)), { controller: args.controller, now, color });
  const usageText = args.controller ? "" : `${renderUsage(latestUsage(loadUsage(args.root)), now)}\n`;
  process.stdout.write(usageText + fleet);
}

try {
  main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
