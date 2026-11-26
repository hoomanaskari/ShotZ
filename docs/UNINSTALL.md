# Removing ShotZ completely (before a clean-install test)

A checklist of every place ShotZ, ShotZ Dev and the older "Shotz" spellings leave something on a
Mac, with a command to **inspect** each one and, separately, a command to **remove** it. It covers
**both generations of identifiers**, all verified against the code (`ShotzCore/AppVariant.swift`,
`ShotzCore/ShotzPaths.swift`, `ShotzCore/ShotzLog.swift`, `AppShell/System/LegacyDataMigration.swift`,
`scripts/bundle.sh`, `scripts/install.sh`, `scripts/run.sh`, the test suites):

- **Current ids** `com.pixelforty.shotz` (ShotZ) and `com.pixelforty.shotz.dev` (ShotZ Dev).
- **Earlier ids** `app.shotz.Shotz` and `app.shotz.Shotz.dev`, used by builds before the change.
  On first launch, `LegacyDataMigration` **moves** the old data folder into the new one, leaves only
  a `MIGRATED.txt` note in the old folder, and copies ShotZ's settings into the new preferences
  domain; the **old preferences domains are left untouched**.

A Mac that ran builds from both generations has leftovers from both; remove both.

Nothing here runs by itself. Read each step, inspect first, then remove what you mean to remove.

> **Your captures live in `~/Library/Application Support/com.pixelforty.shotz/`** (step 3); on a Mac
> where a current build has not run yet they are still in `~/Library/Application Support/Shotz/`.
> Copy out anything you want to keep before removing those folders. Files you exported or saved (default
> `~/Desktop`) are ordinary files and are not touched by anything below.

## Names at a glance

| | ShotZ (installed) | ShotZ Dev (built by `scripts/run.sh`) |
|---|---|---|
| App | `/Applications/ShotZ.app` (older: `/Applications/Shotz.app`) | `<repo>/build/ShotZ Dev.app` (older: `Shotz Dev.app`) |
| Bundle id / defaults domain | `com.pixelforty.shotz` | `com.pixelforty.shotz.dev` |
| Test-run defaults suite | `com.pixelforty.shotz.testrun` | `com.pixelforty.shotz.dev.testrun` |
| Data folder (`~/Library/Application Support/…`) | `com.pixelforty.shotz` | `com.pixelforty.shotz.dev` |
| Test-run data folder | `com.pixelforty.shotz.testrun` | `com.pixelforty.shotz.dev.testrun` |
| Temp folders (`$TMPDIR`) | `com.pixelforty.shotz`, `…shotz.testrun` | `com.pixelforty.shotz.dev`, `…dev.testrun` |
| Log subsystem | `com.pixelforty.shotz` (both apps) | |
| **Earlier** bundle id / defaults domain | `app.shotz.Shotz` | `app.shotz.Shotz.dev` |
| **Earlier** test-run suite | `app.shotz.Shotz.testrun` | `app.shotz.Shotz.dev.testrun` |
| **Earlier** data folder | `Shotz` (after migration: only `MIGRATED.txt`) | `ShotZ Dev` (same) |
| **Earlier** test-run data folder | `ShotZ Test Runs` | `ShotZ Dev Test Runs` |
| **Earlier** temp folders | `Shotz`, `ShotZ Test Runs` | `ShotZ Dev`, `ShotZ Dev Test Runs` |
| **Earlier** log subsystem | `app.shotz.Shotz` | |

Test-run folders and suites are never migrated: the earlier ones simply stay behind. A migration that
was interrupted can leave a staging folder `com.pixelforty.shotz.migrating` (or `….dev.migrating`)
next to the data folder; the next launch discards and redoes it.

Older still: the dev profile used before the variants landed
(`~/Library/Application Support/Shotz-Dev`, `$TMPDIR/Shotz-Dev`) and the pre-rename app names
`Shotz.app` / `Shotz Dev.app`. On the default case-insensitive APFS disk, `Shotz.app` and
`ShotZ.app` (or `Shotz Dev` and `ShotZ Dev`) are the same folder.

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
mdfind "kMDItemCFBundleIdentifier == 'app.shotz.Shotz' || kMDItemCFBundleIdentifier == 'app.shotz.Shotz.dev' || kMDItemCFBundleIdentifier == 'com.pixelforty.shotz' || kMDItemCFBundleIdentifier == 'com.pixelforty.shotz.dev'"
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
ls -ld ~/Library/Application\ Support/com.pixelforty.shotz* 2>/dev/null   # current ids (incl. .testrun, .migrating)
cat ~/Library/Application\ Support/Shotz/MIGRATED.txt 2>/dev/null           # where the earlier data went
ls -ld ~/Library/Application\ Support/{Shotz,"ShotZ Dev","ShotZ Test Runs","ShotZ Dev Test Runs",Shotz-Dev} 2>/dev/null
du -sh ~/Library/Application\ Support/{com.pixelforty.shotz,com.pixelforty.shotz.dev,Shotz,"ShotZ Dev","ShotZ Test Runs","ShotZ Dev Test Runs",Shotz-Dev} 2>/dev/null
```
Remove (move to the Trash; one line per folder):
```bash
osascript -e 'tell application "Finder" to delete POSIX file "'"$HOME"'/Library/Application Support/Shotz"'
```
- `com.pixelforty.shotz`: the installed app's captures, documents and history. **Back up first.**
- `com.pixelforty.shotz.dev`, `com.pixelforty.shotz.testrun`, `com.pixelforty.shotz.dev.testrun`, and
  any `….migrating` staging folder: the development app, test runs, an interrupted migration.
- `Shotz`: after migration it holds only `MIGRATED.txt` and can go. If it still holds `Captures/`
  and `history.json`, no current build has run yet (or the migration failed and left the data in
  place, as designed): **back up first if you want them.**
- `ShotZ Dev`: the earlier development app's data (after migration: only `MIGRATED.txt`).
- `ShotZ Test Runs`, `ShotZ Dev Test Runs`: hermetic engineer and test launches; safe to remove.
- `Shotz-Dev`: the old dev profile; safe to remove.

## 4. Preferences (defaults domains)

Inspect:
```bash
for d in com.pixelforty.shotz com.pixelforty.shotz.dev com.pixelforty.shotz.testrun com.pixelforty.shotz.dev.testrun \
         app.shotz.Shotz app.shotz.Shotz.dev app.shotz.Shotz.testrun app.shotz.Shotz.dev.testrun; do
  echo "== $d"; defaults read "$d" 2>/dev/null | head -20
done
ls ~/Library/Preferences | grep -iE '^com\.pixelforty\.shotz|^app\.shotz|^Shotz'
```
The last line also lists throw-away suites left by `swift test` runs (`ShotzTests-…`,
`ShotzQATests-…`, `ShotzEditorTests-…`, `ShotzAppShellTests-…`, `ShotzVariantTests-…`,
`ShotzRenameTests-…`, each followed by a UUID).

Remove:
```bash
for d in com.pixelforty.shotz com.pixelforty.shotz.dev com.pixelforty.shotz.testrun com.pixelforty.shotz.dev.testrun \
         app.shotz.Shotz app.shotz.Shotz.dev app.shotz.Shotz.testrun app.shotz.Shotz.dev.testrun; do
  defaults delete "$d" 2>/dev/null
done
```
For the test suites, delete each by name (they are only test data):
```bash
ls ~/Library/Preferences | grep -E '^Shotz[A-Za-z]*Tests-' | sed 's/\.plist$//' | while read -r d; do defaults delete "$d"; done
```
The migration copies ShotZ's settings into the new domain and leaves the `app.shotz.Shotz…` domains
as they were, so both generations show up here. Use `defaults delete` rather than deleting `.plist`
files: `cfprefsd` caches preferences and would
write a deleted file back.

## 5. Caches, saved state, HTTP storage

ShotZ does not create these on purpose, but macOS may on the app's behalf.

Inspect:
```bash
ls -ld ~/Library/Caches/{app.shotz.Shotz,com.pixelforty.shotz}* \
       ~/Library/Saved\ Application\ State/{app.shotz.Shotz,com.pixelforty.shotz}* \
       ~/Library/HTTPStorages/{app.shotz.Shotz,com.pixelforty.shotz}* 2>/dev/null
```
Remove: move whatever the listing shows to the Trash (Finder ▸ Go ▸ Go to Folder… `~/Library/Caches`
and so on).

## 6. Temporary files

Drag-out copies and in-flight capture files live under the user temp directory
(`ShotzPaths.temporary`, `.dragExports`); ShotZ removes old drag copies itself after a day.

Inspect:
```bash
ls -ld "$TMPDIR"Shotz "$TMPDIR"Shotz-Dev "$TMPDIR""ShotZ Dev" "$TMPDIR""ShotZ Test Runs" "$TMPDIR""ShotZ Dev Test Runs" 2>/dev/null
ls -ld "$TMPDIR"com.pixelforty.shotz* 2>/dev/null   # current ids
ls -d "$TMPDIR"Shotz*Tests-* 2>/dev/null   # leftovers from interrupted test runs
```
Remove: these folders are scratch space; move them to the Trash, or leave them: macOS clears
`$TMPDIR` periodically and on restart.

## 7. Screen Recording permission (TCC)

Each bundle id has its own entry; resetting it means the next launch asks again.

Inspect: System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording (look for ShotZ and
ShotZ Dev). From Terminal this needs Full Disk Access, so the Settings pane is easier.

Remove (one command per bundle id; run only the ones whose entry exists):
```bash
tccutil reset ScreenCapture com.pixelforty.shotz
tccutil reset ScreenCapture com.pixelforty.shotz.dev
tccutil reset ScreenCapture app.shotz.Shotz
tccutil reset ScreenCapture app.shotz.Shotz.dev
```
A permission granted to an earlier id does not carry over: after the id change ShotZ asks for Screen
Recording again, and the earlier entry stays in the list until reset.
Or select the entry in the Settings pane and click −. Don't run `tccutil reset ScreenCapture`
without a bundle id: that resets the permission for every app.

## 8. Login items and background items

Inspect: System Settings ▸ General ▸ Login Items & Extensions (look for ShotZ / ShotZ Dev), or:
```bash
sfltool dumpbtm | grep -i -B2 -A6 -E 'shotz|pixelforty'   # asks for an administrator password
```
Remove: turn it off in ShotZ's own Settings while the app is still installed (step 0), or click −
in the Login Items pane. Each bundle id registers its own login item, so after the id change there
can be two ShotZ entries (earlier and current); remove the stale one. Avoid `sfltool resetbtm`: it resets the login and background items of
every app.

## 9. Launch Services registrations

Every `ShotZ.app` / `ShotZ Dev.app` ever built (including in worktrees) registers with Launch
Services; stale registrations show up in "Open With" and can confuse which copy opens.

Inspect:
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -iE '^path:.*(ShotZ|Shotz).*\.app' | sort -u
```
The app names are the same in both generations, so this one search finds builds of either; the
dump's `identifier:` lines show which bundle id each one has.

Remove: unregister each path the dump lists (works even if the folder is already gone):
```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/path/from/the/dump/ShotZ Dev.app"
```
Avoid `lsregister -kill`: it rebuilds the database for every app.

## 10. Logs and crash reports

Inspect:
```bash
log show --last 1d --info --predicate 'subsystem == "com.pixelforty.shotz" OR subsystem == "app.shotz.Shotz"' | tail -50
ls ~/Library/Logs/DiagnosticReports | grep -iE 'shotz'
```
Remove:
- Unified log entries can't be removed per app; they age out on their own. (`sudo log erase --all`
  erases the logs of every app; not recommended.)
- Crash reports: move the `ShotZ…` / `Shotz…` `.ips` files listed above to the Trash.

## 11. Sparkle (software updates)

ShotZ (production only) embeds Sparkle; its feed and key settings are in `Resources/Info.plist` and
`scripts/bundle.sh`. Where Sparkle keeps things is Sparkle's own convention, not ShotZ code:

Inspect:
```bash
ls -ld ~/Library/Caches/com.pixelforty.shotz/org.sparkle-project.Sparkle 2>/dev/null   # downloaded updates
defaults read com.pixelforty.shotz 2>/dev/null | grep -E '^ *"?SU'                      # Sparkle's own settings
```
Remove: the cache folder goes with step 5 (`~/Library/Caches/com.pixelforty.shotz`), and the `SU…`
settings go with the domain in step 4. ShotZ Dev has no updater.

## 12. Empty the Trash and check

After emptying the Trash, these should all come back empty:
```bash
mdfind "kMDItemCFBundleIdentifier == 'app.shotz.Shotz' || kMDItemCFBundleIdentifier == 'app.shotz.Shotz.dev' || kMDItemCFBundleIdentifier == 'com.pixelforty.shotz' || kMDItemCFBundleIdentifier == 'com.pixelforty.shotz.dev'"
ls ~/Library/Application\ Support | grep -iE 'shotz'
ls ~/Library/Preferences | grep -iE 'shotz'
ls ~/Library/Caches ~/Library/Saved\ Application\ State | grep -iE 'shotz'
```
Then install the release build fresh (`docs/INSTALL.md`) for the clean-install test.
