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
| `Typography` | title 15 semibold · sectionHeader 13 semibold · body 13 · control 13 medium · label 12 medium · caption 11 · value 12 medium monospaced digits | NSFont `.font`, SwiftUI `.swiftUIFont` |
| `Palette` | windowBackground, surface, surfaceSunken, raised · separator, border · textPrimary / Secondary / Tertiary · fillHover, fillPressed · accentFill, onAccent, selectedFill, selectedContent, selectedBorder, focusRing · danger, success, warning · glassFill, glassEdge | Semantic only; each resolves for light, dark and increased contrast |
| `ControlState` | rest · hover · pressed · selected · disabled · focused (combinable) | |
| `ControlRole` | primary · secondary · quiet · tool · chip · glass · destructive | |
| `fills(for:state:)` | role × state → background, border, content, raised | The only place state styling lives |
| `Motion` | fast 0.12 s · standard 0.2 s · slow 0.3 s; `arrive`, `move` curves | 0 under Reduce Motion; `reduceTransparency` makes glass solid |
| `Elevation` | control · card · overlay | Shadows in light; dark relies on surface steps and borders |

The accent family follows the system accent. `accentFill` and `selectedContent` are derived so labels
always reach 4.5:1 (7:1 with Increase Contrast), so an orange or yellow accent gets dark labels
automatically. Contrast is unit-tested for 4 appearances × 8 accents.

## Controls

AppKit (layer-backed, drawn in `draw(_:)`, usable in title bars, panels and the non-activating stack
panel). All share `ShotzControlView`: hover/press tracking, keyboard focus with ShotZ's focus ring,
first-mouse, Space/Return activation, VoiceOver role/label/value, `stateOverride` for previews.

| Control | Use it for |
|---|---|
| `ShotzButton` `.primary` | The one main action of a surface (editor Save, onboarding Continue) |
| `ShotzButton` `.secondary` | Other labelled actions (Copy, Choose…) |
| `ShotzButton` `.quiet` (icon only) | Toolbar actions: zoom, more, undo; always with `setShotzToolTip(_:shortcut:)` |
| `ShotzButton` `.destructive` | Delete, Clear history |
| `ShotzButton` `.glass` | Controls over images (stack card hover) |
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
| `ShotzToast` | Confirmations: "Copied", "Saved", "Couldn't save" |
| `ShotzKeyCaps` | Shortcuts shown in panels or help |

SwiftUI (Settings and onboarding), drawn from the same tokens and the same state → fills mapping:
`.buttonStyle(.shotz(role, size:))`, `ShotzLabel`, `ShotzIconView`, `.toggleStyle(.shotzSwitch)`,
`.toggleStyle(.shotzCheckbox)`, `.toggleStyle(.shotzChip)`, `ShotzSegmentedPicker`, `ShotzMenuPicker`,
`ShotzSliderView`, `ShotzSwatchPicker`, `ShotzSettingsPane`, `ShotzSettingsSection`, `ShotzCard`,
`ShotzSettingsRow`, `ShotzSettingsTabBar`, `ShotzBanner`, `ShotzKeyCapsView`, `ShotzStatusBadge`.

Reference compositions (built only from the above): `EditorActionArea`, `EditorOptionsBar`,
`StackCardHover`, `SettingsPaneExample`.

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
- [ ] Trailing area: `EditorActionArea` (zoom │ drag, more │ Copy · Save); Save is the only primary.
- [ ] Options bar: `EditorOptionsBar` layout in a `ShotzToolbarStack`, all compact.
- [ ] Background and crop panels: `ShotzPanel` + `ShotzFormStack`; crop W × H with `ShotzNumberField`;
      aspect presets with `ShotzPopUpButton`.
- [ ] Feedback: `ShotzToast`. Highlight layers keep `AnnotationRenderer.blendMode(for:document:base:)`.
- [ ] Remove `EditorControls.swift` styling once every call site uses ShotzUI.

Quick-access stack (QuickAccess)
- [ ] Hover buttons: `ShotzButton(role: .glass)`, layout as `StackCardHover` (corner circles inset 8 pt,
      Copy and Save centred, caption pill bottom-left).
- [ ] Flashes: `ShotzToast` (`.success` / `.failure`); icons `.success`, `.failure`.
- [ ] Context menu items use `ShotzIcon` images (`image(pointSize: 16)`).

Settings and onboarding (AppShell), mapped onto the existing swap points
- [ ] `PrefPane` → `ShotzSettingsPane`; `PrefSection` → `ShotzSettingsSection`; `PrefRow` + `PrefHelp`
      → `ShotzSettingsRow(_, help:)`.
- [ ] Window tabs → `ShotzSettingsTabBar` (icons `.general`, `.keyboard`, `.stack`, `.capture`,
      `.editor`, `.advanced`).
- [ ] `ShellSwitch` → `.toggleStyle(.shotzSwitch)`; `ShellCheckbox` → `.toggleStyle(.shotzCheckbox)`.
- [ ] `ShellButton` → `.buttonStyle(.shotz(.secondary))`, `.prominent` → `.shotz(.primary)`,
      `.link` → `.shotz(.quiet)`.
- [ ] `ShellBanner` → `ShotzBanner`; `KeyCap` / `KeyCapsRow` → `ShotzKeyCapsView`; `StatusPill` →
      `ShotzStatusBadge`.
- [ ] Format and similar choices: `ShotzSegmentedPicker` (≤ 4 options) or `ShotzMenuPicker`.
- [ ] Onboarding primary action: `.shotz(.primary, size: .large)`, one per page.

Every surface
- [ ] No `import SwiftUI` `.bordered*` styles, no SF Symbols, no colour literals in chrome.
- [ ] Check light, dark and Increase Contrast; keyboard-only pass (Tab through, Space activates,
      focus ring visible); VoiceOver reads every control.
