#!/usr/bin/env bash
set -euo pipefail

SKILL_SLUG="docmate"
SCHEMA_VERSION=2
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
ROOT_DIR=""
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd -P || pwd -P)"
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd -P || pwd -P)"
fi
CANONICAL_DIR="$HOME/.agents/skills/$SKILL_SLUG"

DOCMATE_REPO="${DOCMATE_REPO:-wufei-png/DocMate}"
DOCMATE_BRANCH="${DOCMATE_BRANCH:-main}"
REMOTE_RAW_BASE_URL="https://raw.githubusercontent.com/${DOCMATE_REPO}/${DOCMATE_BRANCH}"
DESCRIPTION_PROMPT_URL="https://github.com/${DOCMATE_REPO}/blob/${DOCMATE_BRANCH}/docs/prompts/fill-catalog-descriptions.md"
DOCMATE_USE_LOCAL_CACHE="${DOCMATE_USE_LOCAL_CACHE:-auto}"
SCAN_MAX_DEPTH="${DOCMATE_SCAN_MAX_DEPTH:-2}"
SCAN_DEPTH_CONFIGURED=0
if [ -n "${DOCMATE_SCAN_MAX_DEPTH:-}" ]; then
  SCAN_DEPTH_CONFIGURED=1
fi

YES=0
HOSTS_RAW=""
HOSTS_ARG_SET=0
SKILL_LANG=""
INSTALL_MODE=""
EXISTING="backup"
UPDATE_MODE="ask"
UPDATE_MODE_ARG_SET=0
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
  install.sh [--yes] --repo PATH [--repo PATH ...] [--language en|zh] [--install-mode global|single|custom] [--hosts all|openclaw,claude-code,opencode,codex,hermes] [--existing backup|skip|overwrite] [--update-mode auto|ask|off] [--scan-depth N]
  install.sh [--yes] --auto-scan --scan-root PATH [--scan-depth N] [--language en|zh] [--install-mode global|single|custom] [--hosts all|openclaw,claude-code,opencode,codex,hermes] [--existing backup|skip|overwrite] [--update-mode auto|ask|off]
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
    --language) SKILL_LANG="${2:-}"; shift 2 ;;
    --auto-scan) AUTO_SCAN=1; shift ;;
    --scan-root) SCAN_ROOT="${2:-}"; shift 2 ;;
    --scan-depth) SCAN_MAX_DEPTH="${2:-}"; SCAN_DEPTH_CONFIGURED=1; shift 2 ;;
    --install-mode) INSTALL_MODE="${2:-}"; shift 2 ;;
    --hosts) HOSTS_RAW="${2:-}"; HOSTS_ARG_SET=1; shift 2 ;;
    --existing) EXISTING="${2:-}"; shift 2 ;;
    --update-mode) UPDATE_MODE="${2:-}"; UPDATE_MODE_ARG_SET=1; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

case "$EXISTING" in backup|skip|overwrite) ;; *) usage ;; esac
case "$SKILL_LANG" in ""|en|zh) ;; *) usage ;; esac
case "$INSTALL_MODE" in ""|global|single|custom) ;; *) usage ;; esac
case "$UPDATE_MODE" in ask|auto|off) ;; *) usage ;; esac
case "$SCAN_MAX_DEPTH" in ""|*[!0-9]*|0) usage ;; esac

SUPPORTED_HOSTS=(openclaw claude-code opencode codex hermes)
HOSTS=()
INSTALL_STRATEGY="symlink"
INSTALL_TARGET_DIR="$CANONICAL_DIR"
MENU_LABELS=()
MENU_VALUES=()
MENU_ENABLED=()
MENU_SELECTED=()
MENU_ROW_DETECTED=()
MENU_RESULT=""
MENU_RESULTS=()
MENU_CURSOR=0
MENU_LINES=0
MENU_MESSAGE=""
MENU_ALL_DETECTED_MODE=0

cleanup() {
  local tmp_file
  for tmp_file in ${TMP_FILES[@]+"${TMP_FILES[@]}"}; do
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
  done
}
trap cleanup EXIT

can_prompt() {
  [ "$TTY_AVAILABLE" -eq 1 ] || [ -t 0 ]
}

can_use_interactive_menu() {
  [ "$TTY_AVAILABLE" -eq 1 ] && [ "${TERM:-dumb}" != "dumb" ]
}

ui_printf() {
  if [ "$TTY_AVAILABLE" -eq 1 ]; then
    printf "%b" "$1" >&$TTY_FD
  else
    printf "%b" "$1"
  fi
}

read_menu_key() {
  local key=""
  local rest=""

  IFS= read -rsn1 key <&$TTY_FD || return 1
  if [ "$key" = $'\x1b' ]; then
    IFS= read -rsn2 rest <&$TTY_FD || true
    key="$key$rest"
  fi

  case "$key" in
    $'\x1b[A') printf '%s\n' "up" ;;
    $'\x1b[B') printf '%s\n' "down" ;;
    " ") printf '%s\n' "space" ;;
    ""|$'\r') printf '%s\n' "enter" ;;
    *) printf '%s\n' "other" ;;
  esac
}

draw_menu() {
  local title="$1"
  local hint="$2"
  local index=0
  local marker=""
  local checkbox=""
  local line=""

  if [ "$MENU_LINES" -gt 0 ]; then
    ui_printf "\033[${MENU_LINES}A"
  fi
  ui_printf "\033[J"

  MENU_LINES=0
  ui_printf "${title}\n"
  MENU_LINES=$((MENU_LINES + 1))
  ui_printf "${hint}\n"
  MENU_LINES=$((MENU_LINES + 1))

  for index in "${!MENU_LABELS[@]}"; do
    marker=" "
    if [ "$index" -eq "$MENU_CURSOR" ]; then
      marker=">"
    fi

    checkbox="[ ]"
    if [ "${MENU_SELECTED[$index]:-0}" -eq 1 ]; then
      checkbox="[x]"
    fi

    line="${marker} ${checkbox} ${MENU_LABELS[$index]}"
    if [ "${MENU_ENABLED[$index]:-1}" -ne 1 ]; then
      line="${line} (not available)"
    fi
    ui_printf "${line}\n"
    MENU_LINES=$((MENU_LINES + 1))
  done

  if [ -n "$MENU_MESSAGE" ]; then
    ui_printf "${MENU_MESSAGE}\n"
  else
    ui_printf "\n"
  fi
  MENU_LINES=$((MENU_LINES + 1))
}

sync_all_detected_row() {
  local index=0
  local detected_count=0
  local selected_count=0

  if [ "$MENU_ALL_DETECTED_MODE" -ne 1 ]; then
    return
  fi

  for index in "${!MENU_LABELS[@]}"; do
    if [ "$index" -eq 0 ]; then
      continue
    fi
    if [ "${MENU_ROW_DETECTED[$index]:-0}" -eq 1 ]; then
      detected_count=$((detected_count + 1))
      if [ "${MENU_SELECTED[$index]:-0}" -eq 1 ]; then
        selected_count=$((selected_count + 1))
      fi
    fi
  done

  if [ "$detected_count" -gt 0 ] && [ "$selected_count" -eq "$detected_count" ]; then
    MENU_SELECTED[0]=1
  else
    MENU_SELECTED[0]=0
  fi
}

toggle_all_detected_rows() {
  local index=0
  local next_state=1

  if [ "${MENU_SELECTED[0]:-0}" -eq 1 ]; then
    next_state=0
  fi

  MENU_SELECTED[0]=$next_state
  for index in "${!MENU_LABELS[@]}"; do
    if [ "$index" -eq 0 ]; then
      continue
    fi
    if [ "${MENU_ROW_DETECTED[$index]:-0}" -eq 1 ]; then
      MENU_SELECTED[$index]=$next_state
    fi
  done
}

run_menu() {
  local title="$1"
  local mode="$2"
  local empty_message="$3"
  local hint=""
  local key=""
  local selected_count=0
  local index=0

  MENU_RESULT=""
  MENU_RESULTS=()
  MENU_CURSOR=0
  MENU_LINES=0
  MENU_MESSAGE=""
  MENU_SELECTED=()

  for index in "${!MENU_LABELS[@]}"; do
    MENU_SELECTED[$index]=0
  done
  if [ "$mode" = "single" ] && [ "${#MENU_LABELS[@]}" -gt 0 ]; then
    MENU_SELECTED[0]=1
  fi
  if [ "$mode" = "multi" ]; then
    sync_all_detected_row
  fi

  if [ "$mode" = "multi" ]; then
    hint="Use Up/Down to move, Space to select, Enter to confirm."
  else
    hint="Use Up/Down to move, Space or Enter to select."
  fi

  ui_printf "\033[?25l"
  while true; do
    draw_menu "$title" "$hint"
    key="$(read_menu_key)" || key="enter"

    case "$key" in
      up)
        if [ "$MENU_CURSOR" -gt 0 ]; then
          MENU_CURSOR=$((MENU_CURSOR - 1))
        else
          MENU_CURSOR=$((${#MENU_LABELS[@]} - 1))
        fi
        if [ "$mode" = "single" ]; then
          for index in "${!MENU_SELECTED[@]}"; do
            MENU_SELECTED[$index]=0
          done
          MENU_SELECTED[$MENU_CURSOR]=1
        fi
        MENU_MESSAGE=""
        ;;
      down)
        if [ "$MENU_CURSOR" -lt $((${#MENU_LABELS[@]} - 1)) ]; then
          MENU_CURSOR=$((MENU_CURSOR + 1))
        else
          MENU_CURSOR=0
        fi
        if [ "$mode" = "single" ]; then
          for index in "${!MENU_SELECTED[@]}"; do
            MENU_SELECTED[$index]=0
          done
          MENU_SELECTED[$MENU_CURSOR]=1
        fi
        MENU_MESSAGE=""
        ;;
      space|enter)
        if [ "${MENU_ENABLED[$MENU_CURSOR]:-1}" -ne 1 ]; then
          MENU_MESSAGE="This option is not available."
          continue
        fi

        if [ "$mode" = "single" ]; then
          MENU_RESULT="${MENU_VALUES[$MENU_CURSOR]}"
          MENU_RESULTS=("$MENU_RESULT")
          break
        fi

        if [ "$key" = "space" ]; then
          if [ "$MENU_ALL_DETECTED_MODE" -eq 1 ] && [ "$MENU_CURSOR" -eq 0 ]; then
            toggle_all_detected_rows
          elif [ "${MENU_SELECTED[$MENU_CURSOR]:-0}" -eq 1 ]; then
            MENU_SELECTED[$MENU_CURSOR]=0
          else
            MENU_SELECTED[$MENU_CURSOR]=1
          fi
          sync_all_detected_row
          MENU_MESSAGE=""
          continue
        fi

        selected_count=0
        MENU_RESULTS=()
        for index in "${!MENU_SELECTED[@]}"; do
          if [ "$MENU_ALL_DETECTED_MODE" -eq 1 ] && [ "$index" -eq 0 ]; then
            continue
          fi
          if [ "${MENU_SELECTED[$index]:-0}" -eq 1 ]; then
            selected_count=$((selected_count + 1))
            MENU_RESULTS+=("${MENU_VALUES[$index]}")
          fi
        done

        if [ "$selected_count" -eq 0 ]; then
          MENU_MESSAGE="$empty_message"
          continue
        fi

        MENU_RESULT="${MENU_RESULTS[0]}"
        break
        ;;
    esac
  done

  ui_printf "\033[?25h"
  ui_printf "\n"
}

array_contains() {
  local needle="$1"
  shift || true

  local item
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

host_command() {
  case "$1" in
    openclaw) printf '%s\n' "openclaw" ;;
    claude-code) printf '%s\n' "claude" ;;
    opencode) printf '%s\n' "opencode" ;;
    codex) printf '%s\n' "codex" ;;
    hermes) printf '%s\n' "hermes" ;;
    *) return 1 ;;
  esac
}

host_label() {
  case "$1" in
    openclaw) printf '%s\n' "OpenClaw" ;;
    claude-code) printf '%s\n' "Claude Code" ;;
    opencode) printf '%s\n' "OpenCode" ;;
    codex) printf '%s\n' "Codex" ;;
    hermes) printf '%s\n' "Hermes" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

is_supported_host() {
  local host="$1"
  array_contains "$host" "${SUPPORTED_HOSTS[@]}"
}

is_host_detected() {
  local command_name
  command_name="$(host_command "$1")" || return 1
  command -v "$command_name" >/dev/null 2>&1
}

host_status_label() {
  if is_host_detected "$1"; then
    printf '%s\n' "detected"
  else
    printf '%s\n' "not detected, can still create directory"
  fi
}

add_selected_host() {
  local host="$1"

  if ! is_supported_host "$host"; then
    echo "Error: unsupported agent platform: $host" >&2
    exit 1
  fi
  if ! array_contains "$host" ${HOSTS[@]+"${HOSTS[@]}"}; then
    HOSTS+=("$host")
  fi
}

parse_hosts_raw() {
  local raw_hosts="$1"
  local host=""

  HOSTS=()
  if [ -z "$raw_hosts" ]; then
    echo "Error: --hosts requires at least one agent platform or all" >&2
    exit 1
  fi

  if [ "$raw_hosts" = "all" ]; then
    HOSTS=("${SUPPORTED_HOSTS[@]}")
    return
  fi

  for host in $(printf '%s\n' "$raw_hosts" | tr ',' ' '); do
    add_selected_host "$host"
  done

  if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "Error: --hosts did not select any supported agent platform" >&2
    exit 1
  fi
}

select_detected_hosts() {
  local host

  HOSTS=()
  for host in "${SUPPORTED_HOSTS[@]}"; do
    if is_host_detected "$host"; then
      HOSTS+=("$host")
    fi
  done

  if [ "${#HOSTS[@]}" -eq 0 ]; then
    echo "Warning: no supported agent platform CLI detected; using Codex canonical install target."
    HOSTS=(codex)
  fi
}

print_host_summary() {
  local host
  local marker

  echo "Agent platform status:"
  for host in "${SUPPORTED_HOSTS[@]}"; do
    marker="[ ]"
    if array_contains "$host" ${HOSTS[@]+"${HOSTS[@]}"}; then
      marker="[x]"
    fi
    echo "  $marker $(host_label "$host") ($(host_status_label "$host"))"
  done
  echo ""
}

build_host_menu_rows() {
  local include_all="$1"
  local host=""
  local detected=0

  MENU_LABELS=()
  MENU_VALUES=()
  MENU_ENABLED=()
  MENU_ROW_DETECTED=()

  if [ "$include_all" = "true" ]; then
    MENU_LABELS+=("All detected agent platforms")
    MENU_VALUES+=("all-detected")
    MENU_ENABLED+=(1)
    MENU_ROW_DETECTED+=(0)
  fi

  for host in "${SUPPORTED_HOSTS[@]}"; do
    detected=0
    if is_host_detected "$host"; then
      detected=1
    fi
    MENU_LABELS+=("$(host_label "$host") ($(host_status_label "$host"))")
    MENU_VALUES+=("$host")
    MENU_ENABLED+=(1)
    MENU_ROW_DETECTED+=("$detected")
  done
}

select_install_mode_interactive() {
  local choice=""

  if can_use_interactive_menu; then
    MENU_LABELS=(
      "All detected agent platforms (recommended) - OpenClaw, Claude Code, OpenCode, Codex, Hermes"
      "One agent platform - choose OpenClaw, Claude Code, OpenCode, Codex, or Hermes"
      "Selected agent platforms - choose multiple from OpenClaw, Claude Code, OpenCode, Codex, Hermes"
    )
    MENU_VALUES=(global single custom)
    MENU_ENABLED=(1 1 1)
    MENU_ROW_DETECTED=(0 0 0)
    MENU_ALL_DETECTED_MODE=0
    run_menu "Agent platform mode" "single" "Please select one agent platform mode."
    INSTALL_MODE="$MENU_RESULT"
    return
  fi

  echo "Agent platform mode:"
  echo "  [1] All detected agent platforms (recommended) - OpenClaw, Claude Code, OpenCode, Codex, Hermes"
  echo "  [2] One agent platform - choose OpenClaw, Claude Code, OpenCode, Codex, or Hermes"
  echo "  [3] Selected agent platforms - choose multiple from OpenClaw, Claude Code, OpenCode, Codex, Hermes"
  echo ""

  while true; do
    read_user_line "Enter choice [1-3, default 1]: "
    choice="$REPLY"
    case "$choice" in
      ""|1) INSTALL_MODE="global"; break ;;
      2) INSTALL_MODE="single"; break ;;
      3) INSTALL_MODE="custom"; break ;;
      *) echo "Invalid choice. Please try again." ;;
    esac
  done
}

select_single_host_interactive() {
  local choice=""

  if can_use_interactive_menu; then
    build_host_menu_rows "false"
    MENU_ALL_DETECTED_MODE=0
    run_menu "Select one agent platform" "single" "Please select one agent platform."
    HOSTS=("$MENU_RESULT")
    return
  fi

  echo "Select one agent platform:"
  echo "  [1] OpenClaw     ($(host_status_label "openclaw"))"
  echo "  [2] Claude Code  ($(host_status_label "claude-code"))"
  echo "  [3] OpenCode     ($(host_status_label "opencode"))"
  echo "  [4] Codex        ($(host_status_label "codex"))"
  echo "  [5] Hermes       ($(host_status_label "hermes"))"
  echo ""

  while true; do
    read_user_line "Enter choice [1-5]: "
    choice="$REPLY"
    case "$choice" in
      1) HOSTS=(openclaw); break ;;
      2) HOSTS=(claude-code); break ;;
      3) HOSTS=(opencode); break ;;
      4) HOSTS=(codex); break ;;
      5) HOSTS=(hermes); break ;;
      *) echo "Invalid choice. Please try again." ;;
    esac
  done
}

select_custom_hosts_interactive() {
  local choices=""
  local choice=""

  if can_use_interactive_menu; then
    build_host_menu_rows "true"
    MENU_ALL_DETECTED_MODE=1
    run_menu "Select agent platforms" "multi" "Please select at least one agent platform."
    HOSTS=(${MENU_RESULTS[@]+"${MENU_RESULTS[@]}"})
    MENU_ALL_DETECTED_MODE=0
    return
  fi

  echo "Select agent platforms:"
  echo "  [0] All detected agent platforms"
  echo "  [1] OpenClaw     ($(host_status_label "openclaw"))"
  echo "  [2] Claude Code  ($(host_status_label "claude-code"))"
  echo "  [3] OpenCode     ($(host_status_label "opencode"))"
  echo "  [4] Codex        ($(host_status_label "codex"))"
  echo "  [5] Hermes       ($(host_status_label "hermes"))"
  echo ""

  while true; do
    HOSTS=()
    read_user_line "Enter numbers (e.g., 0 or 1,3,5): "
    choices="$REPLY"
    for choice in $(printf '%s\n' "$choices" | tr ',' ' '); do
      case "$choice" in
        0|all|ALL)
          select_detected_hosts
          ;;
        1) add_selected_host "openclaw" ;;
        2) add_selected_host "claude-code" ;;
        3) add_selected_host "opencode" ;;
        4) add_selected_host "codex" ;;
        5) add_selected_host "hermes" ;;
        "") ;;
        *) echo "Warning: ignoring invalid host choice: $choice" ;;
      esac
    done

    if [ "${#HOSTS[@]}" -gt 0 ]; then
      break
    fi
    echo "Please select at least one agent platform."
  done
}

select_update_mode_interactive() {
  local choice=""

  if [ "$UPDATE_MODE_ARG_SET" -eq 1 ]; then
    return
  fi

  if [ "$YES" -eq 1 ] || ! can_prompt; then
    return
  fi

  if can_use_interactive_menu; then
    MENU_LABELS=(
      "Ask (default) - always ask before editing docs or opening a PR/MR"
      "Auto - repair high-confidence confirmed gaps without asking"
      "Off - only report gaps; never edit documentation"
    )
    MENU_VALUES=(ask auto off)
    MENU_ENABLED=(1 1 1)
    MENU_ROW_DETECTED=(0 0 0)
    MENU_ALL_DETECTED_MODE=0
    run_menu "Documentation repair mode" "single" "Please select one update mode."
    UPDATE_MODE="$MENU_RESULT"
    return
  fi

  echo "Documentation repair mode:"
  echo "  [1] Ask (default) - always ask before editing docs or opening a PR/MR"
  echo "  [2] Auto - repair high-confidence confirmed gaps without asking"
  echo "  [3] Off - only report gaps; never edit documentation"
  echo ""

  while true; do
    read_user_line "Enter choice [1-3, default 1]: "
    choice="$REPLY"
    case "$choice" in
      ""|1) UPDATE_MODE="ask"; break ;;
      2) UPDATE_MODE="auto"; break ;;
      3) UPDATE_MODE="off"; break ;;
      *) echo "Invalid choice. Please try again." ;;
    esac
  done
}

select_install_targets() {
  if [ "$HOSTS_ARG_SET" -eq 1 ]; then
    parse_hosts_raw "$HOSTS_RAW"
    if [ -z "$INSTALL_MODE" ]; then
      INSTALL_MODE="custom"
    fi
  else
    if [ -z "$INSTALL_MODE" ]; then
      if [ "$YES" -eq 1 ] || ! can_prompt; then
        INSTALL_MODE="global"
      else
        select_install_mode_interactive
      fi
    fi

    case "$INSTALL_MODE" in
      global)
        select_detected_hosts
        ;;
      single)
        if [ "$YES" -eq 1 ] || ! can_prompt; then
          echo "Error: --install-mode single requires --hosts PLATFORM in non-interactive mode" >&2
          exit 1
        fi
        select_single_host_interactive
        ;;
      custom)
        if [ "$YES" -eq 1 ] || ! can_prompt; then
          echo "Error: --install-mode custom requires --hosts PLATFORM[,PLATFORM...] in non-interactive mode" >&2
          exit 1
        fi
        select_custom_hosts_interactive
        ;;
    esac
  fi

  if [ "$INSTALL_MODE" = "single" ]; then
    if [ "${#HOSTS[@]}" -ne 1 ]; then
      echo "Error: single platform install requires exactly one selected agent platform" >&2
      exit 1
    fi
    INSTALL_STRATEGY="direct"
    INSTALL_TARGET_DIR="$(host_dir "${HOSTS[0]}")"
  else
    INSTALL_STRATEGY="symlink"
    INSTALL_TARGET_DIR="$CANONICAL_DIR"
  fi

  echo "Selected install mode: $INSTALL_MODE"
  print_host_summary
}

select_skill_language() {
  local choice=""

  if [ -n "$SKILL_LANG" ]; then
    case "$SKILL_LANG" in
      zh) echo "Selected skill language: 中文" ;;
      en) echo "Selected skill language: English" ;;
    esac
    return
  fi

  if [ "$YES" -eq 1 ] || ! can_prompt; then
    SKILL_LANG="en"
    echo "Selected skill language: English"
    return
  fi

  if can_use_interactive_menu; then
    MENU_LABELS=("English" "中文")
    MENU_VALUES=(en zh)
    MENU_ENABLED=(1 1)
    MENU_ROW_DETECTED=(0 0)
    MENU_ALL_DETECTED_MODE=0
    run_menu "Skill language / 选择语言" "single" "Please select one skill language."
    SKILL_LANG="$MENU_RESULT"
  else
    echo "Skill language / 选择语言:"
    echo "  [1] English"
    echo "  [2] 中文"
    echo ""

    while true; do
      read_user_line "Enter choice [1-2, default 1]: "
      choice="$REPLY"
      case "$choice" in
        ""|1) SKILL_LANG="en"; break ;;
        2) SKILL_LANG="zh"; break ;;
        *) echo "Invalid choice. Please try again." ;;
      esac
    done
  fi

  case "$SKILL_LANG" in
    zh) echo "Selected skill language: 中文" ;;
    en) echo "Selected skill language: English" ;;
  esac
}

should_use_local_file() {
  local rel_path="$1"

  if [ -z "$ROOT_DIR" ]; then
    return 1
  fi

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

deploy_skill_file() {
  local rel_path="skills/docmate/SKILL.en.md"

  if [ "$SKILL_LANG" = "zh" ]; then
    rel_path="skills/docmate/SKILL.zh.md"
  fi

  materialize_file "$rel_path" "$INSTALL_TARGET_DIR/SKILL.md"
  rm -f "$INSTALL_TARGET_DIR/SKILL.en.md" "$INSTALL_TARGET_DIR/SKILL.zh.md" 2>/dev/null || true

  if [ "$SKILL_LANG" = "zh" ]; then
    echo "Deployed Chinese DocMate skill."
  else
    echo "Deployed English DocMate skill."
  fi
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
    *) echo "Error: unsupported agent platform: $1" >&2; exit 1 ;;
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

prepare_install_dir() {
  local target="$1"
  local label="${2:-install target}"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$target"
    return
  fi

  case "$EXISTING" in
    skip)
      echo "Skipping existing $label: $target"
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
  mkdir -p "$target"
}

read_user_line() {
  local prompt="$1"

  if [ "$TTY_AVAILABLE" -eq 1 ]; then
    ui_printf "$prompt"
    if IFS= read -r REPLY <&$TTY_FD; then
      return
    fi
    REPLY=""
    echo "Error: interactive input is unavailable. Re-run with --repo PATH or --auto-scan --scan-root PATH." >&2
    exit 1
  fi

  if [ -t 0 ]; then
    printf "%s" "$prompt"
    if IFS= read -r REPLY; then
      return
    fi
    REPLY=""
    echo "Error: interactive input is unavailable. Re-run with --repo PATH or --auto-scan --scan-root PATH." >&2
    exit 1
  fi

  echo "Error: interactive input is unavailable. Re-run with --repo PATH or --auto-scan --scan-root PATH." >&2
  exit 1
}

confirm_yes_no() {
  local prompt="$1"
  local default_answer="${2:-no}"
  local answer=""
  local suffix="[y/N]"

  if can_use_interactive_menu; then
    if [ "$default_answer" = "yes" ]; then
      MENU_LABELS=("Yes (default)" "No")
      MENU_VALUES=(yes no)
    else
      MENU_LABELS=("No (default)" "Yes")
      MENU_VALUES=(no yes)
    fi
    MENU_ENABLED=(1 1)
    MENU_ROW_DETECTED=(0 0)
    MENU_ALL_DETECTED_MODE=0
    run_menu "$prompt" "single" "Please select yes or no."
    [ "$MENU_RESULT" = "yes" ]
    return
  fi

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

  for existing_path in ${REPOS[@]+"${REPOS[@]}"}; do
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

remove_repo_index() {
  local remove_index="$1"
  local index=0
  local filtered=()

  for index in "${!REPOS[@]}"; do
    if [ "$index" -ne "$remove_index" ]; then
      filtered+=("${REPOS[$index]}")
    fi
  done

  REPOS=(${filtered[@]+"${filtered[@]}"})
}

resolve_duplicate_repo_names() {
  local first=0
  local second=0
  local duplicate_name=""
  local choice=""

  while true; do
    duplicate_name=""
    first=0
    second=0

    for first in "${!REPOS[@]}"; do
      for second in "${!REPOS[@]}"; do
        if [ "$second" -le "$first" ]; then
          continue
        fi
        if [ "$(basename "${REPOS[$first]}")" = "$(basename "${REPOS[$second]}")" ]; then
          duplicate_name="$(basename "${REPOS[$first]}")"
          break 2
        fi
      done
    done

    if [ -z "$duplicate_name" ]; then
      return
    fi

    echo "Warning: duplicate repository name detected: $duplicate_name"
    echo "  [A] ${REPOS[$first]}"
    echo "  [B] ${REPOS[$second]}"

    if [ "$YES" -eq 1 ] || ! can_prompt; then
      echo "Warning: keeping ${REPOS[$first]} and excluding ${REPOS[$second]}"
      remove_repo_index "$second"
      continue
    fi

    if can_use_interactive_menu; then
      MENU_LABELS=(
        "Exit install"
        "Exclude A: ${REPOS[$first]}"
        "Exclude B: ${REPOS[$second]}"
      )
      MENU_VALUES=(exit exclude-first exclude-second)
      MENU_ENABLED=(1 1 1)
      MENU_ROW_DETECTED=(0 0 0)
      MENU_ALL_DETECTED_MODE=0
      run_menu "Duplicate repository name action" "single" "Please choose how to resolve the duplicate repository name."
      case "$MENU_RESULT" in
        exit)
          echo "Install cancelled because duplicate repository names must be resolved."
          exit 1
          ;;
        exclude-first)
          echo "Excluding ${REPOS[$first]}"
          remove_repo_index "$first"
          continue
          ;;
        exclude-second)
          echo "Excluding ${REPOS[$second]}"
          remove_repo_index "$second"
          continue
          ;;
      esac
    fi

    while true; do
      echo "Duplicate repository name action:"
      echo "  [1] Exit install"
      echo "  [2] Exclude A: ${REPOS[$first]}"
      echo "  [3] Exclude B: ${REPOS[$second]}"
      read_user_line "Enter choice [1-3]: "
      choice="$REPLY"
      case "$choice" in
        1)
          echo "Install cancelled because duplicate repository names must be resolved."
          exit 1
          ;;
        2)
          echo "Excluding ${REPOS[$first]}"
          remove_repo_index "$first"
          break
          ;;
        3)
          echo "Excluding ${REPOS[$second]}"
          remove_repo_index "$second"
          break
          ;;
        *) echo "Invalid choice. Please try again." ;;
      esac
    done
  done
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

select_scan_depth_interactive() {
  local depth=""
  local option=""

  if can_use_interactive_menu; then
    MENU_LABELS=("$SCAN_MAX_DEPTH (default)")
    MENU_VALUES=("$SCAN_MAX_DEPTH")
    MENU_ENABLED=(1)
    MENU_ROW_DETECTED=(0)
    for option in 1 2 3 4 5; do
      if [ "$option" != "$SCAN_MAX_DEPTH" ]; then
        MENU_LABELS+=("$option")
        MENU_VALUES+=("$option")
        MENU_ENABLED+=(1)
        MENU_ROW_DETECTED+=(0)
      fi
    done
    MENU_LABELS+=("Custom depth")
    MENU_VALUES+=(custom)
    MENU_ENABLED+=(1)
    MENU_ROW_DETECTED+=(0)
    MENU_ALL_DETECTED_MODE=0
    run_menu "Repository scan depth" "single" "Please select one scan depth."
    if [ "$MENU_RESULT" != "custom" ]; then
      SCAN_MAX_DEPTH="$MENU_RESULT"
      return
    fi
  fi

  while true; do
    read_user_line "Repository scan depth [default: $SCAN_MAX_DEPTH]: "
    depth="$REPLY"
    if [ -z "$depth" ]; then
      return
    fi
    case "$depth" in
      *[!0-9]*|0)
        echo "Invalid scan depth. Please enter a positive integer."
        ;;
      *)
        SCAN_MAX_DEPTH="$depth"
        return
        ;;
    esac
  done
}

collect_auto_scan_repos() {
  local scan_root="$SCAN_ROOT"
  local candidate=""
  local candidates=()
  local depth_selected=0

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
    if [ "$YES" -ne 1 ] && [ "$SCAN_DEPTH_CONFIGURED" -ne 1 ] && [ "$depth_selected" -eq 0 ]; then
      select_scan_depth_interactive
      depth_selected=1
    fi
    if [ "$YES" -eq 1 ] || confirm_yes_no "Scan this prefix for git repositories with max depth $SCAN_MAX_DEPTH?" "yes"; then
      break
    fi
    scan_root=""
    depth_selected=0
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
    if can_use_interactive_menu; then
      MENU_LABELS=(
        "Auto scan - search for git repositories under a prefix"
        "Manual input - enter repository paths one by one"
      )
      MENU_VALUES=(auto manual)
      MENU_ENABLED=(1 1)
      MENU_ROW_DETECTED=(0 0)
      MENU_ALL_DETECTED_MODE=0
      run_menu "Repository discovery" "single" "Please select one repository discovery mode."
      case "$MENU_RESULT" in
        auto) collect_auto_scan_repos ;;
        manual) collect_manual_repos ;;
      esac
      continue
    fi

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

select_skill_language

for repo_arg in ${REPO_ARGS[@]+"${REPO_ARGS[@]}"}; do
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

resolve_duplicate_repo_names
select_update_mode_interactive
echo "Selected documentation repair mode: $UPDATE_MODE"
select_install_targets

if ! prepare_install_dir "$INSTALL_TARGET_DIR" "$INSTALL_MODE install target"; then
  echo "DocMate install skipped. Use --existing backup or --existing overwrite to replace the install target."
  exit 0
fi

deploy_skill_file
mkdir -p "$INSTALL_TARGET_DIR/references"

NODE_BIN="$(find_node)"
REPO_FILE="$(mktemp)"
TMP_FILES+=("$REPO_FILE")
for repo_path in ${REPOS[@]+"${REPOS[@]}"}; do
  printf '%s\t%s\n' "$repo_path" "$(detect_default_branch "$repo_path")" >> "$REPO_FILE"
done

"$NODE_BIN" - "$INSTALL_TARGET_DIR/references/docmate.catalog.json" "$SCHEMA_VERSION" "$UPDATE_MODE" "$REPO_FILE" <<'EOF'
const fs = require("node:fs");
const path = require("node:path");

const [, , catalogPath, schemaVersionRaw, updateMode, repoFile] = process.argv;

const repos = fs.readFileSync(repoFile, "utf8")
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => {
    const [repoPath, defaultBranch] = line.split("\t");
    return {
      name: path.basename(repoPath),
      path: repoPath,
      baseBranchCandidates: [defaultBranch],
    };
  });

const payload = {
  schemaVersion: Number(schemaVersionRaw),
  defaults: {
    update: {
      mode: updateMode,
    },
  },
  repos,
};

fs.writeFileSync(catalogPath, `${JSON.stringify(payload, null, 2)}\n`);
EOF

run_catalog_validator "$INSTALL_TARGET_DIR/references/docmate.catalog.json"

if [ "$INSTALL_STRATEGY" = "symlink" ]; then
  for host in ${HOSTS[@]+"${HOSTS[@]}"}; do
    target="$(host_dir "$host")"
    if [ "$target" = "$CANONICAL_DIR" ]; then
      continue
    fi
    if prepare_target "$target"; then
      ln -s "$CANONICAL_DIR" "$target"
    fi
  done
fi

echo "DocMate installed to $INSTALL_TARGET_DIR"
echo "Catalog: $INSTALL_TARGET_DIR/references/docmate.catalog.json"
echo
echo "============================================================"
echo "Optional catalog enrichment"
echo "Edit these optional routing fields in:"
echo "  $INSTALL_TARGET_DIR/references/docmate.catalog.json"
echo "- repos[].description: to auto-fill this field, open this one-time prompt"
echo "  and paste it into your own agent:"
echo "  $DESCRIPTION_PROMPT_URL"
echo "  Provide this catalog path to the agent:"
echo "  $INSTALL_TARGET_DIR/references/docmate.catalog.json"
echo "- repos[].aliases: fill manually with short names users may type for the project."
echo "- repos[].baseBranchCandidates: seeded from the detected remote default"
echo "  branch via gh/glab/git, then local HEAD, then fallback main; edit it if"
echo "  documentation repair should target another base branch."
echo "- defaults.update.mode: global repair mode for all repos; current value:"
echo "  $UPDATE_MODE"
echo "============================================================"
