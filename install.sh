#!/usr/bin/env bash
# Extra setup after `omarchy plugin add`. The plugin files themselves come
# from Omarchy. This script checks dependencies, links the CLI, builds the
# optional search helper, and walks you through choosing the hotkey.
set -euo pipefail

PLUGIN_ID="nobledoodle.noblerunner"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
ENABLE=0
# ask: guided choice when run in a terminal. Or one of the four keys, or skip.
HOTKEY=ask
BUILD_SEARCH=1

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--enable] [--hotkey=KEY | --no-hotkey] [--no-search]

Run this after Omarchy has installed the plugin:

  omarchy plugin add https://github.com/NobleDoodle/noblerunner --enable
  ~/.config/omarchy/plugins/nobledoodle.noblerunner/install.sh

  --enable     Enable the plugin if it is not already enabled
  --hotkey=KEY Set the hotkey without asking. KEY is one of:
                 alt-space    Alt+Space
                 super        a tap of the Super key by itself
                 super-space  Super+Space (takes the Omarchy menu's key)
                 off          no hotkey
  --no-hotkey  Leave the hotkey as it is and do not ask
  --no-search  Do not build the optional Rust search helper

Run in a terminal with neither hotkey option, the script shows the four
choices and asks. The hotkey lives in ~/.config/hypr/noblerunner.lua. Change
it later with: noblerunner setup hyprland
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable) ENABLE=1 ;;
    --hotkey) HOTKEY=ask ;;
    --hotkey=alt-space|--hotkey=super|--hotkey=super-space|--hotkey=off) HOTKEY="${1#--hotkey=}" ;;
    --hotkey=*) die "unknown hotkey '${1#--hotkey=}'; use alt-space, super, super-space or off" ;;
    --no-hotkey) HOTKEY=skip ;;
    --no-search) BUILD_SEARCH=0 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

require_cmd() {
  local cmd="$1" why="$2" pkg="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    info "$cmd is installed ($why)"
  else
    die "missing $cmd ($why). Install the $pkg package, then run this script again."
  fi
}

info "Checking dependencies"
require_cmd omarchy-shell "the plugin runs inside the Omarchy shell" omarchy
require_cmd socat "fast calls from the noblerunner command" socat
require_cmd jq "plugin enable and doctor read the shell's plugin list" jq
if command -v hyprctl >/dev/null 2>&1; then
  info "hyprctl is installed (hotkey reload)"
else
  warn "hyprctl is missing. The plugin still runs; the hotkey step will be skipped."
fi

if [[ -x "$SOURCE_DIR/bin/noblerunner" ]]; then
  ROOT="$SOURCE_DIR"
elif [[ -x "$TARGET_DIR/bin/noblerunner" ]]; then
  ROOT="$TARGET_DIR"
else
  die "noblerunner is not installed. Run: omarchy plugin add https://github.com/NobleDoodle/noblerunner --enable"
fi
info "Using $ROOT"

if [[ "$BUILD_SEARCH" -eq 1 ]]; then
  if command -v cargo >/dev/null 2>&1; then
    info "Building the optional search helper"
    "$ROOT/bin/build-search"
  else
    warn "cargo is not installed, so the faster search helper was not built."
    warn "Search still works with the built-in matcher. Install rust and rerun this script to add the helper."
  fi
fi

mkdir -p "$HOME/.local/bin"
ln -sfn "$ROOT/bin/noblerunner" "$HOME/.local/bin/noblerunner"
info "Linked $HOME/.local/bin/noblerunner"

if [[ "$ENABLE" -eq 1 ]]; then
  info "Enabling $PLUGIN_ID"
  omarchy plugin enable "$PLUGIN_ID"
fi

hotkey_hint() { info "Choose a hotkey any time with: noblerunner setup hyprland"; }

if [[ "$HOTKEY" == skip ]]; then
  info "Hotkey left as it is."
  hotkey_hint
elif ! command -v hyprctl >/dev/null 2>&1; then
  warn "Skipping the hotkey because hyprctl is missing."
elif [[ "$HOTKEY" != ask ]]; then
  info "Setting the hotkey: $HOTKEY"
  "$ROOT/bin/noblerunner" setup hyprland "--key=$HOTKEY" --yes || warn "The hotkey was not changed."
elif [[ -t 0 && -t 1 ]]; then
  info "Hotkey"
  # The walkthrough: lists Alt+Space, Super, Super+Space and Off, says what
  # each key is used for now, and asks before taking a key from anything.
  if ! "$ROOT/bin/noblerunner" setup hyprland; then
    warn "The hotkey was not changed."
    hotkey_hint
  fi
else
  info "Not a terminal, so the hotkey question was skipped."
  hotkey_hint
fi

info "Checking the install"
"$ROOT/bin/noblerunner" doctor || true
info "Done. noblerunner stays loaded, so restart the shell once if the launcher does not appear: omarchy-restart-shell"
