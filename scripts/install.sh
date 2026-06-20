#!/usr/bin/env bash
set -euo pipefail

SKILL_SLUG="docmate"
SCHEMA_VERSION=2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P || pwd -P)"
CANONICAL_DIR="$HOME/.agents/skills/$SKILL_SLUG"

DOCMATE_REPO="${DOCMATE_REPO:-wufei-png/DocMate}"
DOCMATE_BRANCH="${DOCMATE_BRANCH:-main}"
REMOTE_RAW_BASE_URL="https://raw.githubusercontent.com/${DOCMATE_REPO}/${DOCMATE_BRANCH}"
DOCMATE_USE_LOCAL_CACHE="${DOCMATE_USE_LOCAL_CACHE:-auto}"
SCAN_MAX_DEPTH="${DOCMATE_SCAN_MAX_DEPTH:-5}"

YES=0
HOSTS_RAW="all"
EXISTING="backup"
UPDATE_MODE="ask"
AUTO_SCAN=0
SCAN_ROOT=""
REPO_ARGS=()
REPOS=()
TMP_FILES=()
TTY_FD=9
TTY_AVAILABLE=0
if { exec 9<>/dev/tty; } 2>/dev/null; then
  TTY_AVAILABLE=1
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  install.sh [--yes] --repo PATH [--repo PATH ...] [--hosts all|openclaw,claude-code,opencode,codex,hermes] [--existing backup|skip|overwrite] [--update-mode ask|auto|off]
  install.sh [--yes] --auto-scan --scan-root PATH [--hosts all|openclaw,claude-code,opencode,codex,hermes] [--existing backup|skip|overwrite] [--update-mode ask|auto|off]
  install.sh

Pipe install:
  curl -fsSL https://raw.githubusercontent.com/wufei-png/DocMate/main/scripts/install.sh | bash

Backward compatibility: --project PATH is accepted as an alias for --repo PATH.
EOF
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    --repo|--project) REPO_ARGS+=("${2:-}"); shift 2 ;;
    --auto-scan) AUTO_SCAN=1; shift ;;
    --scan-root) SCAN_ROOT="${2:-}"; shift 2 ;;
    --hosts) HOSTS_RAW="${2:-}"; shift 2 ;;
    --existing) EXISTING="${2:-}"; shift 2 ;;
    --update-mode) UPDATE_MODE="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$EXISTING" in backup|skip|overwrite) ;; *) usage ;; esac
case "$UPDATE_MODE" in ask|auto|off) ;; *) usage ;; esac

HOSTS=()
if [ "$HOSTS_RAW" = "all" ]; then
  HOSTS=(openclaw claude-code opencode codex hermes)
else
  IFS=',' read -r -a HOSTS <<< "$HOSTS_RAW"
fi

cleanup() {
  local tmp_file
  for tmp_file in "${TMP_FILES[@]}"; do
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
  done
}
trap cleanup EXIT

can_prompt() {
  [ "$TTY_AVAILABLE" -eq 1 ] || [ -t 0 ]
}

should_use_local_file() {
  local rel_path="$1"
  case "$DOCMATE_USE_LOCAL_CACHE" in
    0|false|FALSE|False|no|NO|off|OFF) return 1 ;;
    auto|1|true|TRUE|True|yes|YES|on|ON)
      [ -f "$ROOT_DIR/$rel_path" ]
      return
      ;;
    *) [ -f "$ROOT_DIR/$rel_path" ] ;;
  esac
}

download_remote_file() {
  local remote_path="$1"
  local dest_path="$2"
  local remote_url="${REMOTE_RAW_BASE_URL}/${remote_path}"

  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required for remote install but was not found" >&2
    return 1
  fi

  mkdir -p "$(dirname "$dest_path")"
  if curl -fsSL "$remote_url" -o "$dest_path"; then
    return 0
  fi

  echo "Error: failed to download $remote_url" >&2
  return 1
}

materialize_file() {
  local rel_path="$1"
  local dest_path="$2"

  mkdir -p "$(dirname "$dest_path")"
  if should_use_local_file "$rel_path"; then
    cp "$ROOT_DIR/$rel_path" "$dest_path"
    return
  fi

  download_remote_file "$rel_path" "$dest_path"
}

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

run_catalog_validator() {
  local catalog_path="$1"
  local tmp_validate

  if should_use_local_file "scripts/validate_catalog.sh"; then
    bash "$ROOT_DIR/scripts/validate_catalog.sh" "$catalog_path" >/dev/null
    return
  fi

  tmp_validate="$(mktemp)"
  TMP_FILES+=("$tmp_validate")
  download_remote_file "scripts/validate_catalog.sh" "$tmp_validate"
  bash "$tmp_validate" "$catalog_path" >/dev/null
}

host_dir() {
  case "$1" in
    openclaw) printf '%s\n' "$HOME/.openclaw/skills/$SKILL_SLUG" ;;
    claude-code) printf '%s\n' "$HOME/.claude/skills/$SKILL_SLUG" ;;
    opencode) printf '%s\n' "$HOME/.config/opencode/skills/$SKILL_SLUG" ;;
    codex) printf '%s\n' "$CANONICAL_DIR" ;;
    hermes) printf '%s\n' "$HOME/.hermes/skills/software-development/$SKILL_SLUG" ;;
    *) echo "Error: unsupported host: $1" >&2; exit 1 ;;
  esac
}

backup_path() {
  local target="$1"
  local index=0
  while [ -e "${target}_backup_${index}" ] || [ -L "${target}_backup_${index}" ]; do
    index=$((index + 1))
  done
  printf '%s\n' "${target}_backup_${index}"
}

prepare_target() {
  local target="$1"
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$(dirname "$target")"
    return
  fi

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$CANONICAL_DIR" ]; then
    rm -f "$target"
    mkdir -p "$(dirname "$target")"
    return
  fi

  case "$EXISTING" in
    skip)
      echo "Skipping existing target: $target"
      return 1
      ;;
    overwrite)
      rm -rf "$target"
      ;;
    backup)
      local backup
      backup="$(backup_path "$target")"
      mv "$target" "$backup"
      echo "Backed up $target to $backup"
      ;;
  esac
  mkdir -p "$(dirname "$target")"
}

prepare_canonical_target() {
  if [ ! -e "$CANONICAL_DIR" ] && [ ! -L "$CANONICAL_DIR" ]; then
    mkdir -p "$CANONICAL_DIR"
    return
  fi

  case "$EXISTING" in
    skip)
      echo "Skipping existing canonical target: $CANONICAL_DIR"
      return 1
      ;;
    overwrite)
      rm -rf "$CANONICAL_DIR"
      ;;
    backup)
      local backup
      backup="$(backup_path "$CANONICAL_DIR")"
      mv "$CANONICAL_DIR" "$backup"
      echo "Backed up $CANONICAL_DIR to $backup"
      ;;
  esac
  mkdir -p "$CANONICAL_DIR"
}

read_user_line() {
  local prompt="$1"

  if [ "$TTY_AVAILABLE" -eq 1 ]; then
    printf "%s" "$prompt" >&$TTY_FD
    IFS= read -r REPLY <&$TTY_FD || REPLY=""
    return
  fi

  if [ -t 0 ]; then
    printf "%s" "$prompt"
    IFS= read -r REPLY || REPLY=""
    return
  fi

  echo "Error: interactive input is unavailable. Re-run with --repo PATH or --auto-scan --scan-root PATH." >&2
  exit 1
}

confirm_yes_no() {
  local prompt="$1"
  local default_answer="${2:-no}"
  local answer=""
  local suffix="[y/N]"

  if [ "$default_answer" = "yes" ]; then
    suffix="[Y/n]"
  fi

  while true; do
    read_user_line "$prompt $suffix "
    answer="$REPLY"
    case "$answer" in
      "")
        [ "$default_answer" = "yes" ]
        return
        ;;
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

normalize_path() {
  local path="$1"
  (cd "$path" && pwd -P)
}

repo_path_exists() {
  local repo_path="$1"
  local existing_path

  for existing_path in "${REPOS[@]}"; do
    if [ "$existing_path" = "$repo_path" ]; then
      return 0
    fi
  done

  return 1
}

add_repo_path() {
  local repo_path="$1"
  repo_path="$(normalize_path "$repo_path")"

  if repo_path_exists "$repo_path"; then
    echo "Warning: duplicate repository path filtered: $repo_path"
    return
  fi

  REPOS+=("$repo_path")
  echo "Added repository: $(basename "$repo_path") ($repo_path)"
}

git_top_level() {
  local path="$1"
  git -C "$path" rev-parse --show-toplevel 2>/dev/null || true
}

first_remote_name() {
  local repo_path="$1"
  local remote_name=""

  if git -C "$repo_path" remote get-url origin >/dev/null 2>&1; then
    printf '%s\n' "origin"
    return
  fi

  remote_name="$(git -C "$repo_path" remote 2>/dev/null | head -n 1 || true)"
  printf '%s\n' "$remote_name"
}

remote_host_from_url() {
  local remote_url="$1"
  local without_scheme=""
  local without_user=""
  local host_port=""

  case "$remote_url" in
    http://*|https://*)
      without_scheme="${remote_url#*://}"
      host_port="${without_scheme%%/*}"
      ;;
    ssh://*)
      without_scheme="${remote_url#ssh://}"
      without_user="${without_scheme#*@}"
      host_port="${without_user%%/*}"
      ;;
    *@*:*)
      without_user="${remote_url#*@}"
      host_port="${without_user%%:*}"
      ;;
    *)
      host_port=""
      ;;
  esac

  printf '%s\n' "${host_port%%:*}"
}

remote_path_from_url() {
  local remote_url="$1"
  local without_scheme=""
  local without_user=""
  local path_part=""

  case "$remote_url" in
    http://*|https://*)
      without_scheme="${remote_url#*://}"
      path_part="${without_scheme#*/}"
      ;;
    ssh://*)
      without_scheme="${remote_url#ssh://}"
      without_user="${without_scheme#*@}"
      path_part="${without_user#*/}"
      ;;
    *@*:*)
      path_part="${remote_url#*:}"
      ;;
    *)
      path_part=""
      ;;
  esac

  path_part="${path_part#/}"
  path_part="${path_part%.git}"
  printf '%s\n' "$path_part"
}

remote_kind_from_url() {
  local remote_url="$1"
  local host
  local lower_host

  host="$(remote_host_from_url "$remote_url")"
  lower_host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"

  case "$lower_host" in
    *github*) printf '%s\n' "github" ;;
    *gitlab*) printf '%s\n' "gitlab" ;;
    *) printf '%s\n' "git" ;;
  esac
}

normalize_branch_name() {
  local branch="$1"
  branch="$(printf '%s\n' "$branch" | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  branch="${branch#refs/heads/}"
  printf '%s\n' "$branch"
}

github_repo_arg_from_url() {
  local remote_url="$1"
  local host
  local repo_path

  host="$(remote_host_from_url "$remote_url")"
  repo_path="$(remote_path_from_url "$remote_url")"
  [ -n "$repo_path" ] || return 0

  case "$host" in
    github.com) printf '%s\n' "$repo_path" ;;
    "") printf '%s\n' "$repo_path" ;;
    *) printf '%s/%s\n' "$host" "$repo_path" ;;
  esac
}

default_branch_from_gh() {
  local repo_path="$1"
  local remote_url="$2"
  local repo_arg
  local branch=""

  command -v gh >/dev/null 2>&1 || return 0
  repo_arg="$(github_repo_arg_from_url "$remote_url")"

  if [ -n "$repo_arg" ]; then
    branch="$(GH_NO_UPDATE_NOTIFIER=1 gh repo view "$repo_arg" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  fi
  if [ -z "$branch" ]; then
    branch="$(cd "$repo_path" && GH_NO_UPDATE_NOTIFIER=1 gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || true)"
  fi

  normalize_branch_name "$branch"
}

default_branch_from_glab() {
  local repo_path="$1"
  local remote_url="$2"
  local branch=""

  command -v glab >/dev/null 2>&1 || return 0

  branch="$(GLAB_NO_UPDATE_NOTIFIER=1 glab repo view "$remote_url" -F json --jq '.default_branch // .defaultBranch // .defaultBranchRef.name // empty' 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    branch="$(cd "$repo_path" && GLAB_NO_UPDATE_NOTIFIER=1 glab repo view -F json --jq '.default_branch // .defaultBranch // .defaultBranchRef.name // empty' 2>/dev/null || true)"
  fi

  normalize_branch_name "$branch"
}

default_branch_from_git_remote() {
  local remote_url="$1"
  local branch=""

  [ -n "$remote_url" ] || return 0
  if [ -z "${GIT_SSH_COMMAND:-}" ]; then
    branch="$(GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" git ls-remote --symref "$remote_url" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' || true)"
  else
    branch="$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref "$remote_url" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' || true)"
  fi
  normalize_branch_name "$branch"
}

default_branch_from_local_head() {
  local repo_path="$1"
  local branch=""

  branch="$(git -C "$repo_path" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  normalize_branch_name "$branch"
}

detect_default_branch() {
  local repo_path="$1"
  local remote_name=""
  local remote_url=""
  local remote_kind=""
  local branch=""

  remote_name="$(first_remote_name "$repo_path")"
  if [ -n "$remote_name" ]; then
    remote_url="$(git -C "$repo_path" remote get-url "$remote_name" 2>/dev/null || true)"
    remote_kind="$(remote_kind_from_url "$remote_url")"

    case "$remote_kind" in
      github)
        branch="$(default_branch_from_gh "$repo_path" "$remote_url")"
        ;;
      gitlab)
        branch="$(default_branch_from_glab "$repo_path" "$remote_url")"
        ;;
    esac

    if [ -z "$branch" ]; then
      branch="$(default_branch_from_git_remote "$remote_url")"
    fi
  fi

  if [ -z "$branch" ]; then
    branch="$(default_branch_from_local_head "$repo_path")"
  fi

  if [ -z "$branch" ]; then
    branch="main"
    echo "Warning: could not detect default branch for $repo_path; using fallback: $branch" >&2
  else
    echo "Detected default branch for $(basename "$repo_path"): $branch" >&2
  fi

  printf '%s\n' "$branch"
}

find_repos_under() {
  local scan_root="$1"
  scan_root="$(normalize_path "$scan_root")"

  find "$scan_root" -maxdepth "$SCAN_MAX_DEPTH" \( -type d -name ".git" -o -type f -name ".git" \) -print 2>/dev/null \
    | while IFS= read -r git_marker; do
        dirname "$git_marker"
      done \
    | sort -u
}

print_repo_candidates() {
  local candidate
  for candidate in "$@"; do
    echo "  - $(basename "$candidate") ($candidate)"
  done
}

add_repo_candidates() {
  local candidate
  for candidate in "$@"; do
    add_repo_path "$candidate"
  done
}

process_repo_path() {
  local raw_path="$1"
  local normalized=""
  local top_level=""
  local candidate=""
  local candidates=()

  if [ -z "$raw_path" ]; then
    echo "Warning: empty repository path ignored"
    return
  fi

  if [ ! -d "$raw_path" ]; then
    echo "Warning: repository path does not exist or is not a directory: $raw_path"
    return
  fi

  normalized="$(normalize_path "$raw_path")"
  top_level="$(git_top_level "$normalized")"
  if [ -n "$top_level" ] && [ -d "$top_level" ]; then
    top_level="$(normalize_path "$top_level")"
    if [ "$top_level" != "$normalized" ]; then
      echo "Warning: $normalized is inside a git repository; using repository root $top_level"
    fi
    add_repo_path "$top_level"
    return
  fi

  echo "Warning: $normalized is not a git repository. Scanning beneath it for repositories."
  while IFS= read -r candidate; do
    [ -n "$candidate" ] && candidates+=("$candidate")
  done < <(find_repos_under "$normalized")

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo "Warning: no git repositories detected beneath $normalized"
    return
  fi

  echo "Detected repositories under $normalized:"
  print_repo_candidates "${candidates[@]}"
  if [ "$YES" -eq 1 ] || confirm_yes_no "Add all detected repositories?" "yes"; then
    add_repo_candidates "${candidates[@]}"
  else
    echo "Skipped detected repositories under $normalized"
  fi
}

collect_manual_repos() {
  local raw_path=""

  echo "Enter repository paths one per line. If a path is not a git repository, DocMate will scan beneath it."
  echo "Submit an empty line to finish."
  while true; do
    read_user_line "Repository path: "
    raw_path="$REPLY"
    [ -n "$raw_path" ] || break
    process_repo_path "$raw_path"
  done
}

collect_auto_scan_repos() {
  local scan_root="$SCAN_ROOT"
  local candidate=""
  local candidates=()

  while true; do
    if [ -z "$scan_root" ]; then
      if [ "$YES" -eq 1 ]; then
        echo "Error: --auto-scan with --yes requires --scan-root PATH" >&2
        exit 1
      fi
      read_user_line "Repository prefix directory to scan: "
      scan_root="$REPLY"
    fi

    if [ ! -d "$scan_root" ]; then
      echo "Warning: scan root does not exist or is not a directory: $scan_root"
      scan_root=""
      continue
    fi

    scan_root="$(normalize_path "$scan_root")"
    if [ "$scan_root" = "/" ]; then
      echo "Warning: refusing to scan filesystem root. Choose a narrower repository prefix directory."
      scan_root=""
      continue
    fi

    echo "Repository prefix directory: $scan_root"
    if [ "$YES" -eq 1 ] || confirm_yes_no "Scan this prefix for git repositories?" "yes"; then
      break
    fi
    scan_root=""
  done

  echo "Scanning for git repositories under $scan_root (max depth: $SCAN_MAX_DEPTH)..."
  while IFS= read -r candidate; do
    [ -n "$candidate" ] && candidates+=("$candidate")
  done < <(find_repos_under "$scan_root")

  if [ "${#candidates[@]}" -eq 0 ]; then
    echo "Warning: no git repositories detected beneath $scan_root"
    return
  fi

  echo "Detected repositories:"
  print_repo_candidates "${candidates[@]}"
  if [ "$YES" -eq 1 ] || confirm_yes_no "Add all detected repositories?" "yes"; then
    add_repo_candidates "${candidates[@]}"
  else
    echo "Skipped auto-scan repositories"
  fi
}

discover_repos_interactive() {
  local choice=""

  while [ "${#REPOS[@]}" -eq 0 ]; do
    echo "Repository discovery:"
    echo "  [1] Manual input"
    echo "  [2] Auto scan"
    read_user_line "Enter choice [1-2]: "
    choice="$REPLY"
    case "$choice" in
      1) collect_manual_repos ;;
      2) collect_auto_scan_repos ;;
      *) echo "Invalid choice. Please try again." ;;
    esac
  done
}

for repo_arg in "${REPO_ARGS[@]}"; do
  process_repo_path "$repo_arg"
done

if [ "$AUTO_SCAN" -eq 1 ]; then
  collect_auto_scan_repos
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
  if [ "$YES" -eq 1 ] || ! can_prompt; then
    echo "Error: no repositories selected. Use --repo PATH or --auto-scan --scan-root PATH." >&2
    exit 1
  fi
  discover_repos_interactive
fi

if ! prepare_canonical_target; then
  echo "DocMate install skipped. Use --existing backup or --existing overwrite to replace the canonical install."
  exit 0
fi

materialize_file "skills/docmate/SKILL.md" "$CANONICAL_DIR/SKILL.md"
mkdir -p "$CANONICAL_DIR/references"
materialize_file "skills/docmate/references/docmate.catalog.example.json" "$CANONICAL_DIR/references/docmate.catalog.example.json"

NODE_BIN="$(find_node)"
REPO_FILE="$(mktemp)"
TMP_FILES+=("$REPO_FILE")
for repo_path in "${REPOS[@]}"; do
  printf '%s\t%s\n' "$repo_path" "$(detect_default_branch "$repo_path")" >> "$REPO_FILE"
done

"$NODE_BIN" - "$CANONICAL_DIR/references/docmate.catalog.json" "$SCHEMA_VERSION" "$HOSTS_RAW" "$UPDATE_MODE" "$REPO_FILE" <<'EOF'
const fs = require("node:fs");
const path = require("node:path");

const [, , catalogPath, schemaVersionRaw, hostsRaw, updateMode, repoFile] = process.argv;
const installHosts = hostsRaw === "all"
  ? ["openclaw", "claude-code", "opencode", "codex", "hermes"]
  : hostsRaw.split(",").map((host) => host.trim()).filter(Boolean);

const repos = fs.readFileSync(repoFile, "utf8")
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => {
    const [repoPath, defaultBranch] = line.split("\t");
    return {
      name: path.basename(repoPath),
      description: `Documentation repository at ${repoPath}. Edit this description and aliases for better routing.`,
      path: repoPath,
      aliases: [],
      baseBranchCandidates: [defaultBranch],
      update: {
        mode: updateMode,
      },
    };
  });

const payload = {
  schemaVersion: Number(schemaVersionRaw),
  installHosts,
  defaults: {
    update: {
      mode: updateMode,
    },
  },
  repos,
};

fs.writeFileSync(catalogPath, `${JSON.stringify(payload, null, 2)}\n`);
EOF

run_catalog_validator "$CANONICAL_DIR/references/docmate.catalog.json"

for host in "${HOSTS[@]}"; do
  target="$(host_dir "$host")"
  if [ "$target" = "$CANONICAL_DIR" ]; then
    continue
  fi
  if prepare_target "$target"; then
    ln -s "$CANONICAL_DIR" "$target"
  fi
done

echo "DocMate installed to $CANONICAL_DIR"
echo "Catalog: $CANONICAL_DIR/references/docmate.catalog.json"
