#!/usr/bin/env bash
# Extra setup after `omarchy plugin add`. The plugin files themselves come
# from Omarchy. This script checks dependencies, links the CLI, builds the
# optional search helper, and can bind a hotkey.
set -euo pipefail

PLUGIN_ID="nobledoodle.noblerunner"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
ENABLE=0
HOTKEY=0
BUILD_SEARCH=1

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--enable] [--hotkey] [--no-search]

Run this after Omarchy has installed the plugin:

  omarchy plugin add https://github.com/NobleDoodle/noblerunner --enable
  ~/.config/omarchy/plugins/nobledoodle.noblerunner/install.sh

  --enable     Enable the plugin if it is not already enabled
  --hotkey     Bind Alt+Space in ~/.config/hypr/noblerunner.lua
               Skipped, not failed, when that chord is already taken.
               An existing noblerunner.lua is kept.
  --no-search  Do not build the optional Rust search helper
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable) ENABLE=1 ;;
    --hotkey) HOTKEY=1 ;;
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

if [[ "$HOTKEY" -eq 1 ]]; then
  if ! command -v hyprctl >/dev/null 2>&1; then
    warn "Skipping the hotkey because hyprctl is missing."
  else
    info "Binding a hotkey (Alt+Space). An existing noblerunner.lua is kept."
    if ! "$ROOT/bin/noblerunner" setup hyprland --yes; then
      warn "The hotkey was not written. Edit ~/.config/hypr/noblerunner.lua yourself if Alt+Space is already used."
    fi
  fi
else
  info "Hotkey skipped. Bind one with: noblerunner setup hyprland"
fi

info "Checking the install"
"$ROOT/bin/noblerunner" doctor || true
info "Done. noblerunner stays loaded, so restart the shell once if the launcher does not appear: omarchy-restart-shell"
