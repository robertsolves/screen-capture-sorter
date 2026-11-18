#!/usr/bin/env bash
# Stops the watcher, removes it and restores the screenshot settings install.sh replaced.
# Captures already sorted are left where they are.
set -euo pipefail

LABEL=com.robertsolves.screen-capture-sorter
BIN="$HOME/.local/bin/screen-capture-sorter"
STATE="$HOME/.local/state/screen-capture-sorter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$BIN"

restore() {
  local key=$1 file="$STATE/previous-$1"
  if [[ -s "$file" ]]; then
    defaults write com.apple.screencapture "$key" -string "$(cat "$file")"
  else
    defaults delete com.apple.screencapture "$key" 2>/dev/null || true
  fi
}
restore location
restore target
killall SystemUIServer 2>/dev/null || true
rm -rf "$STATE"

echo "Uninstalled. Screenshot settings restored; your captures were not touched."
