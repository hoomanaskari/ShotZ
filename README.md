# Shotz

Shotz is an original, open-source macOS screenshot and annotation app. It is a
menu-bar agent: a global shortcut captures the screen, the capture appears in
a quick-access stack of thumbnail cards, and one click opens it in an
annotation editor. It is native Swift 6, AppKit-first, built for macOS 15 and
later, with no third-party dependencies, no network access and no telemetry.

- Behaviour: [docs/SPEC.md](docs/SPEC.md)
- Structure, module contracts and conventions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Phase 1 scope

- Still screenshots: area, window, fullscreen and all-in-one, driven by the
  system `screencapture` tool behind a `CaptureEngine` protocol.
- Global shortcuts ⌘⇧3 / ⌘⇧4 / ⌘⇧5 (rebindable).
- The quick-access stack: copy, save, drag out, annotate, Quick Look, close.
- The annotation editor: arrows, shapes, text, highlighter, blur/pixelate,
  counters, pen, crop and presentation backgrounds, with full undo.
- History of recent captures under `~/Library/Application Support/Shotz/`.

Out of scope for Phase 1: video/GIF recording, scrolling capture, OCR, cloud
upload, pinning.

The repository currently holds the foundation: the `ShotzCore` contracts,
settings and export service, the `AnnotationKit` document model, and small
working stubs for the other modules wired end to end.

## Build, run, test

Requires Xcode 16 or later (Swift 6 toolchain) on macOS 15 or later.

```bash
swift build                          # debug build of all modules
swift test                           # all unit tests
scripts/bundle.sh [debug|release]    # → build/Shotz.app (Info.plist, icon, codesign)
scripts/run.sh [--dev-hotkeys] [app args…]   # bundle (debug) and launch; quits a previous instance of this bundle only; worktrees: adds --dev-profile, direct exec
scripts/install.sh                   # release bundle → /Applications/Shotz.app (manager/owner only)
swift scripts/make-sample.swift <w> <h> <out.png>   # synthetic test PNG
```

### Debug launch arguments

To exercise the stack and editor without Screen Recording permission, make a
sample image and pass it to the app (`run.sh` passes arguments through and
makes file paths absolute):

```bash
swift scripts/make-sample.swift 5120 2880 build/sample-5k.png
```

```bash
scripts/run.sh --dev-profile --dev-hotkeys --debug-present build/sample-5k.png
```

```bash
scripts/run.sh --dev-profile --dev-hotkeys --debug-edit build/sample-5k.png
```

- `--debug-present <png> [<png>…]` copies each image into the captures folder,
  adds it to history (kind area, scale 2) and shows it in the quick-access stack.
- `--debug-edit <png>` opens the image in the editor.
- `--debug-edit-capture <png>` imports the image into history like
  `--debug-present`, then opens it as a capture (`openEditor(for:)`), so edits
  and Save's export overwrite persist. The same source path always maps to the
  same history entry, so a second launch reopens that capture instead of
  importing again (it is re-imported, under the same id, only if its file is
  gone). `--debug-capture-id <uuid>` forces the id.

### Dev profile (required for every engineer and test launch)

`--dev-profile` (or `SHOTZ_DEV_PROFILE=1`) runs Shotz with its own
preferences (`UserDefaults` suite `app.shotz.Shotz.dev`) and its own data
(`~/Library/Application Support/Shotz-Dev`, temp folder `Shotz-Dev`), so a
test run never touches the owner's settings, onboarding state, history or
captures. Any `--debug-*` argument, `SHOTZ_EDITOR_SCRIPT` or
`-QuickAccessSelfTest` switches it on as well. The bundle id stays
`app.shotz.Shotz`, so the Screen Recording grant still applies, and
argument-domain overrides such as `-quickAccess.side right` keep working. The
first log line after launch says which profile is active.

Rules for engineers and test runs:

- Always launch with `--dev-profile`. From any git worktree, `scripts/run.sh`
  adds `--dev-profile` itself and starts the executable directly (not through
  Launch Services), so it never relaunches the wrong copy.
- Only run the bundle built in your own worktree. Never bundle, launch or quit
  `build/Shotz.app` in the main checkout: that is the owner's instance.

### Global shortcuts per run

`--dev-hotkeys` (or `SHOTZ_DEV_HOTKEYS=1`) replaces the capture shortcuts for
that run and never writes to preferences. In the dev profile Shotz registers
**no** global shortcuts unless `--dev-hotkeys` is given, and then a set no
other Shotz uses, so a test copy can never take a key press meant for the
owner's copy:

| Run | Capture fullscreen / area / all-in-one | Capture window, restore |
|---|---|---|
| standard | stored (⌘⇧3/4/5 by default) | stored |
| standard + `--dev-hotkeys` | ⌃⌥⌘3/4/5 | stored |
| dev profile | none | none |
| dev profile + `--dev-hotkeys` | ⌃⌥⇧⌘3/4/5 | none |

Settings ▸ Shortcuts shows the shortcut each action has in the current
session, and says so when none are registered. The launch log has a
`Hotkeys: …` line.

Signing: `bundle.sh` uses `$SHOTZ_SIGN_IDENTITY` if set, otherwise the first
"Apple Development" identity in the keychain, otherwise ad-hoc, with the same
rule for debug and release so the Screen Recording grant carries over. A
release build refuses ad-hoc signing unless `SHOTZ_ALLOW_ADHOC=1`, uses the
hardened runtime (checked after signing) and never contacts the network (no
secure timestamp). The version comes from `Resources/Info.plist`.

`install.sh` (owner/manager, main checkout only; it refuses to run from a
worktree) builds a release, stages and verifies the copy next to
`/Applications/Shotz.app`, quits only the installed copy (politely, then by
force after 5 s), swaps the new bundle in with two renames (the old copy is
restored if the swap fails) and relaunches Shotz if it was running.

The app icon is generated by `swift Resources/make-app-icon.swift`.

## Installing

See [docs/INSTALL.md](docs/INSTALL.md): installing into `/Applications`, the
Screen Recording permission, launch at login, freeing ⌘⇧3/4/5 and rolling back.

## Permissions

Shotz needs **Screen Recording** permission (System Settings ▸ Privacy &
Security ▸ Screen & System Audio Recording). Without it, a capture shows a
prompt explaining how to grant it instead of producing an empty image.
Signing with a stable identity keeps the grant across rebuilds; ad-hoc builds
may need to be re-approved after each rebuild.

For ⌘⇧3/4/5 to reach Shotz, macOS's own screenshot shortcuts (System Settings
▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots) must be turned off. Shotz only
reads that setting; it never changes system settings.

## License

MIT. See [LICENSE](LICENSE).
