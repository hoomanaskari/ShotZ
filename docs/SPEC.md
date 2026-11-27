# ShotZ — Phase 1 behaviour spec

ShotZ is an original macOS screenshot and annotation app. Phase 1 covers still
screenshots, the quick-access thumbnail stack, and the annotation editor.
Out of scope: video/GIF recording, scrolling capture, OCR, cloud upload, pinning.

ShotZ has its own name, icon, sounds, wording and visual design. It matches the
*workflow and quality* of the tool the owner uses today, not its look.

Sources for this spec: the owner's description of their workflow, the owner's
current preference values, macOS's built-in screenshot tool, and general
knowledge of this product category. The owner has confirmed the assumptions
that could not be observed directly; decisions are recorded in section 10.

Units are points unless stated. "Capture" means one still image plus metadata.

---

## 1. App shape

- Menu-bar agent app (`LSUIElement`), no Dock icon, no main window.
- Status item in the menu bar, **hideable** (owner runs with it hidden). When
  hidden, launching ShotZ again (Finder/Spotlight) opens Settings, so the app
  is always reachable.
- Status menu: Capture Area, Capture Window, Capture Fullscreen, All-in-One,
  separator, Capture History ▸ (last 10, click re-opens in the stack),
  Open Last Capture in Editor, separator, Settings…, Quit ShotZ. Each item
  shows its current shortcut.
- Launch at login (setting, default on after onboarding asks).
- No telemetry and no analytics. The only network access is Sparkle's update
  check in the production app: an https request for ShotZ's update feed
  (`appcast.xml` on GitHub), once a day by default and switchable in
  Settings ▸ Advanced, plus the update download when the user chooses to install
  it. Sparkle's system profile is off. ShotZ Dev and test runs never use the network.

## 2. Global shortcuts

| Action | ShotZ (production) | ShotZ Dev (development app) |
|---|---|---|
| Capture fullscreen | ⌘⇧3 | ⌃⌥⌘3 |
| Capture area | ⌘⇧4 | ⌃⌥⌘4 |
| All-in-one | ⌘⇧5 | ⌃⌥⌘5 |

- All three are rebindable in Settings (recorder control), and can be cleared.
- ⌘⇧6 is reserved for a later recording phase; ShotZ does not bind it.
- Shortcuts work from any app, including full-screen apps, with no extra
  permission (Carbon hot keys).
- If a shortcut cannot be registered, Settings shows a warning beside it.
  macOS does not always report a shortcut held by another app, and Settings
  says so.
- ShotZ Dev is a separate app (own bundle id, name, icon, settings, data and
  Screen Recording grant) so it can run next to the installed ShotZ; its
  default shortcuts never collide with production. Engineer and automated
  test runs register no shortcuts at all (`--no-hotkeys`).
- macOS's own screenshot shortcuts (System Settings ▸ Keyboard ▸ Keyboard
  Shortcuts ▸ Screenshots) must be off for ⌘⇧3/4/5 to reach ShotZ. On the
  owner's machine they already are (symbolic hot keys 28–31 and 184 are
  disabled). Onboarding checks this and shows the steps if they are on; ShotZ
  never changes system settings itself.
- A shortcut pressed while a capture is already in progress is ignored.

## 3. Capture flows

Capture is behind the `CaptureEngine` protocol. The Phase 1 engine drives the
system's `/usr/sbin/screencapture`, so selection feels exactly like macOS.

### 3.1 Area (⌘⇧4)

- Crosshair cursor with live coordinates; drag to select; release to capture.
- **Space** toggles window mode: the window under the pointer highlights,
  click captures that window **with its shadow** on a transparent background.
  Space again returns to the crosshair. ⌥-click in window mode captures
  without the shadow (system behaviour).
- While dragging: Space moves the selection, ⇧ locks an axis, ⌥ resizes from
  the centre (system behaviour).
- Esc cancels: no capture, no sound, nothing added to the stack.
- Works across all displays.

### 3.2 Fullscreen (⌘⇧3)

- Captures the whole display that contains the mouse pointer, immediately,
  including the menu bar and Dock. One capture, one thumbnail.

### 3.3 All-in-one (⌘⇧5)

- Phase 1: shows the system capture toolbar (selection / window / screen
  buttons, adjustable selection that remembers its last rectangle). The result
  is routed into ShotZ like any other capture. Recording buttons in that
  toolbar are not handled by ShotZ in Phase 1.
- Later: a ShotZ-native all-in-one overlay.

### 3.4 Capture Window (menu only, no default shortcut)

- Starts interactive capture already in window mode.

### 3.5 After any capture

1. The image is written losslessly (PNG) to ShotZ's private captures folder
   `~/Library/Application Support/Shotz/Captures/` with the display name
   `ShotZ YYYY-MM-DD at HH.mm.ss.png` (a counter is appended on collision).
2. Sound plays if sounds are on (setting, default on).
3. The capture is appended to history and shown in the quick-access stack
   (section 4). Target: thumbnail visible **≤ 150 ms** after the pixels exist.
4. Optional (settings, both default off): also copy to clipboard automatically;
   also save to the export folder automatically.

Image facts: pixel size equals the native pixels of the source (Retina = 2×);
the capture records its scale factor, source display, capture kind
(area/window/fullscreen) and timestamp. The display's colour profile is kept.

### 3.6 Known gaps of the Phase 1 engine (deferred, owner agreed)

The owner's current setup hides desktop icons during capture. The system tool
cannot do that; it needs the later native ScreenCaptureKit engine, as do a
magnifier loupe and a "freeze screen" option. Window captures use a
transparent background with shadow (system default); capturing a window on
top of the wallpaper is also deferred.

## 4. Quick-access stack

The owner's favourite part. It must feel instant and never get in the way.

### 4.1 Placement and stacking

- A column of thumbnail cards anchored to the **bottom-left** of a display's
  visible frame (so it clears the Dock), inset 16 from the left and bottom
  edges, 10 between cards. Setting: left or right side (default left).
- The **newest card is at the bottom**; existing cards slide up to make room.
- Up to 5 cards are visible (fewer if the display is short). When a sixth
  arrives, the oldest leaves the stack (it stays in history).
- Display choice: the display where the capture was taken (setting
  alternative: always the main display). If that display is disconnected the
  stack moves to the main display.
- The stack floats above normal windows and full-screen apps, appears on all
  Spaces, never takes keyboard focus, never activates ShotZ, and is excluded
  from ShotZ's own later captures.
- Cards stay until the user acts. Setting "auto-close after N seconds"
  (default off; the timer pauses while the pointer is over the stack).

### 4.2 Card

- Sizes (setting): Small 150 wide, Medium 200, **Large 250 (default,
  matching the owner's current size)**. Height follows a fixed
  16:10 card; the image is aspect-fit inside on a neutral backdrop, so very
  tall or wide captures stay recognisable.
- Rounded corners (10), hairline border, soft shadow. ShotZ's own styling.
- Entrance: slides in from the left edge with a short spring (~250 ms).
  Exit: fades and scales down (~180 ms); remaining cards settle with a spring.
- Animations must not delay interaction: a card is draggable and clickable
  from its first frame.

### 4.3 Hover

Hovering a card dims the image slightly and reveals, within 100 ms:

- Centre: **Copy** and **Save** buttons (labelled).
- Top-left: **Close** (×).
- Top-right: **Annotate** (pencil).
- Bottom-right: **Quick Look** (eye).
- Bottom-left: file-size / pixel-size caption, e.g. `1920 × 1080`.

Each button has a tooltip with its shortcut. With the pointer over a card
these keys act on it (the stack still does not take focus; keys are only
captured while hovering):

| Key | Action |
|---|---|
| ⌘C | Copy |
| ⌘S | Save |
| ⌘E or Return | Annotate |
| Space | Quick Look |
| ⌘W or Esc | Close |
| ⌘⌫ | Close and delete the file from history |

### 4.4 Actions

- **Copy**: puts the image on the pasteboard (PNG + TIFF + file URL) so it
  pastes into image and file targets alike. Brief "Copied" confirmation on the
  card. The card stays (setting: close after copy, default off).
- **Save**: writes to the export folder (default `~/Desktop`) **without
  asking** (owner's setting). Setting "ask where to save" shows a save panel
  instead. Format per settings. Brief "Saved" confirmation, then the card
  closes (setting: keep after save, default off).
- **Annotate**: opens the capture in the editor (section 5). While the editor
  is open the card is hidden from the stack (one capture, one place on
  screen). When the editor window closes, the card comes back (section 4.6).
- **Quick Look**: standard Quick Look preview panel for the file.
- **Close**: removes the card. The capture stays in history.
- **Double-click** the card: Annotate.
- **Right-click**: context menu with all of the above plus Show in Finder,
  Copy File Path, Delete, Close All.
- **Drag-out**: dragging a card starts a file drag immediately (3 pt
  threshold) with the thumbnail as the drag image. It drops into any app
  accepting image files or image data (Finder, Mail, Slack, browsers, chat
  apps, design tools). The dragged file carries the export file name and
  format. After a successful drop the card is **removed** (owner's setting;
  default on). A cancelled drag leaves the card in place.
- **Swipe away**: dragging a card horizontally off the nearest screen edge
  (rather than onto a drop target) dismisses it.

### 4.5 Robustness

- Ten captures in quick succession: no dropped captures, no animation
  glitches, stack remains ordered.
- Thumbnails are downsampled once, off the main thread; full images are not
  kept in memory by the stack.
- Display connect/disconnect, resolution change, Dock move and Space switch
  all re-lay-out the stack without losing cards.
- Quitting ShotZ clears the stack; captures remain in history.

### 4.6 Returning from the editor

Closing the editor means "done editing", not "dismiss". The capture leaves
the screen only when it is dismissed from the stack (or by a stack setting
such as remove-after-drag or close-after-save).

- When an editor window closes, its capture is presented in the stack again
  as the newest card (bottom), on the display the editor window was on.
- If the capture has edits (objects, crop or background), the card shows the
  **annotated result**: the thumbnail is re-rendered from the document, and
  Copy, Save, Quick Look and drag-out all deliver the flattened annotated
  image at full resolution. The size caption shows the annotated pixel size.
- Annotate on that card reopens the **same editable document**: objects are
  still selectable and editable, with the original pixels underneath.
- The same applies when the editor was opened from history or the status
  menu rather than from a card: closing it puts the card in the stack.
- An image opened from a file (not a capture) does not create a card.
- If the same capture is already open in an editor, Annotate brings that
  window forward; there is never a card and an editor for one capture at once.
- Copy or Save inside the editor do not close the editor or add a card
  (unless "close editor after copy/save" is on, in which case the close rule
  above applies and the card returns).
- Quitting ShotZ with editors open saves their documents; cards are not
  restored on next launch (history keeps everything).

## 5. Annotation editor

### 5.1 Window

- One standard resizable window per capture, titled with the capture name.
  Several can be open. Opening the editor activates ShotZ (it shows no Dock
  icon; the window is a normal key window).
- Initial size fits the image at ≤ 100 % zoom within 80 % of the screen;
  minimum 720 × 480.
- Layout: tool strip along the top, context options bar under it (changes
  with the selected tool/object), canvas in the middle, action buttons at the
  top-right (Copy, Save, drag handle).
- Canvas: checkerboard-free neutral backdrop, image centred. Zoom: pinch,
  ⌘+scroll, ⌘+ / ⌘− , ⌘0 fit, ⌘1 100 %. Range 10 %–800 %. Two-finger scroll
  pans; holding Space and dragging pans.
- Performance target: 60 fps object dragging, drawing and zooming on a
  5120 × 2880 capture; opening the editor ≤ 300 ms.
- Closing the window (⌘W or the close button) means "done editing": edits are
  written back to the history item silently (non-destructive; the document
  can be reopened and edited), there is no "save changes?" dialog, and the
  capture's card returns to the quick-access stack showing the annotated
  result (section 4.6).
- Esc: deselect → switch to Select tool → (nothing; Esc never closes).
  ⌘W closes.

### 5.2 Objects — common behaviour

- Everything drawn is a vector object over the untouched base image. Objects
  stay selectable, movable, resizable, restylable and deletable until export.
- After drawing an object the tool stays armed (draw several in a row);
  setting "return to Select after drawing" default off. A plain click on an
  existing object with a drawing tool selects it instead of starting a new one.
- Selection: click, ⇧-click to add, drag a marquee on empty canvas (Select
  tool), ⌘A all. Handles: 8 for box shapes, 2 end points (+ curve handle) for
  lines/arrows.
- Move: drag, arrow keys 1 px, ⇧+arrows 10 px. ⇧ while dragging constrains to
  an axis. ⌥-drag duplicates.
- Resize: ⇧ keeps aspect / snaps lines to 15°; ⌥ resizes from centre.
- Snapping: object edges and centres snap to image edges/centre and to other
  objects, with guide lines; ⌘ held disables snapping.
- Delete/Backspace deletes; ⌘D duplicates; ⌘C/⌘X/⌘V copy/cut/paste objects
  (between editor windows too); ⌘] / ⌘[ bring forward / send backward,
  ⌥⌘] / ⌥⌘[ to front / back.
- Changing an option with objects selected restyles them; with nothing
  selected it sets the default for the next object. Last-used style per tool
  is remembered across launches.
- Undo ⌘Z / redo ⇧⌘Z cover every change (create, move, style, crop,
  background), unlimited within the session; a drag is one undo step.

### 5.3 Tools

Shortcuts are single keys while no text is being edited.

| Key | Tool | Options |
|---|---|---|
| V | Select | — |
| A | Arrow | colour, thickness (5 steps), style: straight · curved · tapered ("pointer") · double-headed · line-with-dot; press A again to cycle styles |
| R | Rectangle | colour, thickness, outline / filled / outline+translucent fill, corner radius |
| O | Ellipse | colour, thickness, outline / filled |
| L | Line | colour, thickness, solid / dashed |
| T | Text | colour, size, style: plain · outlined · on solid pill · on translucent pill; bold; alignment |
| H | Highlighter | colour, thickness; freehand marker or rectangle highlight; multiply blend so text stays readable; ⇧ straightens |
| B | Blur / Pixelate | mode: pixelate · gaussian blur · solid redact; strength; drag a rectangle |
| N | Counter | colour, size; each click drops the next number; drag while placing to pull out an optional pointer tail; start value and style (1,2,3 / A,B,C) |
| P | Pen | colour, thickness; smoothed freehand; ⇧ straight line |
| C | Crop | free or aspect preset (Original, 1:1, 4:3, 16:9, 3:2); snapping to image edges and objects; numeric W×H fields; Return applies, Esc cancels; non-destructive (can be re-opened and widened) |
| G | Background | see 5.4 |

Details:

- **Colour**: 8 presets (red default, orange, yellow, green, blue, purple,
  black, white) plus a custom colour well (system colour panel) and opacity.
  Keys 1–8 pick a preset.
- **Thickness** scales with image size so a "medium" arrow looks the same on a
  1× and a 5K capture (base unit = image long edge / 400, clamped).
- **Arrow**: head size scales with thickness; curved arrows expose one
  mid-point control handle; arrows always get a subtle contrast outline option
  (setting in options bar, default off).
- **Text**: click to place and type; Return = new line, ⌘Return or Esc or
  click-away commits; double-click an existing text to edit. Empty text is
  discarded. Dragging side handles sets wrap width; corner handles scale the
  font. System font, emoji supported.
- **Blur / Pixelate** objects sample the base image (and background fill) only,
  never other annotations, and are irreversible in exported files (real pixels,
  strong enough that text is unrecoverable at default strength). They render
  beneath other annotation types regardless of creation order.
- **Counter** numbers renumber automatically when one is deleted; a selected
  counter's value can be typed over.
- **Pen/Highlighter** strokes are smoothed on release and become single
  objects (movable, recolourable, not point-editable).

### 5.4 Background tool

A panel (toggle G) that wraps the image for presentation:

- On/off.
- Fill: none (transparent) · solid colour · gradient (12 built-in original
  presets + custom two-stop with angle) · **(later)** image/wallpaper.
- Padding (0–25 % of the long edge, slider), optional auto-balance (equal
  visual margins).
- Inner corner radius, shadow (off / soft / strong), inset alignment (9-way):
  the position grid places the image within the padded canvas. In each axis
  the chosen side keeps a quarter of the padding and the opposite side takes
  the rest (centre splits it evenly), so it works with Auto aspect too. With no
  padding and Auto aspect there is nothing to position against: the grid is
  disabled with a note.
- Output aspect: auto, 1:1, 4:3, 16:9, 3:2 (canvas grows; image never crops).
- Window captures (which already carry a transparent shadow margin) are
  handled so the shadow blends onto the fill.
- Presets: save current as a named preset; last used is remembered.

### 5.5 Output

- **Copy** (⌘⇧C, or ⌘C with nothing selected): flattened image to the
  pasteboard. Window stays open (setting: close after copy).
- **Save** (⌘S): writes the flattened image to the export folder without
  asking (or overwrites the previous export of this document), brief
  confirmation; setting "ask where to save".
- **Save As…** (⇧⌘S): save panel with format (PNG, JPEG + quality, HEIC) and
  1× / 2× scale choice.
- **Drag-out**: the drag handle (and the title-bar proxy icon) drags the
  flattened file into other apps.
- Export is always rendered at full pixel resolution of the base image
  (never from the on-screen zoom), sRGB or Display P3 preserved from source.
- The editable document (base image + objects) is stored with the history
  item, so re-opening a capture from history restores editable objects.
- Other menu items: Print (⌘P), Add Capture from File (⌘O opens any image in
  the editor), New from Clipboard (⌘N).

## 6. History

- Every capture is kept in the private captures folder with a small index
  (name, time, kind, pixel size, export path if saved, editor document if
  edited).
- Retention setting: 1 day / 1 week / 1 month (default) / forever; pruned on
  launch and daily.
- Status menu shows the last 10; "Restore last closed card" (no default
  shortcut) puts the most recently closed capture back in the stack.
- A full history browser window is later-phase.

## 7. Settings

SwiftUI window with tabs. Defaults in **bold**; owner's values noted.

**General**
- Launch at login (**on**)
- Show menu-bar icon (**on**; owner: off)
- Play sounds (**on**)
- Export folder (**~/Desktop**)
- After capture: show quick-access stack (**on**) · copy to clipboard (**off**)
  · save automatically (**off**)

**Shortcuts**
- Recorders for fullscreen, area, all-in-one, capture window, restore last
  closed. Reset to defaults.

**Quick access**
- Side: **left** / right
- Display: **where captured** / main display
- Size: small / medium / **large**
- Auto-close: **off** / 5 s / 10 s / 30 s
- Remove after dragging out (**on**)
- Close after copy (**off**) · close after save (**on**)
- Ask for destination when saving (**off**)

**Capture**
- Format: **PNG** / JPEG / HEIC (affects export; private originals stay PNG)
- Retina scale: **native** / downscale to 1×
- Window capture shadow (**on**)
- File name pattern (**ShotZ %Y-%m-%d at %H.%M.%S**)

**Editor**
- Return to Select tool after drawing (**off**)
- Snap while moving and cropping (**on**)
- Close editor after copy (**off**) · after save (**off**)

**Advanced**
- History retention (**1 month**), Clear history…
- Reset all settings

## 8. Permissions and onboarding

- **Screen Recording** is the only required permission (the system capture
  tool runs on ShotZ's behalf). Accessibility is *not* required.
- First launch shows a small onboarding window:
  1. Welcome — what ShotZ does, where it lives (menu bar), its shortcuts.
  2. Screen Recording — explains why, "Open System Settings" button that
     deep-links to Privacy & Security ▸ Screen & System Audio Recording,
     live status that turns green when granted, and a note that macOS may ask
     to quit and reopen ShotZ (with a "Relaunch" button).
  3. System shortcuts — detects whether macOS's own ⌘⇧3/4/5 are enabled; if
     so, shows the exact steps to turn them off and a button to open Keyboard
     settings; if another app already holds the shortcuts, says so and offers
     alternates.
  4. Launch at login toggle, done.
- If a capture is attempted without permission, ShotZ shows the permission
  step instead of producing an empty or wallpaper-only image.
- Onboarding can be reopened from Settings ▸ Advanced.

## 9. Quality bar

- Hotkey to crosshair: no perceptible delay (≤ 100 ms).
- Idle footprint: no timers or polling while idle; < 60 MB memory with an
  empty stack.
- Nothing ever steals focus except the editor window the user asked for.
- No crashes on display changes, sleep/wake, or fast repeated captures.
- VoiceOver labels on all stack buttons and editor tools.

## 10. Decisions

Confirmed by the owner:

1. Default stack card size is Large (~250 wide).
2. Closing the editor writes edits back silently, with no dialog, and the
   capture stays re-editable.
3. Hiding desktop icons during capture is deferred past Phase 1, to the later
   native capture engine.

Requested by the owner after first use:

- Closing the editor returns the capture to the stack as an annotated card;
  it is dismissed only from the stack (section 4.6).
- Development and production are separate apps that run side by side
  (ARCHITECTURE section 8).
- Tool and action icons come from one open-source icon set (Phosphor, MIT),
  not stock system symbols; see THIRD-PARTY-NOTICES.

Decided by engineering (sensible defaults, change if the owner objects):

4. Window captures use a transparent background with the window shadow, as
   the macOS tool does. Capturing on top of the wallpaper is deferred.
5. Stack ordering is newest at the bottom, older cards slide up.
6. All-in-one (⌘⇧5) uses the system capture toolbar in Phase 1.
