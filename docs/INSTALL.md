# Installing ShotZ

How to install ShotZ into `/Applications`, move your shortcuts over to it, and
undo the install. Everything here happens on your Mac. The only time ShotZ
uses the network is to check for updates (see "Updates" below); ShotZ Dev
never does.

## 1. Install

The app is now called **ShotZ**. Installing replaces an existing
`/Applications/Shotz.app` (the old spelling) so only `/Applications/ShotZ.app`
remains.

ShotZ also has a new identity, `com.pixelforty.shotz` (it was `app.shotz.Shotz`).
The first time the new ShotZ starts, it brings your old setup across:

- **Settings:** your settings, including shortcuts and file-name pattern, are
  copied from the old app. The old copy of your settings stays where it was,
  unchanged.
- **History:** your captures, edits and history move from
  `~/Library/Application Support/Shotz` to
  `~/Library/Application Support/com.pixelforty.shotz`. The old folder keeps
  only a `MIGRATED.txt` note saying where everything went.

Because macOS sees a new app, you need to allow Screen Recording once more
(section 2). Launch at login is set up again for the new identity.

1. Quit any ShotZ you started from the checkout (`scripts/run.sh`): open
   Settings ▸ Advanced and click **Quit ShotZ**. If the menu-bar icon is shown,
   you can also choose **Quit ShotZ** from its menu.
2. In Terminal, from the main checkout (not a worktree), run:

   ```bash
   scripts/install.sh
   ```

   The script builds a signed release, checks it, and then replaces
   `/Applications/ShotZ.app` in one step. If something fails before that
   step, any existing copy is left as it was. It quits and relaunches only an
   already installed ShotZ. It also warns you if a ShotZ from the checkout is
   still running.
3. Open **ShotZ** from `/Applications` or Spotlight. With the menu-bar icon
   hidden, opening ShotZ again brings up its Settings.

## Updates

Once ShotZ is installed, new versions arrive through the app itself; you don't
need to run the install script again.

- ShotZ checks once a day by default. When a new version is found, **Update
  Available…** appears in the ShotZ menu; choose it to see what's new and install.
- **Check for Updates…** is in the ShotZ menu and in Settings ▸ Advanced ▸
  Updates, next to the switch for automatic checks and the date of the last check.
- Settings ▸ Advanced ▸ About shows the installed version and build.
- Updates keep ShotZ's identity, so the Screen Recording permission carries over.
- Every update is signed with ShotZ's own update key; ShotZ checks the
  signature against the public key built into the app and refuses anything
  that doesn't match.

## 2. Screen Recording permission

macOS ties the Screen Recording permission to the app's identity: its bundle
id and the certificate it was signed with. The first install with the new
identity (`com.pixelforty.shotz`) needs the permission **once more**. After
that, updates keep the same identity, so the permission is expected to carry
over. Check it after installing:

- **Check:** ShotZ Settings ▸ General ▸ Permissions shows **Allowed** next to
  Screen Recording.
- **If it shows Not allowed, or macOS asks again:**
  1. Click **Set Up…** next to Screen Recording, then **Open System
     Settings**. This opens Privacy & Security ▸ Screen & System Audio
     Recording.
  2. Turn **ShotZ** on. If ShotZ is listed twice (the old identity's entry
     stays in the list), remove both entries with **−**, then add
     `/Applications/ShotZ.app` with **+**.
  3. If macOS offers to quit and reopen ShotZ, choose **Later**. Then click
     **Relaunch ShotZ** in the ShotZ window.

## 3. Launch at login

The first time ShotZ runs from `/Applications`, it applies the choice you made
in the welcome window (on by default) and adds itself to your login items.
Builds run from the checkout never do this.

- **Check:** ShotZ Settings ▸ General ▸ **Launch at login**.
- If ShotZ says macOS needs you to allow it, click **Open Login Items…** and
  turn ShotZ on under System Settings ▸ General ▸ Login Items & Extensions.
- To stop it starting at login, turn the setting off in ShotZ, or turn ShotZ
  off in Login Items.

## 4. Freeing ⌘⇧3, ⌘⇧4 and ⌘⇧5

These shortcuts only reach ShotZ when nothing else claims them first.

- **macOS's own screenshot shortcuts:** System Settings ▸ Keyboard ▸ Keyboard
  Shortcuts… ▸ Screenshots. Untick the screenshot shortcuts there. They are
  already off on this Mac. ShotZ's welcome window checks this and lists any
  that are still on.
- **Your other screenshot app:** open its settings and clear or change its
  shortcuts for capturing the full screen, an area, and its all-in-one or
  capture-options mode. Or quit that app, and stop it from opening at login.
  If two apps share a shortcut, either one may get the key press.

## 5. Checking the shortcuts

The installed ShotZ uses the shortcuts saved in its Settings: ⌘⇧3, ⌘⇧4 and
⌘⇧5 unless you changed them. (The ShotZ you ran from the checkout before
used ⌃⌥⌘3/4/5. From now on those belong to ShotZ Dev; see step 8.)

- **Check:** ShotZ Settings ▸ Shortcuts lists the three shortcuts.
- A yellow warning next to a shortcut means ShotZ could not register it.
  Free it as described in step 4. macOS does not always report a shortcut
  that another app holds. So if a shortcut shows no warning but does nothing,
  another app may still be using it.
- To see what ShotZ registered, run this in Terminal. It prints one line per
  shortcut: `registered`, `FAILED (Carbon status …)` or `not registered`.

  ```bash
  log show --last 10m --style compact --predicate 'subsystem == "com.pixelforty.shotz"' | grep "Hotkey "
  ```

## 6. Clearing test history

Early builds may have left test captures (synthetic images) in ShotZ's
history.

- In ShotZ Settings ▸ Advanced, click **Clear History…**. This deletes the
  captures ShotZ keeps for itself and their edits. Files you saved or
  exported stay where they are.
- Older test builds kept their data in a folder you can delete:

  ```bash
  rm -rf ~/Library/Application\ Support/Shotz-Dev
  ```

## 7. Rolling back

1. In ShotZ Settings ▸ General, turn **Launch at login** off, so no login item
   is left behind.
2. In Settings ▸ Advanced, click **Quit ShotZ**.
3. Delete `/Applications/ShotZ.app`: drag it to the Bin, or run:

   ```bash
   rm -rf /Applications/ShotZ.app
   ```

4. If you changed your other screenshot app's shortcuts, change them back.

Your history (`~/Library/Application Support/com.pixelforty.shotz`) and settings
(preferences domain `com.pixelforty.shotz`) stay in place, ready for a later
reinstall. Delete them too if you want a clean slate. Leftovers from before the
identity change can go as well: the folder `~/Library/Application Support/Shotz`
(only `MIGRATED.txt` is left in it) and the preferences domain `app.shotz.Shotz`
(`defaults delete app.shotz.Shotz`). The Screen Recording entry for ShotZ can
be removed in Privacy & Security ▸ Screen & System Audio Recording with **−**.

## 8. Running the development build next to the installed app

`scripts/run.sh` builds and opens **ShotZ Dev**, a separate app built from the
same code for trying changes. It never touches your installed ShotZ, and
`scripts/install.sh` never touches ShotZ Dev.

- **Telling them apart:** ShotZ Dev's icon has an amber **DEV** band, and its
  menu-bar icon is amber.
- **Shortcuts:** ShotZ Dev uses ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5, so both apps can run
  at once.
- **Separate everything:** ShotZ Dev has its own settings, history
  (`~/Library/Application Support/com.pixelforty.shotz.dev`) and login item (off by default).
- **Screen Recording:** ShotZ Dev is a different app to macOS, so it needs its
  own permission. Grant it the first time you open ShotZ Dev normally (from
  Finder or with `scripts/run.sh` in the main checkout):
  1. The first time it captures, ShotZ Dev opens its permission step.
  2. Click **Open System Settings** and turn **ShotZ Dev** on.
  3. Click **Relaunch ShotZ Dev**.

  Until then, captures in ShotZ Dev show the permission step instead.
- **Quitting:** use ShotZ Dev's menu-bar icon, or Settings ▸ Advanced ▸
  **Quit ShotZ Dev**.
- **Removing it:**

  ```bash
  rm -rf "build/ShotZ Dev.app" ~/Library/Application\ Support/com.pixelforty.shotz.dev
  ```

  ```bash
  defaults delete com.pixelforty.shotz.dev
  ```

  ShotZ Dev's data from before the identity change moves the same way, from
  `Application Support/ShotZ Dev` (preferences `app.shotz.Shotz.dev`, left in place).

