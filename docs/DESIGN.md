# ShotZ design system (ShotzUI)

One module, one owner. Every surface (editor, quick-access stack, Settings, onboarding) builds its
controls from `ShotzUI` and its glyphs from `ShotzIcon` (ShotzCore). Surfaces keep no control
styling of their own. The gallery shows every control in every state:
`SHOTZ_UI_GALLERY=<dir> swift test --filter "GalleryTests|GalleryStep2Tests|SwiftUIGalleryTests"`.

## Tokens (`ShotzUI.*`)

| Token | Values | Use |
|---|---|---|
| `Space` | xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32 | Every gap and inset; never literals |
| `ControlSize` | compact 24 · regular 28 · large 32 (hit target always ≥ 28) | One size per row: options bar compact, toolbars regular, onboarding large |
| | icons 14 / 16 / 18 · radius 6 / 7 / 8 · padding 8 / 10 / 14 | |
| `ToolMetrics` | 32-pt square, 18-pt glyph, radius 8, 2-pt gap | Tool strip only |
| `Radius` | small 4 · card 10 · panel 12 | Key caps / cards and banners / panels and popovers |
| `Typography` | display 20 semibold (onboarding / page titles) · title 15 semibold · sectionHeader 13 semibold · body 13 · control 13 medium · label 12 medium · caption 11 · value 12 medium monospaced digits | NSFont `.font`, SwiftUI `.swiftUIFont` |
| `Palette` | windowBackground, surface, surfaceSunken, raised · separator, border · textPrimary / Secondary / Tertiary · fillHover, fillPressed · accentFill, onAccent, selectedFill, selectedContent, selectedBorder, focusRing · danger, success, warning · glassFill, glassEdge | Semantic only; each resolves for light, dark and increased contrast |
| `ControlState` | rest · hover · pressed · selected · disabled · focused (combinable) | |
| `ControlRole` | primary · secondary · quiet · tool · chip · glass · destructive | |
| `fills(for:state:)` | role × state → background, border, content, raised | The only place state styling lives |
| `Motion` | fast 0.12 s · standard 0.2 s · slow 0.3 s; `arrive`, `move` curves | 0 under Reduce Motion; `reduceTransparency` makes glass solid |
| `Elevation` | control · card · overlay · `floating(dark:)` | Shadows in light; dark relies on surface steps and borders. `floating` is for overlays over arbitrary wallpaper (the stack): 0.45 opacity in dark |
| `Palette.scrim` | black 25 % (35 % with increased contrast) | Dim over an image under hover controls |
| `ShotzUI.isDark(in:)`, `isIncreasedContrast(in:)` | | Appearance checks for surface code (instead of comparing appearance names) |

The accent family follows the system accent. `accentFill` and `selectedContent` are derived so labels
always reach 4.5:1 (7:1 with Increase Contrast), so an orange or yellow accent gets dark labels
automatically. Contrast is unit-tested for 4 appearances × 8 accents.

## Controls

AppKit (layer-backed, drawn in `draw(_:)`, usable in title bars, panels and the non-activating stack
panel). All share `ShotzControlView`: hover/press tracking, keyboard focus with ShotZ's focus ring,
first-mouse, Space/Return activation, VoiceOver role/label/value, `stateOverride` for previews.

| Control | Use it for |
|---|---|
| `ShotzButton` `.primary` | The one main action of a surface (editor Done, onboarding Continue) |
| `ShotzButton` `.secondary` | Other labelled actions (editor Copy and Save, Choose…) |
| `ShotzButton` `.quiet` (icon only) | Toolbar actions: zoom, more, undo; always with `setShotzToolTip(_:shortcut:)` |
| `ShotzButton` `.destructive` | Delete, Clear history |
| `ShotzButton.glass(_:icon:cardSize:)` | The icon + label Copy / Save pair on a card (tighter metrics on small cards) |
| `ShotzGlassIconButton` | Circular glass corner buttons on a card; 30 / 28 / 22 pt (large / medium / small), hit ≥ 28 |
| `ShotzGlassLabel` | Non-interactive text over images (static text, never takes the mouse) |
| `ShotzCaptionPill` | The size caption on a card (a `ShotzGlassLabel` with monospaced digits) |
| `ShotzButton.glass(_:icon:cardSize:iconOnly: true)` | Icon-only glass Copy / Save where labels don't fit |
| `ShotzToolButton` | Editor tools; selected = soft accent tint + accent edge + accent glyph |
| `ShotzSegmentedControl` | Mutually exclusive styles (arrow style, fill mode, text style); text or icon segments |
| `ShotzSegmentedControl.thicknessPicker` | The stepped thickness picker |
| `ShotzSwatchRow` | Colour presets + custom well |
| `ShotzSlider` | Continuous values with a leading icon and trailing monospaced value (opacity, padding) |
| `ShotzToggleChip` | On/off options (contrast outline, panel toggles); a capsule, never confused with a tool |
| `ShotzPopUpButton` | Choosing a value (secondary, ↕ chevron) or a menu of actions (quiet, ⌄ chevron) |
| `ShotzNumberField` | Numbers with steppers: crop W × H, counter start |
| `ShotzSeparator` | Between toolbar groups (vertical) or rows (horizontal) |
| `ShotzToolbarStack` | Any bar: groups with 4-pt gaps, 12 pt + separator between groups |
| `ShotzPanel` + `ShotzFormStack` | Popovers and side panels (background, crop): label column + controls |
| `ShotzToast` | Confirmations: "Copied", "Saved", "Couldn't save"; `compact: true` on cards; `show(in:position: .center / .bottom, duration:)` |
| `ShotzTextField` | Single-line text (file-name pattern, preset names); `usesMonospacedFont` for patterns |
| `ShotzCheckbox`, `ShotzSwitch` | On/off settings inside editor panels |
| `ShotzColorWell` | A single custom colour (gradient stops, background colour) |
| `ShotzTileButton` | Image tiles: gradient presets, later wallpapers |
| `ShotzToggleChip(icon:label:)` | Icon-only on/off chips in tight bars |
| `ShotzUI.label(_:_:)` | Panel titles, form labels, notes, captions (never hand-styled `NSTextField`s) |
| `ShotzKeyCaps` | Shortcuts shown in panels or help |

SwiftUI (Settings and onboarding), drawn from the same tokens and the same state → fills mapping:
`.buttonStyle(.shotz(role, size:))`, `ShotzLabel`, `ShotzIconView`, `.toggleStyle(.shotzSwitch)`,
`.toggleStyle(.shotzCheckbox)`, `.toggleStyle(.shotzChip)`, `ShotzSegmentedPicker`, `ShotzMenuPicker`,
`ShotzSliderView`, `ShotzSwatchPicker`, `ShotzSettingsPane`, `ShotzSettingsSection`, `ShotzCard`,
`ShotzSettingsRow`, `ShotzSettingsTabBar` (onboarding / in-window tabs only), `ShotzBanner`, `ShotzKeyCapsView`, `ShotzStatusBadge`.

SwiftUI also has `ShotzTextFieldView`, `ShotzFormRow` (label column), `ShotzHelpText(tone:)` and `ShotzShortcutField`
(the recorder's look; key capture stays with the caller).

Reference compositions (built only from the above): `EditorActionArea` (zoom │ drag, more │
Copy · Save · **Done**), `EditorOptionsBar`, `StackCardHover(cardSize:)`, `SettingsPaneExample`.

### Editor control factory → ShotzUI

| `EditorControls` today | ShotzUI |
|---|---|
| `toolStrip`, `toolbarToggle` | `ShotzToolButton` (toggle = `isSelected`) in a `ShotzToolbarStack` |
| `primaryButton`, `secondaryButton`, `iconButton`, `prominentButton`, `button` | `ShotzButton` `.primary` / `.secondary` / `.quiet` icon |
| `segmented(glyphs:)`, `segmented(titles:)` | `ShotzSegmentedControl` (icon / text), `.thicknessPicker` |
| `toggleChip(glyph)`, `toggleChip(title)` | `ShotzToggleChip(icon:label:)`, `ShotzToggleChip(title:)` |
| `slider`, `sliderRow` | `ShotzSlider` (leading icon: `.opacity`, `.strength`, `.angle`, `.padding`) |
| `swatch`, `colorWell`, `eyedropper` | `ShotzSwatchRow`, `ShotzColorWell`, `ShotzButton(icon: .eyedropper, role: .quiet)` |
| `popup`, `zoomMenu` | `ShotzPopUpButton` (secondary choice / quiet with `titleFont = Typography.value`) |
| `numberField` | `ShotzNumberField` |
| `checkbox`, `panelSwitch` | `ShotzCheckbox`, `ShotzSwitch` |
| `imageButton` | `ShotzTileButton` |
| `panelTitle`, `formLabel`, `note`, `caption` | `ShotzUI.label(_, .panelTitle / .formLabel / .note / .caption)` |
| `separator` | `ShotzSeparator` |
| `toast` | `ShotzToast` |

## Rules

Do
- Use one primary action per surface, at the trailing end.
- Give a row one control size. Use tokens for every gap, radius, font and colour.
- Give every icon-only control a tooltip with its shortcut and an accessibility label (`ShotzIcon`
  supplies one).
- Group toolbar controls with `ShotzToolbarStack`; separate groups, don't space them by eye.
- Show values in `Typography.value` (monospaced digits) and reserve their width.

Don't
- Don't style controls outside ShotzUI: no `NSButton` bezels, `.bordered` / `.borderedProminent`,
  custom fills, or hand-drawn selection blocks in surface code. If something is missing, ask the
  ShotzUI owner.
- Don't use SF Symbols. Use `ShotzIcon` (Phosphor regular plus ShotZ glyphs), one weight everywhere.
- Don't use colour literals or system colours for chrome. Use `ShotzUI.Palette` (the system accent
  comes through it).
- Don't let a control change size between states (the chip reserves its check slot; values reserve
  their width).
- Don't put more than one primary button on a surface, or a primary in a toolbar group with quiet icons.

## Adoption checklist

Editor (AnnotationEditor)
- [ ] Tool strip: `ShotzToolButton` per tool, groups select │ shapes │ text, counter │ redact, crop,
      background (2-pt gap, `Space.s` + separator between groups).
- [ ] Trailing area: `EditorActionArea` (zoom │ drag, more │ Copy · Save · Done); Done is the only
      primary (closes the window, back to the stack), Copy and Save are equal-width secondaries.
- [ ] Options bar: `EditorOptionsBar` layout in a `ShotzToolbarStack`, all compact.
- [ ] Background and crop panels: `ShotzPanel` + `ShotzFormStack`; crop W × H with `ShotzNumberField`;
      aspect presets with `ShotzPopUpButton`.
- [ ] Feedback: `ShotzToast`. Highlight layers keep `AnnotationRenderer.blendMode(for:document:base:)`.
- [ ] Remove `EditorControls.swift` styling once every call site uses ShotzUI.

Quick-access stack (QuickAccess)
- [ ] Hover controls: `StackCardHover(cardSize:)` layout: `ShotzGlassIconButton` corners (inset 6 / 8 / 8 pt),
      `ShotzButton.glass` Copy / Save pair centred, `ShotzCaptionPill` bottom-left.
- [ ] Flashes: `ShotzToast(_, tone:, compact: true).show(in: card, position: .center)`; icons `.success`, `.failure`.
- [ ] Size caption: `ShotzCaptionPill` (inert), not a frozen glass button. Dim: `Palette.scrim`.
- [ ] Panel shadow over wallpaper: `Elevation.floating(dark: ShotzUI.isDark(in: appearance))`.
- [ ] Context menu items use `ShotzIcon` images (`image(pointSize: 16)`).

Settings and onboarding (AppShell): one ShotzUI part per existing wrapper

| AppShell wrapper | ShotzUI |
|---|---|
| `PrefPane` | `ShotzSettingsPane` |
| `PrefSection` | `ShotzSettingsSection` (header over a `ShotzCard`) |
| `PrefRow` (label column) | `ShotzFormRow` (or `ShotzSettingsRow` for title + trailing control rows) |
| `PrefHelp` (secondary / warning / error) | `ShotzHelpText(tone:)` |
| `ShellCheckbox` | `.toggleStyle(.shotzCheckbox)` |
| `ShellSwitch` | `.toggleStyle(.shotzSwitch)` |
| `ShellButton` standard / prominent / link | `.buttonStyle(.shotz(.secondary))` / `.shotz(.primary)` / `.shotz(.quiet)` |
| `ShellBanner` info / warning | `ShotzBanner(tone: .info / .warning)` |
| `KeyCap`, `KeyCapsRow` | `ShotzKeyCapsView([…])` |
| `ShortcutRecorderField` | `ShotzShortcutField` |
| `StatusPill(text:positive:)` | `ShotzStatusBadge(_:positive:)` |

- [ ] Tabs: keep the system preferences toolbar (`NSToolbar`) with `ShotzIcon` images (`.general`,
      `.keyboard`, `.stack`, `.capture`, `.editor`, `.advanced`). Pane content uses ShotzUI sections,
      cards, rows and switches. (`ShotzSettingsTabBar` is for onboarding or in-window tab strips only.)
- [ ] Swap each wrapper body for its ShotzUI part (the panes don't change).
- [ ] Format and similar choices: `ShotzSegmentedPicker` (≤ 4 options) or `ShotzMenuPicker`.
- [ ] Onboarding primary action: `.shotz(.primary, size: .large)`, one per page; page titles in
      `Typography.display`.
- [ ] Switches and checkboxes in rows use `.labelsHidden()` (honoured: no label gap).
- [ ] Text inputs (file-name pattern): `ShotzTextFieldView(…, monospaced: true)`.

Every surface
- [ ] No `import SwiftUI` `.bordered*` styles, no SF Symbols, no colour literals in chrome.
- [ ] Check light, dark and Increase Contrast; keyboard-only pass (Tab through, Space activates,
      focus ring visible); VoiceOver reads every control.
