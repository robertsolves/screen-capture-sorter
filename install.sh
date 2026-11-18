#!/usr/bin/env bash
# Builds the watcher, points macOS screenshots and screen recordings at the capture folder and
# starts the watcher at login. Safe to re-run; it rebuilds and restarts.
#
#   SCREEN_CAPTURE_DIR  where captures go (default ~/Desktop/screen_capture)
#   SIGN_IDENTITY       codesign identity (default "-", ad hoc). A real identity keeps the
#                       Desktop access grant across rebuilds; ad hoc builds may ask again.
set -euo pipefail

LABEL=com.robertsolves.screen-capture-sorter
DIR="${SCREEN_CAPTURE_DIR:-$HOME/Desktop/screen_capture}"
IDENTITY="${SIGN_IDENTITY:--}"
BIN="$HOME/.local/bin/screen-capture-sorter"
STATE="$HOME/.local/state/screen-capture-sorter"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$(cd "$(dirname "$0")" && pwd)/main.swift"

command -v swiftc >/dev/null || { echo "swiftc not found; run: xcode-select --install" >&2; exit 1; }
mkdir -p "$(dirname "$BIN")" "$STATE" "$DIR" "$(dirname "$PLIST")"

echo "Building $BIN"
swiftc -O "$SRC" -o "$BIN"
codesign --force --sign "$IDENTITY" --identifier "$LABEL" "$BIN"

# Remember the settings we replace so uninstall.sh can put them back. Only on first install,
# so a re-run doesn't record our own values as the originals.
if [[ ! -f "$STATE/previous-location" ]]; then
  defaults read com.apple.screencapture location 2>/dev/null >"$STATE/previous-location" || : >"$STATE/previous-location"
  defaults read com.apple.screencapture target 2>/dev/null >"$STATE/previous-target" || : >"$STATE/previous-target"
fi
printf '%s\n' "$DIR" >"$STATE/dir"
defaults write com.apple.screencapture location -string "$DIR"
defaults write com.apple.screencapture target -string file
killall SystemUIServer 2>/dev/null || true

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$BIN</string>
		<string>$DIR</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardErrorPath</key>
	<string>$STATE/error.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed. Captures go to $DIR/YYYY-MM-DD/HH/ and are copied to the clipboard."
echo "If macOS asks whether screen-capture-sorter may access the Desktop folder, allow it."
