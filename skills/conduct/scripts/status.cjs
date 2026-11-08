#!/usr/bin/env node

// Fleet status: one row per controller workstream in <root>/.brain/fleet.json,
// rendered as a plain-text view. Sibling of conduct.cjs, which stays
// byte-identical to the Codex upstream helper.

const fs = require("node:fs");
const path = require("node:path");

const LABELS = ["CONDUCTOR", "HARNESS", "MEESEEKS", "ANTICHEAT", "CODEX", "ROBBIE", "WINDOWS"];
const STATES = ["in_flight", "blocked", "planned", "done"];
const COLORS = { HARNESS: "38;5;208", CONDUCTOR: "31", ANTICHEAT: "38;5;213", CODEX: "32" };
const STALE_MS = 24 * 60 * 60 * 1000;

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
    const temp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(temp, `${JSON.stringify(data, null, 2)}\n`);
    fs.renameSync(temp, file);
    return { key, row: data.rows[key] };
  });
}

function bar(percent) {
  const cells = Math.round(percent / 10);
  return "█".repeat(cells) + "░".repeat(10 - cells);
}

function age(ms) {
  const hours = Math.floor(ms / 3600000);
  return hours >= 48 ? `${Math.floor(hours / 24)}d` : `${hours}h`;
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
  process.stdout.write(render(load(fleetPath(args.root)), { controller: args.controller, now, color }));
}

try {
  main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
