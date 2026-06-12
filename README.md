# NekoRun

A tiny macOS menu-bar utility that uploads dropped files to an SSH host via `scp` and optionally runs a post-upload shell command. The cat in the menu bar is the drop target.

Everything is user-configured — no host, path, or command is baked into the binary.

## Features

- **Menu-bar only** — no Dock icon, no main window. The cat lives in your menu bar.
- **Drag-and-drop upload** — drop any file or folder onto the cat to `scp -r` it to the configured host and remote directory.
- **Configurable destination** — *Set Upload Destination…* pops a two-field alert for `user@hostname` + remote path; both persist in `UserDefaults`.
- **Post-upload hook** — optional shell command that runs locally after `scp` succeeds. Useful for `ssh host chmod -R …`, local cleanup, notifications, etc.
- **Animated icon during upload** — the cat alternates between two expressions every 500 ms while `scp` and the hook are running, so you always know something's in flight.
- **Hover state** — the cat opens its eyes wider when you mouse over it (real-time mouse-position tracking, not alpha-hit-tested, so it doesn't flicker on the icon's transparent pixels).
- **Template icons** — both the default and hover cats are registered as template images, so macOS auto-tints them for light and dark menu bars.
- **Classic bomb dialog on failure** — `scp` or hook failures surface in an `NSAlert` with a hand-drawn Mac OS 6 bomb icon and the verbatim stderr/stdout.
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

## Release a DMG (no Apple Developer Program required)

```
./scripts/release.sh
```

Produces `release/NekoRun-<version>.dmg` containing the `.app` plus an `/Applications` symlink (the classic drag-here layout). The app is ad-hoc signed, so downloaders will see *"macOS cannot verify that this app is free from malware"* on first launch; they need to open **System Settings → Privacy & Security** and click **Open Anyway**. Subsequent launches are silent.

To uninstall: drag `NekoRun.app` to the Trash. Preferences left behind at `~/Library/Preferences/com.twobuttz.NekoRun.plist` can optionally be removed with `defaults delete com.twobuttz.NekoRun`.

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

## How it works

- SwiftUI's `MenuBarExtra` creates an `NSStatusItem` whose button is an `NSStatusBarButton`. `MenuBarDropInstaller` finds that button at launch and `object_setClass`'s it to `DropEnabledStatusBarButton` (no stored properties added, so the instance size is unchanged).
- Drag events are dispatched by AppKit to the button (which is now our subclass). On drop, file URLs are read from the pasteboard and `Uploader.upload` is kicked off in a detached task.
- `Uploader.upload` invokes `/usr/bin/scp -r <files> <user@host>:<dir>/`; if that succeeds and a post-upload hook is set, it runs the hook via `/bin/sh -c`. stdout/stderr are captured; non-zero exits surface in the bomb dialog.
- The cat's hover swap is driven by `NSEvent.addLocalMonitorForEvents` + `addGlobalMonitorForEvents` comparing the cursor's screen location to the button's screen frame. This bypasses `NSStatusBarButton`'s alpha-based hit testing, which would otherwise fire spurious mouse-exited events whenever the cursor crosses a transparent pixel of the cat.
- The image setter is overridden to coerce any external write (SwiftUI relayout, AppKit internals) back to whichever variant the hover / upload state currently wants — preventing flicker.
- During an upload, a 500 ms `Timer` toggles a phase bit and re-applies the image. Begin/end calls are ref-counted, so overlapping uploads keep the animation running until the last one finishes.

## Notes

- Both `scp` and the optional hook run with whatever environment macOS gives child processes of GUI apps. If you depend on shell config (e.g. `~/.zshrc` aliases), invoke the binary directly or wrap with `bash -lc`.
- If `scp` reports `connect ... Operation timed out` or `Undefined error: 0`, you're probably missing the Local Network grant — check System Settings → Privacy & Security → Local Network.
- Drops to a remote directory overwrite remote files of the same name silently (default `scp` behavior).
- Persisted keys in `UserDefaults`: `UploadDestinationHost`, `UploadDestinationDirectory`, `PostUploadCommand`.

## License

[MIT](LICENSE) — © 2026 Noah Tsutsui.
