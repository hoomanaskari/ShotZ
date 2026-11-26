# Contributing to ShotZ

Bug reports and fixes are welcome. For anything bigger than a fix, please open an issue first so we can agree on the approach. ShotZ's Phase 1 scope is still screenshots (see [docs/SPEC.md](docs/SPEC.md)).

## Build and test

You need Xcode 16 or later (Swift 6) on macOS 15 or later.

```bash
swift build        # must finish without warnings
swift test         # all tests must pass
scripts/run.sh     # build and run ShotZ Dev
```

ShotZ Dev is a separate app from ShotZ (its own bundle id, settings, captures and Screen Recording permission, default shortcuts ⌃⌥⌘3/4/5), so you can work on it with your installed ShotZ still running. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §8 lists the debug launch arguments for exercising the stack and the editor without capturing your screen.

### Screenshots

`scripts/screenshots/make-screenshots.sh` rebuilds the README screenshots from ShotZ Dev, using synthetic sample images. Its last step, `compose.py`, needs [Pillow](https://pypi.org/project/pillow/) (`python3 -m pip install pillow`).

## Conventions

The full list is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §10. The ones that matter most:

- **Swift 6 with strict concurrency.** UI types are `@MainActor`. No force unwraps outside tests. Don't swallow errors with `try?` unless the failure really doesn't matter, and say why in a comment.
- **AppKit in code**, no storyboards or xibs. `public` only for what another module needs. One type per file, files under about 400 lines.
- **Modules depend only downwards** (ARCHITECTURE §1). Modules talk to each other through `ShotzCore` protocols, wired up in `AppCoordinator`.
- **Logging with `os.Logger`**, no `print`. **No analytics and no network access** besides the update check.
- **User-facing text** through `String(localized:)`.
- **Use the design system.** Every control, colour, font, gap and icon comes from `ShotzUI` and `ShotzIcon` ([docs/DESIGN.md](docs/DESIGN.md)). Don't style stock AppKit controls, use colour literals or SF Symbols, or draw your own controls. If something is missing, add it to `ShotzUI` first.
- **Original work only.** Don't copy icons, sounds, text or layouts from other apps.
- **Tests must not disturb whoever is using the Mac.** Never post synthetic global keyboard or mouse events, and never bring ShotZ to the front uninvited. Drive features through debug launch arguments and in-process hooks, and use synthetic test images, not real screenshots.
- **Commits** are small, with an imperative subject naming the module, e.g. `QuickAccess: add drag-out`.

## Pull requests

Rebase on `main`, run `swift build` and `swift test`, and try the change in ShotZ Dev. Describe what changed and how you checked it. For visible changes, include before and after screenshots of ShotZ Dev.
