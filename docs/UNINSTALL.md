# Removing ShotZ completely (before a clean-install test)

A checklist of every place ShotZ, ShotZ Dev and the older "Shotz" spellings leave something on a
Mac, with a command to **inspect** each one and, separately, a command to **remove** it. Paths and
identifiers are taken from the code (`ShotzCore/ShotzPaths.swift`, `ShotzCore/AppVariant.swift`,
`scripts/bundle.sh`, `scripts/install.sh`, `scripts/run.sh`, the test suites), not from memory.

Nothing here runs by itself. Read each step, inspect first, then remove what you mean to remove.

> **Your captures live in `~/Library/Application Support/Shotz/`** (step 3). Copy out anything you
> want to keep before removing that folder. Files you exported or saved (default `~/Desktop`) are
> ordinary files and are not touched by anything below.

## Names at a glance

| | ShotZ (installed) | ShotZ Dev (built by `scripts/run.sh`) |
|---|---|---|
| App | `/Applications/ShotZ.app` (older: `/Applications/Shotz.app`) | `<repo>/build/ShotZ Dev.app` (older: `Shotz Dev.app`) |
| Bundle id / defaults domain | `app.shotz.Shotz` | `app.shotz.Shotz.dev` |
| Test-run defaults suite | `app.shotz.Shotz.testrun` | `app.shotz.Shotz.dev.testrun` |
| Data folder (Application Support) | `Shotz` | `ShotZ Dev` |
| Test-run data folder | `ShotZ Test Runs` | `ShotZ Dev Test Runs` |
| Temp folder (`$TMPDIR`) | `Shotz`, `ShotZ Test Runs` | `ShotZ Dev`, `ShotZ Dev Test Runs` |
| Log subsystem | `app.shotz.Shotz` (both) | |

Older names still possibly on disk: the dev profile used before the variants landed
(`~/Library/Application Support/Shotz-Dev`, `$TMPDIR/Shotz-Dev`, defaults suite
`app.shotz.Shotz.dev`, now the dev app's own domain) and the pre-rename app names `Shotz.app` /
`Shotz Dev.app`. On the default case-insensitive APFS disk, `Shotz.app` and `ShotZ.app` (or
`Shotz Dev` and `ShotZ Dev`) are the same folder.

## 0. Quit and switch off launch at login first

Inspect:
```bash
pgrep -fl "ShotZ.app|Shotz.app|ShotZ Dev.app|Shotz Dev.app"
```
Remove:
1. In each app still installed, open Settings ▸ General and turn **Launch at login** off (this
   unregisters `SMAppService.mainApp` cleanly; deleting the app first leaves a stale entry).
2. Quit ShotZ and ShotZ Dev from their menus. Both executables are named `ShotZ` (builds from
   before the rename: `Shotz`), so `pkill -ix shotz` quits every copy at once, including dev
   builds running from the repo or a worktree.

## 1. Apps

Inspect:
```bash
ls -ld /Applications/ShotZ.app /Applications/Shotz.app /Applications/.ShotZ.app.* /Applications/.Shotz.app.* 2>/dev/null
mdfind "kMDItemCFBundleIdentifier == 'app.shotz.Shotz' || kMDItemCFBundleIdentifier == 'app.shotz.Shotz.dev'"
```
(`/Applications/.ShotZ.app.installing.*`, `.ShotZ.app.previous.*`, `.Shotz.app.previous.*` exist
only if an `install.sh` run was interrupted.)

Remove (to the Trash, so it stays recoverable until you empty it):
```bash
osascript -e 'tell application "Finder" to delete POSIX file "/Applications/ShotZ.app"'
```
Repeat for `/Applications/Shotz.app` and any hidden `.ShotZ.app.*` / `.Shotz.app.*` leftovers if
present, or drag them to the Trash in Finder (⇧⌘. shows hidden files).

## 2. Repository builds and worktrees

These are build products, not app data, but every one is a registered app and Spotlight finds it.

Inspect:
```bash
ls -d ~/Sites/shotz/build/*.app ~/Sites/shotz/build/.bundle-* 2>/dev/null
ls -d ~/Sites/shotz/.claude/worktrees/*/build/*.app 2>/dev/null
git -C ~/Sites/shotz worktree list
```
Remove:
- Apps in `build/`: `ShotZ.app`, `ShotZ Dev.app`, and the old `Shotz.app` / `Shotz Dev.app`
  (`scripts/bundle.sh` already deletes the old spelling when it rebuilds). Move them to the Trash.
- Worktrees: remove each finished worktree with `git -C ~/Sites/shotz worktree remove <path>` (it
  refuses if there are uncommitted changes), then `git -C ~/Sites/shotz worktree prune`.
- SwiftPM build caches (`.build/` in the repo and in each worktree) can go too; `swift build`
  recreates them.

## 3. Application Support (captures, history, editable documents)

Each folder holds `Captures/` (original PNGs), `Documents/` (editable annotations) and
`history.json` (`ShotzPaths.captures`, `.documents`, `.historyIndex`).

Inspect:
```bash
ls -ld ~/Library/Application\ Support/{Shotz,"ShotZ Dev","ShotZ Test Runs","ShotZ Dev Test Runs",Shotz-Dev} 2>/dev/null
du -sh ~/Library/Application\ Support/{Shotz,"ShotZ Dev","ShotZ Test Runs","ShotZ Dev Test Runs",Shotz-Dev} 2>/dev/null
```
Remove (move to the Trash; one line per folder):
```bash
osascript -e 'tell application "Finder" to delete POSIX file "'"$HOME"'/Library/Application Support/Shotz"'
```
- `Shotz`: the installed app's captures and history. **Back up first if you want them.**
- `ShotZ Dev`: the development app's data.
- `ShotZ Test Runs`, `ShotZ Dev Test Runs`: hermetic engineer and test launches; safe to remove.
- `Shotz-Dev`: the old dev profile; safe to remove.

## 4. Preferences (defaults domains)

Inspect:
```bash
for d in app.shotz.Shotz app.shotz.Shotz.dev app.shotz.Shotz.testrun app.shotz.Shotz.dev.testrun; do
  echo "== $d"; defaults read "$d" 2>/dev/null | head -20
done
ls ~/Library/Preferences | grep -iE '^app\.shotz|^Shotz'
```
The last line also lists throw-away suites left by `swift test` runs (`ShotzTests-…`,
`ShotzQATests-…`, `ShotzEditorTests-…`, `ShotzAppShellTests-…`, `ShotzVariantTests-…`,
`ShotzRenameTests-…`, each followed by a UUID).

Remove:
```bash
for d in app.shotz.Shotz app.shotz.Shotz.dev app.shotz.Shotz.testrun app.shotz.Shotz.dev.testrun; do
  defaults delete "$d" 2>/dev/null
done
```
For the test suites, delete each by name (they are only test data):
```bash
ls ~/Library/Preferences | grep -E '^Shotz[A-Za-z]*Tests-' | sed 's/\.plist$//' | while read -r d; do defaults delete "$d"; done
```
Use `defaults delete` rather than deleting `.plist` files: `cfprefsd` caches preferences and would
write a deleted file back.

## 5. Caches, saved state, HTTP storage

ShotZ does not create these on purpose, but macOS may on the app's behalf.

Inspect:
```bash
ls -ld ~/Library/Caches/app.shotz.Shotz* ~/Library/Saved\ Application\ State/app.shotz.Shotz* ~/Library/HTTPStorages/app.shotz.Shotz* 2>/dev/null
```
Remove: move whatever the listing shows to the Trash (Finder ▸ Go ▸ Go to Folder… `~/Library/Caches`
and so on).

## 6. Temporary files

Drag-out copies and in-flight capture files live under the user temp directory
(`ShotzPaths.temporary`, `.dragExports`); ShotZ removes old drag copies itself after a day.

Inspect:
```bash
ls -ld "$TMPDIR"Shotz "$TMPDIR"Shotz-Dev "$TMPDIR""ShotZ Dev" "$TMPDIR""ShotZ Test Runs" "$TMPDIR""ShotZ Dev Test Runs" 2>/dev/null
ls -d "$TMPDIR"Shotz*Tests-* 2>/dev/null   # leftovers from interrupted test runs
```
Remove: these folders are scratch space; move them to the Trash, or leave them: macOS clears
`$TMPDIR` periodically and on restart.

## 7. Screen Recording permission (TCC)

Each bundle id has its own entry; resetting it means the next launch asks again.

Inspect: System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording (look for ShotZ and
ShotZ Dev). From Terminal this needs Full Disk Access, so the Settings pane is easier.

Remove:
```bash
tccutil reset ScreenCapture app.shotz.Shotz
tccutil reset ScreenCapture app.shotz.Shotz.dev
```
Or select the entry in the Settings pane and click −. Don't run `tccutil reset ScreenCapture`
without a bundle id: that resets the permission for every app.

## 8. Login items and background items

Inspect: System Settings ▸ General ▸ Login Items & Extensions (look for ShotZ / ShotZ Dev), or:
```bash
sfltool dumpbtm | grep -i -B2 -A6 shotz   # asks for an administrator password
```
Remove: turn it off in ShotZ's own Settings while the app is still installed (step 0), or click −
in the Login Items pane. Avoid `sfltool resetbtm`: it resets the login and background items of
every app.

## 9. Launch Services registrations

Every `ShotZ.app` / `ShotZ Dev.app` ever built (including in worktrees) registers with Launch
Services; stale registrations show up in "Open With" and can confuse which copy opens.

Inspect:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -iE '^path:.*(ShotZ|Shotz).*\.app' | sort -u
```
Remove: unregister each path the dump lists (works even if the folder is already gone):
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/path/from/the/dump/ShotZ Dev.app"
```
Avoid `lsregister -kill`: it rebuilds the database for every app.

## 10. Logs and crash reports

Inspect:
```bash
log show --last 1d --info --predicate 'subsystem == "app.shotz.Shotz"' | tail -50
ls ~/Library/Logs/DiagnosticReports | grep -iE 'shotz'
```
Remove:
- Unified log entries can't be removed per app; they age out on their own. (`sudo log erase --all`
  erases the logs of every app; not recommended.)
- Crash reports: move the `ShotZ…` / `Shotz…` `.ips` files listed above to the Trash.

## 11. Sparkle (once updates ship)

Not present yet: engineer A is adding Sparkle. When it lands, verify against the code and fill in.
Sparkle normally keeps downloaded updates under `~/Library/Caches/app.shotz.Shotz/` (covered by
step 5) and its settings as `SU…` keys in the `app.shotz.Shotz` defaults domain (covered by step 4).

## 12. Empty the Trash and check

After emptying the Trash, these should all come back empty:
```bash
mdfind "kMDItemCFBundleIdentifier == 'app.shotz.Shotz' || kMDItemCFBundleIdentifier == 'app.shotz.Shotz.dev'"
ls ~/Library/Application\ Support | grep -iE 'shotz'
ls ~/Library/Preferences | grep -iE 'shotz'
```
Then install the release build fresh (`docs/INSTALL.md`) for the clean-install test.
