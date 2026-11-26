# Installing Shotz

How to install Shotz into `/Applications`, move your shortcuts over to it, and
undo the install. Everything here happens on your Mac; Shotz never uses the
network.

## 1. Install

1. Quit any Shotz you started from the checkout (`scripts/run.sh`): open
   Settings ▸ Advanced and click **Quit Shotz**. If the menu-bar icon is shown,
   you can also choose **Quit Shotz** from its menu.
2. In Terminal, from the main checkout (not a worktree), run:

   ```bash
   scripts/install.sh
   ```

   The script builds a signed release, checks it, and then replaces
   `/Applications/Shotz.app` in one step. If something fails before that
   step, any existing copy is left as it was. It quits and relaunches only an
   already installed Shotz. It also warns you if a Shotz from the checkout is
   still running.
3. Open **Shotz** from `/Applications` or Spotlight. With the menu-bar icon
   hidden, opening Shotz again brings up its Settings.

## 2. Screen Recording permission

macOS ties the Screen Recording permission to the app's identity: its bundle
id and the certificate it was signed with. The installed copy has the same
identity as the builds you have already allowed, so the permission should
carry over.

- **Check:** Shotz Settings ▸ General ▸ Permissions shows **Allowed** next to
  Screen Recording.
- **If it shows Not allowed, or macOS asks again:**
  1. Click **Set Up…** next to Screen Recording, then **Open System
     Settings**. This opens Privacy & Security ▸ Screen & System Audio
     Recording.
  2. Turn **Shotz** on. If Shotz is listed twice, remove both entries with
     **−**, then add `/Applications/Shotz.app` with **+**.
  3. If macOS offers to quit and reopen Shotz, choose **Later**. Then click
     **Relaunch Shotz** in the Shotz window.

## 3. Launch at login

The first time Shotz runs from `/Applications`, it applies the choice you made
in the welcome window (on by default) and adds itself to your login items.
Builds run from the checkout never do this.

- **Check:** Shotz Settings ▸ General ▸ **Launch at login**.
- If Shotz says macOS needs you to allow it, click **Open Login Items…** and
  turn Shotz on under System Settings ▸ General ▸ Login Items & Extensions.
- To stop it starting at login, turn the setting off in Shotz, or turn Shotz
  off in Login Items.

## 4. Freeing ⌘⇧3, ⌘⇧4 and ⌘⇧5

These shortcuts only reach Shotz when nothing else claims them first.

- **macOS's own screenshot shortcuts:** System Settings ▸ Keyboard ▸ Keyboard
  Shortcuts… ▸ Screenshots. Untick the screenshot shortcuts there. They are
  already off on this Mac. Shotz's welcome window checks this and lists any
  that are still on.
- **Your other screenshot app:** open its settings and clear or change its
  shortcuts for capturing the full screen, an area, and its all-in-one or
  capture-options mode. Or quit that app, and stop it from opening at login.
  If two apps share a shortcut, either one may get the key press.

## 5. Checking the shortcuts

The installed Shotz uses the shortcuts saved in its Settings: ⌘⇧3, ⌘⇧4 and
⌘⇧5 unless you changed them. (The Shotz you ran from the checkout before
used ⌃⌥⌘3/4/5. From now on those belong to Shotz Dev; see step 8.)

- **Check:** Shotz Settings ▸ Shortcuts lists the three shortcuts.
- A yellow warning next to a shortcut means Shotz could not register it.
  Free it as described in step 4. macOS does not always report a shortcut
  that another app holds. So if a shortcut shows no warning but does nothing,
  another app may still be using it.
- To see what Shotz registered, run this in Terminal. It prints one line per
  shortcut: `registered`, `FAILED (Carbon status …)` or `not registered`.

  ```bash
  log show --last 10m --style compact --predicate 'subsystem == "app.shotz.Shotz"' | grep "Hotkey "
  ```

## 6. Clearing test history

Early builds may have left test captures (synthetic images) in Shotz's
history.

- In Shotz Settings ▸ Advanced, click **Clear History…**. This deletes the
  captures Shotz keeps for itself and their edits. Files you saved or
  exported stay where they are.
- Older test builds kept their data in a folder you can delete:

  ```bash
  rm -rf ~/Library/Application\ Support/Shotz-Dev
  ```

## 7. Rolling back

1. In Shotz Settings ▸ General, turn **Launch at login** off, so no login item
   is left behind.
2. In Settings ▸ Advanced, click **Quit Shotz**.
3. Delete `/Applications/Shotz.app`: drag it to the Bin, or run:

   ```bash
   rm -rf /Applications/Shotz.app
   ```

4. If you changed your other screenshot app's shortcuts, change them back.

Your history (`~/Library/Application Support/Shotz`) and settings (preferences
domain `app.shotz.Shotz`) stay in place, ready for a later reinstall. Delete
them too if you want a clean slate. The Screen Recording entry for Shotz can
be removed in Privacy & Security ▸ Screen & System Audio Recording with **−**.

## 8. Running the development build next to the installed app

`scripts/run.sh` builds and opens **Shotz Dev**, a separate app built from the
same code for trying changes. It never touches your installed Shotz, and
`scripts/install.sh` never touches Shotz Dev.

- **Telling them apart:** Shotz Dev's icon has an amber **DEV** band, and its
  menu-bar icon is amber.
- **Shortcuts:** Shotz Dev uses ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5, so both apps can run
  at once.
- **Separate everything:** Shotz Dev has its own settings, history
  (`~/Library/Application Support/Shotz Dev`) and login item (off by default).
- **Screen Recording:** Shotz Dev needs its own permission, granted once:
  1. The first time it captures, Shotz Dev opens its permission step.
  2. Click **Open System Settings** and turn **Shotz Dev** on.
  3. Click **Relaunch Shotz Dev**.

  Until then, captures in Shotz Dev show the permission step instead.
- **Quitting:** use Shotz Dev's menu-bar icon, or Settings ▸ Advanced ▸
  **Quit Shotz Dev**.
- **Removing it:**

  ```bash
  rm -rf "build/Shotz Dev.app" ~/Library/Application\ Support/Shotz\ Dev
  ```

  ```bash
  defaults delete app.shotz.Shotz.dev
  ```

