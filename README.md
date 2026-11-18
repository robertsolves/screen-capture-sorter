# screen-capture-sorter

Every macOS screenshot and screen recording you take is copied to the clipboard and filed by
day and hour:

```
~/Desktop/screen_capture/
└── 2026-11-19/
    └── 14/
        ├── Screenshot 2026-11-19 at 14.03.22.png
        └── Screen Recording 2026-11-19 at 14.10.05.mov
```

It works with every capture shortcut (⌘⇧3, ⌘⇧4, ⌘⇧5 and the Screenshot app). Images go on
the clipboard as image data plus the file. Recordings go on as the file, so ⌘V pastes them
into Finder, chat apps and terminals.

## Install

Needs the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/robertsolves/screen-capture-sorter.git
cd screen-capture-sorter
./install.sh
```

Take a screenshot. If macOS asks whether `screen-capture-sorter` may access your Desktop
folder, allow it. Without that access it can't move anything.

Options, set as environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `SCREEN_CAPTURE_DIR` | `~/Desktop/screen_capture` | where captures are saved and sorted |
| `SIGN_IDENTITY` | `-` (ad hoc) | codesign identity. A real one (`security find-identity -v -p codesigning`) keeps the Desktop grant across reinstalls |

## Uninstall

```sh
./uninstall.sh
```

This stops the watcher, removes it and restores your previous screenshot save location.
Captures already filed are left where they are.

## How it works

`install.sh` points macOS's screenshot location (`defaults write com.apple.screencapture
location`) at the capture folder. It then compiles `main.swift` into
`~/.local/bin/screen-capture-sorter` and runs it at login with a launchd agent. The watcher
waits for each new file in the capture folder to stop growing, then moves it into
`YYYY-MM-DD/HH/` (24-hour, from the file's creation time) and copies it to the clipboard.

It is a compiled binary because macOS hides the Desktop from scripts launchd starts. Errors
are logged to `~/.local/state/screen-capture-sorter/error.log`.
