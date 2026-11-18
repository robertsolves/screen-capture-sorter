#!/usr/bin/env bash
# Stops the watcher, removes it and restores the screenshot settings install.sh replaced.
# Captures already sorted are left where they are, minus the LATEST_ markers.
set -euo pipefail

LABEL=com.robertsolves.screen-capture-sorter
BIN="$HOME/.local/bin/screen-capture-sorter"
STATE="$HOME/.local/state/screen-capture-sorter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$BIN"

# Takes the LATEST_ prefix off the newest day and hour folders so none is left stale.
unmark() {
  local folder=${1%/} parent name
  parent=$(dirname "$folder")
  name=$(basename "$folder")
  if [[ -e "$parent/${name#LATEST_}" ]]; then
    echo "Left $folder as is: $parent/${name#LATEST_} already exists" >&2
  else
    mv "$folder" "$parent/${name#LATEST_}"
  fi
}
if [[ -f "$STATE/dir" ]]; then
  DIR=$(cat "$STATE/dir")
  shopt -s nullglob
  for day in "$DIR"/LATEST_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/; do
    for hour in "$day"LATEST_[0-9][0-9]/; do unmark "$hour"; done
    unmark "$day"
  done
fi

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

echo "Uninstalled. Screenshot settings restored; your captures are still in place."
