#!/usr/bin/env node

// Session handoff documents for /conduct orient. Not vendored: conduct.cjs and
// protocol.md are hash-pinned to codex-sdlc-wizard, so this lives beside them.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const OPTIONS = {
  write: ["root", "session", "branch", "id", "file"],
  read: ["root", "id"],
  list: ["root", "limit"]
};
const LIST_FIELDS = ["next_steps", "warnings", "worktrees", "open_prs", "held_items"];
const TASK_FIELDS = ["completed", "in_progress", "blocked"];

function usage() {
  process.stdout.write(`Usage:
  handoff.cjs write --root PATH --session ADDRESS --branch NAME [--id ID] [--file PATH]
  handoff.cjs read  --root PATH [--id ID]      latest by created when --id is omitted
  handoff.cjs list  --root PATH [--limit N]    newest first, default limit 10

Handoffs live at <root>/.brain/handoffs/<id>.json. --file supplies tasks,
next_steps, warnings, worktrees, open_prs and held_items; v, id, created,
session, branch and sha always come from the arguments and the repository.
`);
}

function parseArgs(argv, command) {
  const allowed = new Set(OPTIONS[command]);
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const arg = argv[index];
    if (!arg.startsWith("--")) throw new Error(`unexpected argument: ${arg}`);
    const key = arg.slice(2);
    if (!allowed.has(key)) throw new Error(`unknown option: ${arg}`);
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) throw new Error(`${arg} requires a value`);
    if (Object.hasOwn(args, key)) throw new Error(`${arg} may be provided only once`);
    args[key] = value;
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

function rootDir(value) {
  if (!value) throw new Error("--root is required");
  const root = path.resolve(value);
  if (!fs.statSync(root, { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`root is not a directory: ${root}`);
  }
  return root;
}

function handoffDir(root) {
  const dir = path.join(root, ".brain", "handoffs");
  assertPhysicalState(root, dir);
  return dir;
}

function headSha(root) {
  const result = spawnSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`cannot read HEAD sha in ${root}`);
  return result.stdout.trim();
}

const isString = (item) => typeof item === "string";
const isObjectOf = (keys) => (item) => item !== null && typeof item === "object" && !Array.isArray(item)
  && keys.every((key) => typeof item[key] === "string");
const ITEM_CHECKS = {
  "tasks.completed": [isString, "strings"],
  "tasks.in_progress": [isString, "strings"],
  "tasks.blocked": [isObjectOf(["task", "reason"]), "{task, reason} objects"],
  next_steps: [isString, "strings"],
  warnings: [isString, "strings"],
  worktrees: [isString, "strings"],
  open_prs: [Number.isInteger, "integers"],
  held_items: [isObjectOf(["item", "waiting_on"]), "{item, waiting_on} objects"]
};

function arrayField(value, label) {
  if (value === undefined) return [];
  const [check, expected] = ITEM_CHECKS[label];
  if (!Array.isArray(value) || !value.every(check)) throw new Error(`${label} must be an array of ${expected}`);
  return value;
}

function readFields(file) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    throw new Error(`cannot read --file: ${error.message}`);
  }
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("--file must contain a JSON object");
  }
  const tasks = data.tasks ?? {};
  if (tasks === null || typeof tasks !== "object" || Array.isArray(tasks)) {
    throw new Error("tasks must be an object");
  }
  const fields = { tasks: {} };
  for (const key of TASK_FIELDS) fields.tasks[key] = arrayField(tasks[key], `tasks.${key}`);
  for (const key of LIST_FIELDS) fields[key] = arrayField(data[key], key);
  return fields;
}

function write(args) {
  const root = rootDir(args.root);
  const session = args.session;
  if (typeof session !== "string" || !session.includes(":") || session.length > 512) {
    throw new Error("--session must be an address such as claude:<uuid> or codex:<uuid>");
  }
  if (typeof args.branch !== "string" || args.branch.trim() === "") throw new Error("--branch is required");
  const generated = `${new Date().toISOString().replace(/[:.]/g, "-")}-${crypto.randomUUID().slice(0, 8)}`;
  const id = safeId(args.id || generated, "handoff ID");
  const fields = args.file
    ? readFields(args.file)
    : { tasks: { completed: [], in_progress: [], blocked: [] }, ...Object.fromEntries(LIST_FIELDS.map((key) => [key, []])) };

  const dir = handoffDir(root);
  const target = path.join(dir, `${id}.json`);
  assertPhysicalState(root, target);
  const handoff = {
    v: 1,
    id,
    created: new Date().toISOString(),
    session,
    branch: args.branch,
    sha: headSha(root),
    ...fields
  };
  fs.mkdirSync(dir, { recursive: true });
  try {
    fs.writeFileSync(target, `${JSON.stringify(handoff, null, 2)}\n`, { flag: "wx" });
  } catch (error) {
    if (error.code === "EEXIST") throw new Error(`handoff already exists: ${id}`);
    throw error;
  }
  return { id, path: target };
}

function loadAll(root) {
  const dir = handoffDir(root);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const file = path.join(dir, name);
      assertPhysicalState(root, file);
      try {
        return JSON.parse(fs.readFileSync(file, "utf8"));
      } catch {
        throw new Error(`handoff contains invalid JSON: ${file}`);
      }
    })
    .sort((a, b) => String(b.created).localeCompare(String(a.created)) || String(b.id).localeCompare(String(a.id)));
}

function read(args) {
  const root = rootDir(args.root);
  if (args.id) {
    const id = safeId(args.id, "handoff ID");
    const found = loadAll(root).find((handoff) => handoff.id === id);
    if (!found) throw new Error(`no handoff with id: ${id}`);
    return found;
  }
  const latest = loadAll(root)[0];
  if (!latest) throw new Error(`no handoffs in ${path.join(root, ".brain", "handoffs")}`);
  return latest;
}

function list(args) {
  const root = rootDir(args.root);
  const limit = args.limit === undefined ? 10 : Number(args.limit);
  if (!Number.isInteger(limit) || limit < 1) throw new Error("--limit must be a positive integer");
  return loadAll(root).slice(0, limit)
    .map(({ id, created, session, branch, sha }) => JSON.stringify({ id, created, session, branch, sha }));
}

function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h") return usage();
  if (!Object.hasOwn(OPTIONS, command)) throw new Error(`unknown command: ${command}`);
  const args = parseArgs(rest, command);
  if (command === "write") process.stdout.write(`${JSON.stringify(write(args))}\n`);
  if (command === "read") process.stdout.write(`${JSON.stringify(read(args), null, 2)}\n`);
  if (command === "list") for (const line of list(args)) process.stdout.write(`${line}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`handoff: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
