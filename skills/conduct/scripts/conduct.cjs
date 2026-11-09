#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REQUEST_TYPES = new Set(["task", "review", "design", "question"]);
const BOXES = new Set(["outbox", "inbox"]);
const DELIVERY_STATES = new Set(["queued", "sent", "delivered", "answered", "failed"]);

function fail(message) {
  process.stderr.write(`conduct: ${message}\n`);
  process.exitCode = 1;
}

function usage() {
  process.stdout.write(`Usage:
  conduct.cjs emit --from ADDRESS --to ADDRESS --type TYPE (--prompt TEXT | --prompt-file PATH) [options]
  conduct.cjs mark --run ID --id ID --status STATE [--root PATH] [--transport NAME]
  conduct.cjs status [status.cjs arguments]

Options:
  --root PATH       Repository root (default: current directory)
  --run ID          Run ID (default: generated UUID)
  --box BOX         outbox or inbox (default: outbox)
  --id ID           Message ID (default: generated UUID)
  --cwd PATH        Receiver working directory (default: root)
  --ref ID          Request ID for a result envelope
  --prompt-file PATH Read the prompt as UTF-8 from PATH, or from stdin with -
  --transport NAME  Ledger transport label (default: pending)
  --status STATE    Initial: queued, sent, delivered, failed; results also received
                    Use mark for answered after a correlated result exists
`);
}

function dispatchStatus(argv) {
  const helper = path.join(__dirname, "status.cjs");
  const result = spawnSync(process.execPath, [helper, ...argv], {
    shell: false,
    stdio: "inherit"
  });
  if (result.error) throw new Error(`cannot run status helper: ${result.error.message}`);
  if (result.status === null) {
    const reason = result.signal ? `signal ${result.signal}` : "no exit status";
    throw new Error(`status helper terminated with ${reason}`);
  }
  process.exitCode = result.status;
}

function parseArgs(argv, command) {
  const args = {};
  const allowed = new Set(command === "mark"
    ? ["root", "run", "id", "transport", "status"]
    : ["root", "run", "box", "id", "cwd", "ref", "from", "to", "type", "prompt", "prompt-file", "transport", "status"]);
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      throw new Error(`unexpected argument: ${arg}`);
    }
    const key = arg.slice(2);
    if (!allowed.has(key)) throw new Error(`unknown option: ${arg}`);
    const value = argv[index + 1];
    if (value === undefined || (key !== "prompt" && value.startsWith("--"))) {
      throw new Error(`${arg} requires a value`);
    }
    if (Object.hasOwn(args, key)) {
      throw new Error(`${arg} may be provided only once`);
    }
    args[key] = value;
    index += 1;
  }
  return args;
}

function safeId(value, label) {
  if (typeof value !== "string" || value.length < 1 || value.length > 128) {
    throw new Error(`${label} must contain 1-128 characters`);
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(value) || value.includes("..")) {
    throw new Error(`${label} contains unsafe characters`);
  }
  return value;
}

function requiredText(value, label, max = 100000) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  if (value.length > max) {
    throw new Error(`${label} exceeds ${max} characters`);
  }
  return value;
}

function promptText(args) {
  const hasPrompt = Object.hasOwn(args, "prompt");
  const hasPromptFile = Object.hasOwn(args, "prompt-file");
  if (hasPrompt === hasPromptFile) {
    throw new Error("provide exactly one of --prompt or --prompt-file");
  }
  if (hasPrompt) return requiredText(args.prompt, "prompt");

  const promptFile = requiredText(args["prompt-file"], "prompt file", 32768);
  let value;
  try {
    value = fs.readFileSync(promptFile === "-" ? 0 : promptFile, "utf8");
  } catch (error) {
    throw new Error(`cannot read prompt file: ${error instanceof Error ? error.message : String(error)}`);
  }
  return requiredText(value, "prompt");
}

function loadTurns(ledgerPath) {
  if (!fs.existsSync(ledgerPath)) return [];
  return fs.readFileSync(ledgerPath, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch {
        throw new Error(`ledger contains invalid JSON on line ${index + 1}`);
      }
    });
}

function assertPhysicalState(root, target) {
  const relative = path.relative(root, target);
  let current = root;
  for (const component of relative.split(path.sep)) {
    current = path.join(current, component);
    try {
      if (fs.lstatSync(current).isSymbolicLink()) {
        throw new Error(`state path must not be a symbolic link: ${current}`);
      }
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

function withRunLock(runDir, callback) {
  const lockPath = path.join(runDir, ".write-lock");
  fs.mkdirSync(runDir, { recursive: true });
  try {
    fs.mkdirSync(lockPath);
  } catch (error) {
    if (error && error.code === "EEXIST") {
      throw new Error(`run lock exists: ${lockPath}; inspect owner.json and the writer process before removing a stale lock`);
    }
    throw error;
  }

  try {
    fs.writeFileSync(path.join(lockPath, "owner.json"), JSON.stringify({ pid: process.pid, started: new Date().toISOString() }), { flag: "wx", mode: 0o600 });
    return callback();
  } finally {
    fs.rmSync(path.join(lockPath, "owner.json"), { force: true });
    fs.rmdirSync(lockPath);
  }
}

function mark(args) {
  const root = path.resolve(args.root || process.cwd());
  const runId = safeId(args.run, "run ID");
  const messageId = safeId(args.id, "message ID");
  if (!DELIVERY_STATES.has(args.status)) throw new Error("status must be queued, sent, delivered, answered, or failed");
  const runDir = path.join(root, ".brain", "runs", runId);
  const ledgerPath = path.join(runDir, "turns.jsonl");
  assertPhysicalState(root, ledgerPath);
  return withRunLock(runDir, () => {
    const turns = loadTurns(ledgerPath);
    const previous = turns.filter((turn) => turn.envelope?.id === messageId).at(-1);
    if (!previous) throw new Error(`message ID does not exist in this run: ${messageId}`);
    if (args.status === "answered" && !turns.some((turn) => turn.envelope?.type === "result" && turn.envelope.ref === messageId)) {
      throw new Error("answered requires a correlated result in this run");
    }
    const event = {
      ts: new Date().toISOString(),
      envelope: previous.envelope,
      transport: args.transport || previous.transport,
      status: args.status
    };
    fs.appendFileSync(ledgerPath, `${JSON.stringify(event)}\n`);
    return { run_id: runId, id: messageId, status: args.status };
  });
}

function emit(args) {
  const root = path.resolve(args.root || process.cwd());
  const runId = safeId(args.run || crypto.randomUUID(), "run ID");
  const messageId = safeId(args.id || crypto.randomUUID(), "message ID");
  const box = args.box || "outbox";
  if (!BOXES.has(box)) throw new Error("box must be outbox or inbox");

  const from = requiredText(args.from, "from", 512);
  const to = requiredText(args.to, "to", 512);
  if (from === to) throw new Error("from and to must identify different sessions");

  const type = requiredText(args.type, "type", 32);
  if (type !== "result" && !REQUEST_TYPES.has(type)) {
    throw new Error("type must be task, review, design, question, or result");
  }
  const status = args.status ?? (type === "result" ? "received" : "queued");
  if (status === "answered" || (!DELIVERY_STATES.has(status) && !(status === "received" && type === "result"))) {
    throw new Error("invalid initial status; use mark for answered after a correlated result");
  }
  if (box !== (type === "result" ? "inbox" : "outbox")) {
    throw new Error("requests require outbox and results require inbox");
  }

  const prompt = promptText(args);
  const cwd = path.resolve(args.cwd || root);
  const ref = args.ref ? safeId(args.ref, "ref") : null;
  if (type === "result" && ref === null) throw new Error("result envelopes require --ref");
  if (type !== "result" && ref !== null) throw new Error("only result envelopes may carry --ref");

  const runDir = path.join(root, ".brain", "runs", runId);
  const ledgerPath = path.join(runDir, "turns.jsonl");
  const messagePath = path.join(runDir, box, `${messageId}.json`);
  const envelope = { v: 1, id: messageId, from, to, type, prompt, cwd, ref };

  assertPhysicalState(root, ledgerPath);
  assertPhysicalState(root, messagePath);

  return withRunLock(runDir, () => {
    const turns = loadTurns(ledgerPath);
    if (turns.some((turn) => turn.envelope && turn.envelope.id === messageId)) {
      throw new Error(`message ID already exists in run: ${messageId}`);
    }

    if (ref !== null) {
      const parent = turns.find((turn) => turn.envelope && turn.envelope.id === ref)?.envelope;
      if (!parent) throw new Error(`response ref does not exist in this run: ${ref}`);
      if (parent.ref !== null || parent.type === "result") {
        throw new Error("responses cannot reference another response");
      }
      if (from !== parent.to || to !== parent.from) {
        throw new Error("response addresses must reverse the request addresses");
      }
      if (turns.some((turn) => turn.envelope && turn.envelope.ref === ref)) {
        throw new Error(`request already has a response: ${ref}`);
      }
    }

    const serializedEnvelope = `${JSON.stringify(envelope, null, 2)}\n`;
    let createdMessage = false;
    fs.mkdirSync(path.dirname(messagePath), { recursive: true });
    if (fs.existsSync(messagePath)) {
      if (fs.readFileSync(messagePath, "utf8") !== serializedEnvelope) {
        throw new Error(`message path already exists with different content: ${messagePath}`);
      }
    } else {
      fs.writeFileSync(messagePath, serializedEnvelope, { flag: "wx" });
      createdMessage = true;
    }
    const turn = {
      ts: new Date().toISOString(),
      envelope,
      transport: args.transport || "pending",
      status
    };
    try {
      fs.appendFileSync(ledgerPath, `${JSON.stringify(turn)}\n`);
    } catch (error) {
      if (createdMessage) fs.unlinkSync(messagePath);
      throw error;
    }
    return { run_id: runId, path: messagePath, envelope };
  });
}

function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") {
    usage();
    return;
  }
  if (command === "status") {
    dispatchStatus(rest);
    return;
  }
  if (command !== "emit" && command !== "mark") throw new Error(`unknown command: ${command}`);
  const args = parseArgs(rest, command);
  const result = command === "emit" ? emit(args) : mark(args);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

try {
  main();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
