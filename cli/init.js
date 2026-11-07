'use strict';

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const RESET = '\x1b[0m';
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const MAGENTA = '\x1b[35m';
const CYAN = '\x1b[36m';

const REPO_ROOT = path.join(__dirname, '..');
const TEMPLATES_DIR = path.join(__dirname, 'templates');
const WIZARD_DOC = path.join(REPO_ROOT, 'CLAUDE_CODE_SDLC_WIZARD.md');

// Skills and hooks live at repo root (single source of truth for both plugin and CLI)
// Only settings.json remains in cli/templates/ (CLI-specific hook config)
const FILES = [
  { src: 'settings.json', dest: '.claude/settings.json', base: TEMPLATES_DIR },
  { src: 'hooks/sdlc-prompt-check.sh', dest: '.claude/hooks/sdlc-prompt-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/tdd-pretool-check.sh', dest: '.claude/hooks/tdd-pretool-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/instructions-loaded-check.sh', dest: '.claude/hooks/instructions-loaded-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/model-effort-check.sh', dest: '.claude/hooks/model-effort-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/precompact-seam-check.sh', dest: '.claude/hooks/precompact-seam-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/codex-gate-check.sh', dest: '.claude/hooks/codex-gate-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/token-spike-check.sh', dest: '.claude/hooks/token-spike-check.sh', executable: true, base: REPO_ROOT },
  { src: 'hooks/codex-review-stop-check.sh', dest: '.claude/hooks/codex-review-stop-check.sh', executable: true, base: REPO_ROOT },
  // #254 Bug 1: shared helper sourced by all hooks above. Must ship — without
  // it, hooks emit "_find-sdlc-root.sh: No such file or directory" + the
  // SDLC root walk-up logic is silently dead.
  { src: 'hooks/_find-sdlc-root.sh', dest: '.claude/hooks/_find-sdlc-root.sh', base: REPO_ROOT },
  { src: 'skills/sdlc/SKILL.md', dest: '.claude/skills/sdlc/SKILL.md', base: REPO_ROOT },
  { src: 'skills/setup/SKILL.md', dest: '.claude/skills/setup/SKILL.md', base: REPO_ROOT },
  { src: 'skills/update/SKILL.md', dest: '.claude/skills/update/SKILL.md', base: REPO_ROOT },
  { src: 'skills/feedback/SKILL.md', dest: '.claude/skills/feedback/SKILL.md', base: REPO_ROOT },
  { src: 'skills/conduct/SKILL.md', dest: '.claude/skills/conduct/SKILL.md', base: REPO_ROOT },
  { src: 'skills/conduct/references/protocol.md', dest: '.claude/skills/conduct/references/protocol.md', base: REPO_ROOT },
  { src: 'skills/conduct/scripts/conduct.cjs', dest: '.claude/skills/conduct/scripts/conduct.cjs', base: REPO_ROOT },
  { src: 'skills/conduct/scripts/claude-desktop.sh', dest: '.claude/skills/conduct/scripts/claude-desktop.sh', base: REPO_ROOT, executable: true },
  { src: 'skills/conduct/scripts/claude-desktop.py', dest: '.claude/skills/conduct/scripts/claude-desktop.py', base: REPO_ROOT },
];

const WIZARD_HOOK_MARKERS = FILES
  .filter((f) => f.executable && f.dest.startsWith('.claude/hooks/'))
  .map((f) => path.basename(f.src));

const GITIGNORE_ENTRIES = ['.claude/plans/', '.claude/settings.local.json'];

// Paths where the Claude plugin form of this wizard installs.
// If present, running `npx init` creates duplicate /claude-update-wizard (#181).
const PLUGIN_INSTALL_PATHS = [
  '.claude/plugins-local/sdlc-wizard-wrap',
  '.claude/plugins/cache/sdlc-wizard-local',
];

function detectPluginInstall(homeDir) {
  const home = homeDir || os.homedir();
  // Guard empty / non-absolute HOME: without this, path.join('', '.claude/...')
  // produces a project-relative path and init falsely blocks on local dirs.
  if (!home || !path.isAbsolute(home)) return [];
  return PLUGIN_INSTALL_PATHS
    .map((rel) => path.join(home, rel))
    .filter((p) => fs.existsSync(p));
}

// Paths from previous versions that should be removed on upgrade
const OBSOLETE_PATHS = [
  '.claude/skills/testing',  // consolidated into /sdlc in v1.17.0
];

function isWizardHookEntry(hookEntry) {
  if (!hookEntry || !hookEntry.hooks) return false;
  return hookEntry.hooks.some((h) =>
    WIZARD_HOOK_MARKERS.some((marker) => h.command && h.command.includes(marker))
  );
}

function mergeSettings(existingPath, templatePath, force) {
  try {
    const existing = JSON.parse(fs.readFileSync(existingPath, 'utf8'));
    const template = JSON.parse(fs.readFileSync(templatePath, 'utf8'));

    // Merge top-level model field (only set if missing, unless --force).
    // Respects user's explicit model choice; adds the wizard default on fresh
    // installs and for users upgrading from a pre-model template.
    if (template.model && (!('model' in existing) || force)) {
      existing.model = template.model;
    }

    if (template.advisorModel && (!('advisorModel' in existing) || force)) {
      existing.advisorModel = template.advisorModel;
    }

    // Merge cleanupPeriodDays (ROADMAP #225): only set the template default when
    // the user has not chosen a value. NEVER overwrite under --force — retention
    // policy is a user preference (they may want >30 for long pauses, or <30 for
    // disk-tight setups). The wizard's job is to provide a safe floor on fresh
    // installs, not to clobber an explicit choice.
    if ('cleanupPeriodDays' in template && !('cleanupPeriodDays' in existing)) {
      existing.cleanupPeriodDays = template.cleanupPeriodDays;
    }

    // Merge env field
    if (template.env) {
      if (!existing.env || typeof existing.env !== 'object' || Array.isArray(existing.env)) {
        existing.env = {};
      }
      for (const [key, val] of Object.entries(template.env)) {
        if (!(key in existing.env) || force) {
          existing.env[key] = val;
        }
      }
    }

    if (!existing.hooks) existing.hooks = {};

    for (const [event, templateEntries] of Object.entries(template.hooks || {})) {
      if (!existing.hooks[event]) {
        existing.hooks[event] = templateEntries;
        continue;
      }

      // Each template event has exactly one hook entry
      const templateEntry = templateEntries[0];
      const existingIdx = existing.hooks[event].findIndex(isWizardHookEntry);

      if (existingIdx === -1) {
        existing.hooks[event].push(templateEntry);
      } else if (force) {
        existing.hooks[event][existingIdx] = templateEntry;
      }
    }

    const merged = JSON.stringify(existing, null, 2) + '\n';
    const original = fs.readFileSync(existingPath, 'utf8');
    return merged === original ? null : merged;
  } catch (_) {
    return null;
  }
}

function planOperations(targetDir, { force, preserveCustomized = false }) {
  const ops = [];

  // #323 option 2: preserve mode requires hashing each existing file to
  // distinguish CUSTOMIZED from MATCH. Only meaningful with --force; without
  // --force, existing files are SKIP regardless of hash.
  const isCustomized = (srcPath, destPath) => {
    if (!preserveCustomized || !force) return false;
    try {
      const srcHash = crypto.createHash('sha256').update(fs.readFileSync(srcPath)).digest('hex');
      const destHash = crypto.createHash('sha256').update(fs.readFileSync(destPath)).digest('hex');
      return srcHash !== destHash;
    } catch (_) {
      return false;
    }
  };

  for (const file of FILES) {
    const destPath = path.join(targetDir, file.dest);
    const srcPath = path.join(file.base || TEMPLATES_DIR, file.src);
    const exists = fs.existsSync(destPath);

    if (exists && file.dest === '.claude/settings.json') {
      const merged = mergeSettings(destPath, srcPath, force);
      if (merged) {
        ops.push({
          src: srcPath,
          dest: destPath,
          relativeDest: file.dest,
          action: 'MERGE',
          mergedContent: merged,
          executable: false,
        });
        continue;
      }
      // Invalid JSON — fall through to normal SKIP/OVERWRITE
    }

    let action;
    if (!exists) action = 'CREATE';
    else if (isCustomized(srcPath, destPath)) action = 'PRESERVE';
    else action = force ? 'OVERWRITE' : 'SKIP';

    ops.push({
      src: srcPath,
      dest: destPath,
      relativeDest: file.dest,
      action,
      executable: file.executable || false,
    });
  }

  // Wizard doc
  const wizardDest = path.join(targetDir, 'CLAUDE_CODE_SDLC_WIZARD.md');
  const wizardExists = fs.existsSync(wizardDest);
  let wizardAction;
  if (!wizardExists) wizardAction = 'CREATE';
  else if (isCustomized(WIZARD_DOC, wizardDest)) wizardAction = 'PRESERVE';
  else wizardAction = force ? 'OVERWRITE' : 'SKIP';
  ops.push({
    src: WIZARD_DOC,
    dest: wizardDest,
    relativeDest: 'CLAUDE_CODE_SDLC_WIZARD.md',
    action: wizardAction,
    executable: false,
  });

  return ops;
}

function ensureDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function executeOperations(ops) {
  for (const op of ops) {
    if (op.action === 'SKIP' || op.action === 'PRESERVE') continue;
    ensureDir(op.dest);
    if (op.action === 'MERGE') {
      fs.writeFileSync(op.dest, op.mergedContent);
    } else {
      fs.copyFileSync(op.src, op.dest);
    }
    if (op.executable) {
      fs.chmodSync(op.dest, 0o755);
    }
  }
}

function removeObsoletePaths(targetDir, { dryRun }) {
  const removed = [];
  for (const rel of OBSOLETE_PATHS) {
    const fullPath = path.join(targetDir, rel);
    if (fs.existsSync(fullPath)) {
      if (!dryRun) {
        fs.rmSync(fullPath, { recursive: true, force: true });
      }
      removed.push(rel);
    }
  }
  return removed;
}

function updateGitignore(targetDir, { dryRun }) {
  const gitignorePath = path.join(targetDir, '.gitignore');
  let content = '';
  if (fs.existsSync(gitignorePath)) {
    content = fs.readFileSync(gitignorePath, 'utf8');
  }

  const lines = content.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const toAdd = GITIGNORE_ENTRIES.filter((entry) => !lines.includes(entry));
  if (toAdd.length === 0) return [];

  if (!dryRun) {
    const suffix = (content && !content.endsWith('\n') ? '\n' : '') + toAdd.join('\n') + '\n';
    fs.appendFileSync(gitignorePath, suffix);
  }

  return toAdd;
}

function printOps(ops) {
  let preserveCount = 0;
  for (const op of ops) {
    const color = op.action === 'CREATE' ? GREEN
      : op.action === 'SKIP' ? YELLOW
      : op.action === 'MERGE' ? MAGENTA
      : op.action === 'PRESERVE' ? YELLOW
      : CYAN;
    console.log(`  ${color}${op.action}${RESET}  ${op.relativeDest}`);
    if (op.action === 'PRESERVE') preserveCount++;
  }
  if (preserveCount > 0) {
    console.log(`\n  ${YELLOW}PRESERVED ${preserveCount} customized file(s)${RESET} — review with \`init --dry-run\` to see what differs from the latest template.`);
  }
}

// #254 Bug 2: clear the version cache on `init --force` so the
// instructions-loaded hook re-fetches latest from npm post-upgrade. Without
// this, the cache holds the pre-upgrade "latest" for up to 24h and the hook
// prints reverse nudges like "1.42.1 → 1.41.1".
function invalidateVersionCache({ dryRun }) {
  const cacheDir = process.env.SDLC_WIZARD_CACHE_DIR
    || path.join(os.homedir(), '.cache', 'sdlc-wizard');
  const cacheFile = path.join(cacheDir, 'latest-version');
  if (!fs.existsSync(cacheFile)) return false;
  if (!dryRun) {
    try { fs.rmSync(cacheFile, { force: true }); } catch (_) { /* best-effort */ }
  }
  return true;
}

// #358: Nudge the user if their CLI is behind npm latest. Stale-npx-cache
// is the quiet onboarding bug — `npx agentic-sdlc-wizard init` (no @latest
// pin) serves whatever version is cached on disk, sometimes months old.
// Reuses the SDLC_WIZARD_CACHE_DIR/latest-version cache that the
// instructions-loaded hook already populates (#64/#196), so up-to-date users
// pay zero extra latency.
function maybeEmitStaleCliNudge() {
  const semverRe = /^(\d+)\.(\d+)\.(\d+)$/;
  const cmp = (a, b) => {
    const am = a.match(semverRe);
    const bm = b.match(semverRe);
    if (!am || !bm) return 0;
    for (let i = 1; i <= 3; i++) {
      const ai = parseInt(am[i], 10);
      const bi = parseInt(bm[i], 10);
      if (ai < bi) return -1;
      if (ai > bi) return 1;
    }
    return 0;
  };

  let current;
  try {
    current = require('../package.json').version;
  } catch (_) {
    return;
  }
  if (!semverRe.test(current)) return;

  const cacheDir = process.env.SDLC_WIZARD_CACHE_DIR
    || path.join(os.homedir(), '.cache', 'sdlc-wizard');
  const cacheFile = path.join(cacheDir, 'latest-version');
  let latest = null;

  // Try cache first (24h TTL, valid semver, #239 sanity check: cached
  // "latest" must be >= installed — older value means poisoned, refetch).
  if (fs.existsSync(cacheFile)) {
    try {
      const stat = fs.statSync(cacheFile);
      const ageMs = Date.now() - stat.mtimeMs;
      if (ageMs < 86400 * 1000) {
        const content = fs.readFileSync(cacheFile, 'utf8').trim();
        if (semverRe.test(content) && cmp(content, current) >= 0) {
          latest = content;
        }
      }
    } catch (_) { /* unreadable — fall through to npm fetch */ }
  }

  // Cache miss / stale / poisoned → npm fetch (5s timeout, write on success)
  if (latest === null) {
    try {
      const { execSync } = require('child_process');
      const fetched = execSync('npm view agentic-sdlc-wizard version 2>/dev/null', {
        encoding: 'utf8',
        timeout: 5000,
      }).trim();
      if (semverRe.test(fetched)) {
        latest = fetched;
        try {
          fs.mkdirSync(cacheDir, { recursive: true });
          fs.writeFileSync(cacheFile, latest);
        } catch (_) { /* best-effort cache write */ }
      }
    } catch (_) { /* offline or npm unavailable — silent */ }
  }

  if (latest && cmp(current, latest) < 0) {
    console.log(`\n  ${YELLOW}STALE${RESET}   agentic-sdlc-wizard CLI ${current} in use; npm latest is ${latest}.`);
    console.log(`         Recommended: rerun with ${CYAN}npx -y agentic-sdlc-wizard@latest init${RESET} to install the newest hooks/skills.`);
  }
}

function init(targetDir, { force = false, dryRun = false, preserveCustomized = false } = {}) {
  if (!dryRun && !force) {
    const pluginPaths = detectPluginInstall();
    if (pluginPaths.length > 0) {
      console.error(`\n${YELLOW}Claude plugin install detected:${RESET}`);
      for (const p of pluginPaths) console.error(`  ${p}`);
      console.error('\nInstalling via npm on top of the plugin creates duplicate /claude-update-wizard commands.');
      console.error('Pick one channel:');
      console.error(`  - Keep plugin:   exit and use ${CYAN}/plugin update sdlc-wizard${RESET}`);
      console.error(`  - Switch to CLI: remove plugin dir above, then rerun ${CYAN}init${RESET}`);
      console.error(`  - Keep both:     rerun with ${CYAN}--force${RESET} (duplicates expected)\n`);
      const err = new Error(
        `Plugin install detected at: ${pluginPaths.join(', ')}. Use --force to bypass.`
      );
      err.pluginPaths = pluginPaths;
      throw err;
    }
  }

  maybeEmitStaleCliNudge();

  const ops = planOperations(targetDir, { force, preserveCustomized });

  if (dryRun) {
    console.log('Dry run — no files will be written:\n');
    printOps(ops);
    const obsolete = removeObsoletePaths(targetDir, { dryRun: true });
    for (const p of obsolete) {
      console.log(`  ${RED}REMOVE${RESET}  ${p} (obsolete)`);
    }
    const gitignoreAdds = updateGitignore(targetDir, { dryRun: true });
    if (gitignoreAdds.length > 0) {
      console.log(`  ${GREEN}APPEND${RESET}  .gitignore (${gitignoreAdds.join(', ')})`);
    }
    return true;
  }

  console.log('');
  printOps(ops);

  // Always clean up obsolete paths, even when all managed files are SKIP
  const obsolete = removeObsoletePaths(targetDir, { dryRun: false });
  for (const p of obsolete) {
    console.log(`  ${RED}REMOVE${RESET}  ${p} (obsolete)`);
  }

  if (ops.every((o) => o.action === 'SKIP') && obsolete.length === 0) {
    console.log('\nAll files already exist. Use --force to overwrite.');
    return true;
  }

  executeOperations(ops);

  const gitignoreAdds = updateGitignore(targetDir, { dryRun: false });
  if (gitignoreAdds.length > 0) {
    console.log(`  ${GREEN}APPEND${RESET}  .gitignore (${gitignoreAdds.join(', ')})`);
  }

  // #254 Bug 2: bust the latest-version cache after an upgrade so the
  // staleness nudge re-fetches a fresh value from npm. Only on --force,
  // since that's the upgrade path.
  if (force && invalidateVersionCache({ dryRun: false })) {
    console.log(`  ${CYAN}BUST${RESET}    version cache (${path.join(process.env.SDLC_WIZARD_CACHE_DIR || path.join(os.homedir(), '.cache', 'sdlc-wizard'), 'latest-version')})`);
  }

  console.log(`
${GREEN}SDLC Harness installed successfully!${RESET}

${YELLOW}Restart Claude Code${RESET} to load new hooks and skills:
  ${CYAN}/exit${RESET} then ${CYAN}claude --continue${RESET}  (keeps conversation history)
  ${CYAN}/exit${RESET} then ${CYAN}claude${RESET}              (fresh start)

Next steps:
  1. Restart Claude Code (see above)
  2. Tell Claude anything — setup auto-invokes when SDLC files are missing
  3. Claude reads the wizard doc and creates CLAUDE.md, SDLC.md, TESTING.md, ARCHITECTURE.md

The wizard doc is at: CLAUDE_CODE_SDLC_WIZARD.md
  `);

  return true;
}

function check(targetDir, { json = false } = {}) {
  const results = [];

  for (const file of FILES) {
    const destPath = path.join(targetDir, file.dest);
    const srcPath = path.join(file.base || TEMPLATES_DIR, file.src);
    results.push(checkFile(srcPath, destPath, file.dest, file.executable || false));
  }

  const wizardDest = path.join(targetDir, 'CLAUDE_CODE_SDLC_WIZARD.md');
  results.push(checkFile(WIZARD_DOC, wizardDest, 'CLAUDE_CODE_SDLC_WIZARD.md', false));

  const gitignorePath = path.join(targetDir, '.gitignore');
  results.push(checkGitignore(gitignorePath));

  let updateInfo = null;
  try {
    const { execSync } = require('child_process');
    const latest = execSync('npm view agentic-sdlc-wizard version 2>/dev/null', {
      encoding: 'utf8',
      timeout: 5000,
    }).trim();
    const current = require('../package.json').version;
    if (latest !== current) {
      updateInfo = { current, latest };
    }
  } catch (_) {
    // Offline or npm unavailable — skip update check
  }

  const marketplace = checkMarketplacePaths();
  const hasDrift = results.some((r) => r.status === 'MISSING' || r.status === 'DRIFT')
    || marketplace.some((m) => m.status === 'DANGLING');

  if (json) {
    console.log(JSON.stringify({ files: results, update: updateInfo, marketplace }, null, 2));
  } else {
    for (const r of results) {
      const color = r.status === 'MATCH' ? GREEN : r.status === 'MISSING' ? RED : YELLOW;
      console.log(`  ${color}${r.status}${RESET}  ${r.file}`);
      if (r.details) console.log(`         ${r.details}`);
    }
    for (const m of marketplace) {
      const color = m.status === 'DANGLING' ? RED : YELLOW;
      const heading = m.status === 'EPHEMERAL'
        ? `Marketplace '${m.name}' source path is ephemeral:`
        : `Marketplace '${m.name}' source path does not exist:`;
      console.log(`\n  ${color}${m.status}${RESET}  ${heading}`);
      console.log(`         ${m.path}`);
      console.log(`         ${m.details}`);
      // #266: DANGLING + enabledPlugins=true = every UserPromptSubmit hook
      // crashes. Surface the actionable fix loud and clear.
      if (m.crashRisk && m.enabledPluginKey) {
        console.log(`         ${RED}CRASH RISK${RESET}: enabledPlugins["${m.enabledPluginKey}"] is true but the path is missing — every UserPromptSubmit hook will fail until this is resolved (#266)`);
        console.log(`         Fix: edit ~/.claude/settings.json and set enabledPlugins["${m.enabledPluginKey}"] to false, OR run /plugin uninstall to clean up properly`);
      }
      if (m.suggestion) {
        console.log(`         Recommended: move to ${m.suggestion}`);
      }
    }
    if (updateInfo) {
      const customizedCount = results.filter((r) => r.status === 'CUSTOMIZED').length;
      for (const line of buildUpdateRecommendation(updateInfo, customizedCount)) {
        console.log(line);
      }
    }
  }

  return { results, updateInfo, hasDrift, marketplace };
}

// #323: when `check` finds CUSTOMIZED files alongside an available update,
// the historical recommendation `init --force` would silently clobber them.
// This builds an update-recommendation block that's customization-aware:
// no-CUSTOMIZED → recommend --force as before. Has-CUSTOMIZED → warn and
// recommend `--dry-run` first so the user can preview the diff.
function buildUpdateRecommendation(updateInfo, customizedCount) {
  if (!updateInfo) return [];
  const lines = [
    `\n  ${YELLOW}UPDATE${RESET}  v${updateInfo.current} -> v${updateInfo.latest}`,
  ];
  if (customizedCount > 0) {
    lines.push(`         ${YELLOW}WARNING${RESET}: ${customizedCount} file(s) CUSTOMIZED — \`init --force\` will overwrite them`);
    lines.push(`         Preview first:  npx agentic-sdlc-wizard init --dry-run`);
    lines.push(`         Or upgrade safely: npx agentic-sdlc-wizard init --force --preserve-customized`);
    lines.push(`         (\`--preserve-customized\` skips CUSTOMIZED files and updates only MATCH ones.)`);
  } else {
    lines.push('         Run: npx agentic-sdlc-wizard init --force');
  }
  return lines;
}

function settingsHooksMatch(srcPath, destPath) {
  try {
    const src = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
    const dest = JSON.parse(fs.readFileSync(destPath, 'utf8'));
    for (const [event, entries] of Object.entries(src.hooks || {})) {
      if (!dest.hooks || !dest.hooks[event]) return false;
      const templateEntry = entries[0];
      if (!templateEntry || !templateEntry.hooks) continue;
      for (const th of templateEntry.hooks) {
        if (!th.command) continue;
        const marker = WIZARD_HOOK_MARKERS.find((m) => th.command.includes(m));
        if (!marker) continue;
        // Verify marker present AND type matches. We intentionally skip matcher/if
        // comparison — those are customizable per-project (the wizard's own settings
        // use different if guards than the consumer template).
        const found = dest.hooks[event].some(
          (de) => de.hooks && de.hooks.some(
            (h) => h.command && h.command.includes(marker) && h.type === (th.type || 'command')
          )
        );
        if (!found) return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

function checkFile(srcPath, destPath, relativeDest, shouldBeExecutable) {
  if (!fs.existsSync(destPath)) {
    return { file: relativeDest, status: 'MISSING' };
  }
  const srcHash = crypto.createHash('sha256').update(fs.readFileSync(srcPath)).digest('hex');
  const destHash = crypto.createHash('sha256').update(fs.readFileSync(destPath)).digest('hex');
  let fileStatus;
  if (srcHash === destHash) {
    fileStatus = 'MATCH';
  } else if (relativeDest === '.claude/settings.json' && settingsHooksMatch(srcPath, destPath)) {
    fileStatus = 'MATCH';
  } else {
    fileStatus = 'CUSTOMIZED';
  }
  const result = { file: relativeDest, status: fileStatus };

  if (shouldBeExecutable) {
    try {
      fs.accessSync(destPath, fs.constants.X_OK);
    } catch (_) {
      result.status = 'DRIFT';
      result.details = 'Missing executable permission (chmod +x)';
    }
  }

  return result;
}

function checkGitignore(gitignorePath) {
  if (!fs.existsSync(gitignorePath)) {
    return { file: '.gitignore', status: 'MISSING', details: 'No .gitignore found' };
  }
  const lines = fs.readFileSync(gitignorePath, 'utf8').split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
  const missing = GITIGNORE_ENTRIES.filter((e) => !lines.includes(e));
  if (missing.length > 0) {
    return { file: '.gitignore', status: 'DRIFT', details: `Missing entries: ${missing.join(', ')}` };
  }
  return { file: '.gitignore', status: 'MATCH' };
}

const EPHEMERAL_ROOTS = /^(\/tmp\/|\/private\/tmp\/|\/var\/folders\/|\/private\/var\/folders\/)/;

function checkMarketplacePaths() {
  const results = [];
  const globalSettings = path.join(os.homedir(), '.claude', 'settings.json');

  if (!fs.existsSync(globalSettings)) return results;

  let data;
  try {
    data = JSON.parse(fs.readFileSync(globalSettings, 'utf8'));
  } catch (_) {
    return results;
  }

  const marketplaces = data.extraKnownMarketplaces;
  if (!marketplaces || typeof marketplaces !== 'object') return results;

  // #266: cross-reference enabledPlugins to detect the actual crash state.
  // A DANGLING marketplace path is harmless if no plugins from it are enabled,
  // but DANGLING + enabled = every UserPromptSubmit hook crashes (CC's plugin
  // loader fails to resolve the path and propagates the error).
  // Plugin keys in enabledPlugins are formatted "<plugin>@<marketplace>".
  const enabledPlugins = (data.enabledPlugins && typeof data.enabledPlugins === 'object')
    ? data.enabledPlugins
    : {};
  function findEnabledPluginForMarketplace(marketplaceName) {
    for (const [pluginKey, isEnabled] of Object.entries(enabledPlugins)) {
      if (isEnabled !== true) continue;
      // pluginKey shape: "sdlc-wizard@sdlc-wizard-local". The part after the
      // last `@` is the marketplace name. Use lastIndexOf so plugin names
      // containing `@` (npm scoped packages) parse correctly.
      const atIdx = pluginKey.lastIndexOf('@');
      if (atIdx <= 0) continue;
      const mp = pluginKey.slice(atIdx + 1);
      if (mp === marketplaceName) return pluginKey;
    }
    return null;
  }

  for (const [name, entry] of Object.entries(marketplaces)) {
    const source = entry && entry.source;
    if (!source || source.source !== 'directory' || !source.path || typeof source.path !== 'string') continue;

    const sourcePath = source.path;
    const isEphemeral = EPHEMERAL_ROOTS.test(sourcePath);
    const exists = fs.existsSync(sourcePath);
    const basename = path.basename(sourcePath);
    const suggestion = `~/.claude/plugins-local/${basename}`;

    if (!exists) {
      const enabledPluginKey = findEnabledPluginForMarketplace(name);
      const isCrashRisk = enabledPluginKey !== null;
      results.push({
        name,
        path: sourcePath,
        status: 'DANGLING',
        crashRisk: isCrashRisk,
        enabledPluginKey,
        details: isEphemeral
          ? 'Ephemeral path has been reaped — plugin is broken'
          : 'Path does not exist — plugin may be silently broken',
        suggestion: isEphemeral ? suggestion : undefined,
      });
    } else if (isEphemeral) {
      results.push({
        name,
        path: sourcePath,
        status: 'EPHEMERAL',
        details: 'macOS reaps this path periodically — plugin may break silently',
        suggestion,
      });
    }
  }

  return results;
}

module.exports = { init, check, planOperations, detectPluginInstall, buildUpdateRecommendation, GITIGNORE_ENTRIES };
