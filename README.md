# screen-capture-sorter

Every macOS screenshot and screen recording you take is copied to the clipboard and filed by
day and hour. The newest day, and the newest hour inside it, start with `LATEST_` so the
latest capture is always one obvious click away:

```
~/Desktop/screen_capture/
├── 2026-11-18/
│   └── 23/
│       └── Screenshot 2026-11-18 at 23.41.07.png
└── LATEST_2026-11-19/
    ├── 09/
    │   └── Screenshot 2026-11-19 at 09.12.40.png
    └── LATEST_14/
        ├── Screenshot 2026-11-19 at 14.03.22.png
        └── Screen Recording 2026-11-19 at 14.10.05.mov
```

When a capture starts a new hour or day, the marker moves to the new folder and comes off
the old one. The prefix is `LATEST_` rather than `LATEST:` because Finder shows a colon in
a file name as `/`.

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

This stops the watcher, removes it, takes the `LATEST_` prefix off the folders and restores
your previous screenshot save location. Captures already filed are left where they are.

## How it works

`install.sh` points macOS's screenshot location (`defaults write com.apple.screencapture
location`) at the capture folder. It then compiles `main.swift` into
`~/.local/bin/screen-capture-sorter` and runs it at login with a launchd agent. The watcher
waits for each new file in the capture folder to stop growing, then moves it into
`YYYY-MM-DD/HH/` (24-hour, from the file's creation time), moves the `LATEST_` markers and
copies it to the clipboard. A capture back-dated to an earlier day goes into that day's folder
without taking the markers. Only folders named like a date or an hour are ever renamed.
If the capture folder is deleted, moved or put in the Trash, the watcher recreates it at once
so macOS always has somewhere to save the next capture.

It is a compiled binary because macOS hides the Desktop from scripts launchd starts. Errors
are logged to `~/.local/state/screen-capture-sorter/error.log`.
