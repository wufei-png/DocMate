#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <docmate.catalog.json>" >&2
  exit 1
fi

CATALOG_PATH="$1"

if [ ! -f "$CATALOG_PATH" ]; then
  echo "Error: catalog file not found: $CATALOG_PATH" >&2
  exit 1
fi

find_node() {
  if command -v node >/dev/null 2>&1; then
    command -v node
    return
  fi

  local candidate
  candidate="$(find "$HOME/.nvm/versions/node" -path '*/bin/node' -type f 2>/dev/null | sort -V | tail -n 1 || true)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return
  fi

  echo "Error: node is required but was not found on PATH or under ~/.nvm/versions/node" >&2
  exit 1
}

NODE_BIN="$(find_node)"

"$NODE_BIN" - "$CATALOG_PATH" <<'EOF'
const fs = require("node:fs");

const catalogPath = process.argv[2];

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireKeys(object, keys, path) {
  const actual = Object.keys(object).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    fail(`${path} must contain exactly these keys: ${expected.join(", ")}`);
  }
}

function requireString(value, path, { allowEmpty = false } = {}) {
  if (typeof value !== "string") {
    fail(`${path} must be a string`);
  }
  if (!allowEmpty && value.trim() === "") {
    fail(`${path} must be a non-empty string`);
  }
}

function requireStringArray(value, path, { allowEmpty = true } = {}) {
  if (!Array.isArray(value)) {
    fail(`${path} must be an array`);
  }
  if (!allowEmpty && value.length === 0) {
    fail(`${path} must contain at least one value`);
  }

  const seen = new Set();
  value.forEach((entry, index) => {
    requireString(entry, `${path}[${index}]`);
    if (seen.has(entry)) {
      const duplicateKind = path.endsWith(".aliases") ? "alias" : "entry";
      fail(`${path} contains a duplicate ${duplicateKind}: ${entry}`);
    }
    seen.add(entry);
  });
}

let data;
try {
  data = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
} catch (error) {
  fail(`invalid JSON in ${catalogPath}: ${error.message}`);
}

if (!isObject(data)) {
  fail("root must be a JSON object");
}

requireKeys(data, ["schemaVersion", "installHosts", "defaults", "repos"], "root");

if (data.schemaVersion !== 2) {
  fail("schemaVersion must be 2");
}

const supportedHosts = new Set(["openclaw", "claude-code", "opencode", "codex", "hermes"]);
requireStringArray(data.installHosts, "installHosts", { allowEmpty: false });
for (const [index, host] of data.installHosts.entries()) {
  if (!supportedHosts.has(host)) {
    fail(`installHosts[${index}] has an unsupported host: ${host}`);
  }
}

if (!isObject(data.defaults)) {
  fail("defaults must be an object");
}
requireKeys(data.defaults, ["update"], "defaults");
if (!isObject(data.defaults.update)) {
  fail("defaults.update must be an object");
}

const supportedModes = new Set(["ask", "auto", "off"]);
function validateUpdate(update, path) {
  if (!isObject(update)) {
    fail(`${path} must be an object`);
  }
  const allowedKeys = new Set(["mode"]);
  for (const key of Object.keys(update)) {
    if (!allowedKeys.has(key)) {
      fail(`${path}.${key} is not supported`);
    }
  }
  if (update.mode !== undefined) {
    requireString(update.mode, `${path}.mode`);
    if (!supportedModes.has(update.mode)) {
      fail("update.mode must be ask, auto, or off");
    }
  }
}

validateUpdate(data.defaults.update, "defaults.update");

if (!Array.isArray(data.repos) || data.repos.length === 0) {
  fail("repos must be a non-empty array");
}

const seenRepoNames = new Set();
const seenRepoPaths = new Set();
const seenRepoAliases = new Map();
for (const [repoIndex, repo] of data.repos.entries()) {
  if (!isObject(repo)) {
    fail(`repos[${repoIndex}] must be an object`);
  }
  requireKeys(
    repo,
    ["name", "description", "path", "aliases", "baseBranchCandidates", "update"],
    `repos[${repoIndex}]`
  );

  requireString(repo.name, `repos[${repoIndex}].name`);
  if (seenRepoNames.has(repo.name)) {
    fail(`repos contains a duplicate repository name: ${repo.name}`);
  }
  seenRepoNames.add(repo.name);

  requireString(repo.description, `repos[${repoIndex}].description`, { allowEmpty: true });
  requireString(repo.path, `repos[${repoIndex}].path`);
  if (!repo.path.startsWith("/")) {
    fail(`repos[${repoIndex}].path must be an absolute path`);
  }
  if (seenRepoPaths.has(repo.path)) {
    fail(`repos contains a duplicate repository path: ${repo.path}`);
  }
  seenRepoPaths.add(repo.path);

  requireStringArray(repo.aliases, `repos[${repoIndex}].aliases`);
  const seenAliases = new Set();
  for (const alias of repo.aliases) {
    if (seenAliases.has(alias)) {
      fail(`repos[${repoIndex}] contains a duplicate alias: ${alias}`);
    }
    if (seenRepoAliases.has(alias)) {
      const firstRepoName = seenRepoAliases.get(alias);
      fail(`repos[${repoIndex}].aliases contains alias already used by repository ${firstRepoName}: ${alias}`);
    }
    seenAliases.add(alias);
    seenRepoAliases.set(alias, repo.name);
  }

  requireStringArray(repo.baseBranchCandidates, `repos[${repoIndex}].baseBranchCandidates`);
  validateUpdate(repo.update, `repos[${repoIndex}].update`);

  const effectiveMode = repo.update.mode || data.defaults.update.mode || "ask";
  if (effectiveMode !== "off") {
    if (repo.baseBranchCandidates.length === 0) {
      fail("baseBranchCandidates must contain at least one branch when updates are enabled");
    }
  }
}

process.stdout.write("OK\n");
EOF
