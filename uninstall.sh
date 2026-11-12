#!/usr/bin/env bash
# Undo what install.sh added. Does not delete noblerunner's settings or history.
set -euo pipefail

PLUGIN_ID="nobledoodle.noblerunner"
info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

REMOVE_PLUGIN=0
REMOVE_HOTKEY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    # The hotkey file unbinds the key it took (Alt+Space dictation, the Super+Space
    # menu). Left behind without the plugin, that key would do nothing.
    --remove-plugin) REMOVE_PLUGIN=1; REMOVE_HOTKEY=1 ;;
    --hotkey) REMOVE_HOTKEY=1 ;;
    -h|--help)
      echo "Usage: uninstall.sh [--hotkey] [--remove-plugin]"
      echo "  --hotkey         Delete ~/.config/hypr/noblerunner.lua and its require line"
      echo "  --remove-plugin  Remove the hotkey too, then run: omarchy plugin remove $PLUGIN_ID"
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

cli="$HOME/.local/bin/noblerunner"
if [[ -L "$cli" ]]; then
  rm -f "$cli"
  info "Removed $cli"
fi

hypr="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
if [[ "$REMOVE_HOTKEY" -eq 1 ]]; then
  rm -f "$hypr/noblerunner.lua"
  if [[ -f "$hypr/hyprland.lua" ]]; then
    sed -i -E '/^[[:space:]]*require\("hypr\.noblerunner"\)[[:space:]]*$/d' "$hypr/hyprland.lua"
  fi
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null || warn "hyprctl reload failed; reload Hyprland yourself"
  fi
  info "Removed the noblerunner hotkey"
else
  info "Left the hotkey in place. Remove it with: uninstall.sh --hotkey"
fi

if [[ "$REMOVE_PLUGIN" -eq 1 ]]; then
  omarchy plugin remove "$PLUGIN_ID" --yes
else
  info "The plugin is still installed. Remove it with: omarchy plugin remove $PLUGIN_ID"
fi

info "Settings and history were kept under ~/.config/noblerunner and ~/.local/share/noblerunner"
