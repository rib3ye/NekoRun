# NekoRun

A tiny macOS menu-bar utility that uploads dropped files to an SSH host via `scp` and optionally runs a post-upload shell command. The cat in the menu bar is the drop target.

Everything is user-configured — no host, path, or command is baked into the binary.

## Features

- **Menu-bar only** — no Dock icon, no main window. The cat lives in your menu bar.
- **Drag-and-drop upload** — drop any file or folder onto the cat to `scp -r` it to the configured host and remote directory.
- **Configurable destination** — *Set Upload Destination…* pops a two-field alert for `user@hostname` + remote path; both persist in `UserDefaults`.
- **Post-upload hook** — optional shell command that runs locally after `scp` succeeds. Useful for `ssh host chmod -R …`, local cleanup, notifications, etc.
- **Launch at Login** — toggleable via `SMAppService.mainApp` (macOS 13+).

## Requirements

- macOS 13 or later (`MenuBarExtra`, `SMAppService`, `@Observable`).
- Xcode 16+ recommended.
- **SSH key-based auth** to the destination host. There is no password UI; `scp`/`ssh` are spawned non-interactively.
- **Local Network permission** if the destination is on your LAN. macOS Sequoia will prompt on first upload; the entry can be flipped on/off in System Settings → Privacy & Security → Local Network.

## Build & Install

1. Open `NekoRun.xcodeproj` in Xcode.
2. **Product → Archive**.
3. In Organizer → **Distribute App → Custom → Copy App** → export to Desktop.
4. Drag the exported `NekoRun.app` into `/Applications`.
5. Launch from Applications. Click the cat → **Set Upload Destination…** to configure host + path. Optionally **Set Post-Upload Hook…**. Toggle **Launch at Login** if you want it to start on boot.

## Project Settings (worth knowing)

- **App Sandbox: OFF** — required so `/usr/bin/scp` and `/usr/bin/ssh` can read `~/.ssh/config`, `known_hosts`, and your keys.
- **LSUIElement = YES** — strips the Dock icon so it's pure menu bar.
- **`NSLocalNetworkUsageDescription`** — set in the target's Info build settings; triggers the macOS Local Network prompt the first time the app reaches a LAN address.
- **Hardened Runtime: ON** — left enabled; doesn't block ssh.

## Files

| File | Purpose |
| --- | --- |
| `NekoRunApp.swift` | `MenuBarExtra` scene + `AppDelegate` adaptor that installs the drop target at launch. |
| `ContentView.swift` | The dropdown menu (destination, hook, Launch at Login, Quit). |
| `Uploader.swift` | Runs `scp` and the optional post-upload hook; owns `UploadDestinationStore` and `PostUploadCommandStore`; defines the bomb-icon failure alert and the destination/hook editors. |
| `DropEnabledStatusBarButton.swift` | `NSStatusBarButton` subclass (applied via `object_setClass`) that handles file drops, drives the hover-image swap from `NSEvent` mouse-position monitors, and animates the icon during upload. |
| `MenuBarDropInstaller.swift` | Walks `NSApp.windows` after launch to find the status-bar button SwiftUI's `MenuBarExtra` creates, swizzles its class, registers it for `fileURL` drags, and starts hover monitoring. |
| `LoginItemManager.swift` | Wraps `SMAppService.mainApp` for the Launch-at-Login toggle. |
| `Assets.xcassets/MenuBarIcon.imageset/` | Default cat (template image). |
| `Assets.xcassets/MenuBarIconHover.imageset/` | Hover / animation cat (template image). |

## Notes

- Both `scp` and the optional hook run with whatever environment macOS gives child processes of GUI apps. If you depend on shell config (e.g. `~/.zshrc` aliases), invoke the binary directly or wrap with `bash -lc`.
- If `scp` reports `connect ... Operation timed out` or `Undefined error: 0`, you're probably missing the Local Network grant — check System Settings → Privacy & Security → Local Network.
- Drops to a remote directory overwrite remote files of the same name silently (default `scp` behavior).
- Persisted keys in `UserDefaults`: `UploadDestinationHost`, `UploadDestinationDirectory`, `PostUploadCommand`.

## License

[MIT](LICENSE) — © 2026 Noah Tsutsui.
