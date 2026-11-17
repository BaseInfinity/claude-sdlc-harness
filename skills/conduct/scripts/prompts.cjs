#!/usr/bin/env node

// Stalled-prompt watcher: lists iTerm2 panes whose last screen is a Claude Code
// permission dialog, a Codex approval dialog or an AskUserQuestion dialog.
// Read-only by construction: it calls only `it2api list-sessions` and
// `it2api get-buffer`, and prints the pane's id and title, never its text.
// Answering a prompt is never this script's job (protocol.md, operating rule 10).

const childProcess = require("node:child_process");
const fs = require("node:fs");

const DEFAULT_IT2API = "/Applications/iTerm.app/Contents/Resources/utilities/it2api";
// A dialog is live only while it is the last thing on screen. Anything that
// scrolled above this many non-empty lines was answered or abandoned.
const TAIL = 14;
const BORDER = /^[\s│|╭╮╰╯─]+|[\s│|]+$/g;

// Strings verified in the installed binaries: Claude Code 2.1.321, Codex 0.167.0.
const KINDS = [
  {
    kind: "claude-permission",
    question: /^Do you want to .+\?$/,
    option: /^[❯›>]?\s*\d+\.\s+No, and tell Claude what to do differently/,
  },
  {
    kind: "codex-approval",
    question: /^Would you like to (run the following command|make the following edits|grant these permissions)\?$/,
    option: /^[❯›>]?\s*\d+\.\s+No, and tell Codex what to do differently/,
  },
  // AskUserQuestion and other pickers: the footer alone marks a live dialog.
  { kind: "question", question: null, option: /^Enter to select · .*Esc to cancel$/ },
];

function usage() {
  process.stdout.write(`Usage:
  prompts.cjs scan [--it2api PATH] [--state FILE] [--now ISO]

Lists every iTerm2 pane whose last screen is a Claude permission dialog
(claude-permission), a Codex approval dialog (codex-approval) or an
AskUserQuestion dialog (question), one line each:
  STALLED <kind> age=<seconds>s <id8> "<pane title>"
Prints no buffer text. Never sends input to any pane.
--state keeps first-seen times so age survives between scans; a prompt that
clears and returns starts again at 0s. Exit 1 when it2api fails.
`);
}

function parseArgs(argv) {
  const opts = { it2api: process.env.IT2API || DEFAULT_IT2API, state: "", now: "" };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    const value = argv[i + 1];
    if (flag === "--it2api" || flag === "--state" || flag === "--now") {
      if (value === undefined) throw new Error(`${flag} needs a value`);
      opts[flag.slice(2)] = value;
      i += 1;
    } else {
      throw new Error(`unknown argument: ${flag}`);
    }
  }
  return opts;
}

function it2api(bin, args) {
  const result = childProcess.spawnSync(bin, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (result.status !== 0) {
    const why = (result.stderr || "").trim() || (result.error && result.error.message) || `exit ${result.status}`;
    throw new Error(`it2api ${args[0]} failed: ${why}`);
  }
  return result.stdout;
}

function listSessions(bin) {
  const sessions = [];
  for (const line of it2api(bin, ["list-sessions"]).split("\n")) {
    const match = /^Session "(.*)" id=([A-F0-9-]+) /.exec(line);
    if (match) sessions.push({ title: match[1], id: match[2] });
  }
  return sessions;
}

// Returns the kind of the live dialog at the bottom of the buffer, or null.
function classify(buffer) {
  const lines = buffer.split("\n").map((l) => l.replace(BORDER, "")).filter((l) => l !== "");
  const tail = lines.slice(-TAIL);
  for (const rule of KINDS) {
    const optionAt = tail.findIndex((l) => rule.option.test(l));
    if (optionAt === -1) continue;
    if (rule.question && !tail.slice(0, optionAt).some((l) => rule.question.test(l))) continue;
    return rule.kind;
  }
  return null;
}

function readState(file) {
  if (!file || !fs.existsSync(file)) return {};
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function scan(opts) {
  const nowMs = opts.now ? Date.parse(opts.now) : Date.now();
  if (Number.isNaN(nowMs)) throw new Error(`--now is not a date: ${opts.now}`);
  const previous = readState(opts.state);
  const next = {};
  const rows = [];
  const sessions = listSessions(opts.it2api);
  for (const session of sessions) {
    const kind = classify(it2api(opts.it2api, ["get-buffer", session.id]));
    if (!kind) continue;
    // Keyed by pane and kind, not by the dialog's text: moving the selection
    // cursor re-renders the dialog without clearing it.
    const key = `${session.id}/${kind}`;
    const firstSeen = previous[key] || new Date(nowMs).toISOString();
    next[key] = firstSeen;
    const age = Math.max(0, Math.round((nowMs - Date.parse(firstSeen)) / 1000));
    rows.push(`STALLED ${kind} age=${age}s ${session.id.slice(0, 8)} "${session.title}"`);
  }
  if (opts.state) fs.writeFileSync(opts.state, `${JSON.stringify(next, null, 2)}\n`);
  process.stdout.write(rows.length ? `${rows.join("\n")}\n` : `no stalled prompts (${sessions.length} panes scanned)\n`);
}

function main(argv) {
  if (argv[0] === "--help" || argv[0] === "-h") return usage();
  if (argv[0] !== "scan") {
    usage();
    process.exitCode = 1;
    return;
  }
  try {
    scan(parseArgs(argv.slice(1)));
  } catch (error) {
    process.stderr.write(`prompts: ${error.message}\n`);
    process.exitCode = 1;
  }
}

main(process.argv.slice(2));
