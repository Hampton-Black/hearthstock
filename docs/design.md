# Hearthstock design handoff (v1)

How the iPhone designs translate to SwiftUI. Behavior lives in `docs/spec.md`; this file covers how things look and feel. The source designs are the "Hearthstock — iPhone v1" design canvas (artboard names are given in the screen table below).

Direction: **Hearth**. Warm and calm, close to stock iOS. One accent (juniper green), amber for "use soon / rotate", red only for expired items and a shortfall below 3 days.

## 1. Color tokens

Define each token once with a light and dark value. Every pair below meets WCAG 4.5:1 for text on its intended background (checked).

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `bg` | `#F6F1E9` | `#17140F` | Screen background (replaces `systemGroupedBackground`) |
| `card` | `#FFFDF9` | `#25211B` | Cards, grouped rows, sheets' controls |
| `ink` | `#2B241E` | `#F3ECE2` | Primary text |
| `ink2` | `#5F554B` | `#BCB09F` | Secondary text, captions |
| `ink3` | `#776C61` | `#A39784` | Chevrons, inactive tabs, neutral marks. Not for body text |
| `separator` | `#E6DED2` | `#3A342C` | Hairlines (0.5 pt) |
| `track` | `#E9E2D6` | `#332E27` | Search field, segmented control, steppers, bar tracks, Use soon badge |
| `tint` | `#2F5D50` | `#86BBA6` | App accent, primary buttons, the limiting category |
| `tintSoft` | `#E2ECE6` | `#24352E` | Icon tiles, secondary buttons |
| `onTint` | `#FFFDF9` | `#17140F` | Text and icons on `tint` fills (dark mode flips to dark text) |
| `good` / `goodBg` | `#2E6B4F` / `#E1EEE5` | `#8CC7A5` / `#203328` | Good badge, "target met" |
| `amber` / `amberBg` | `#8A5A00` / `#FBEACB` | `#F0BC5E` / `#3A2E17` | Caution, Inspect, Use soon icon |
| `amberLine` | `#D9A441` | `#C9973A` | Kit meter segments, lot timeline (graphics only) |
| `red` / `redBg` | `#A3241B` / `#F7DFDB` | `#F2918A` / `#41201C` | Expired, critical shortfall (< 3 days) |

Set `tint` as the app's `.tint`. Implement tokens as `Color` extensions backed by `UIColor { traits in … }` so they live in reviewable code (no asset catalog churn):

```swift
extension Color {
    static let hsTint = Color(light: 0x2F5D50, dark: 0x86BBA6)
    // …one line per token
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}
```

Camera screens (scan, pantry walk) are always dark: background `#1C1813`, text `#F6EFE4` / `#CFC3B2`, reticle accent `#86BBA6`. Confirm cards on camera screens use the light `card` color in both modes.

## 2. Typography

System font (SF Pro) everywhere. Numbers use `.fontDesign(.rounded)` plus `.monospacedDigit()`. Everything uses text styles so Dynamic Type works; nothing is a fixed point size except the hero number, which scales with `@ScaledMetric(relativeTo: .largeTitle)`.

| Element | Style | Weight / design |
| --- | --- | --- |
| Screen title | `.largeTitle` (navigation large title) | Bold |
| Hero runway range ("9–11") | 64 pt, `@ScaledMetric(relativeTo: .largeTitle)` | Bold, rounded |
| "days" after the hero | `.title2` | Semibold, rounded, `ink2` |
| Category value ("18–24 days") | `.title` | Bold, rounded |
| Section header ("Focus next") | `.title3` | Bold |
| Row title | `.headline` | Semibold |
| Row subtitle, card captions | `.subheadline` | Regular, `ink2` |
| Grouped-list section headers, footers | `.footnote` | Regular, `ink2` |
| State badges | `.footnote` | Semibold |
| Bar axis labels | `.caption` | Regular, `ink3` |

## 3. Layout and shape

- Screen side margin 16 pt. Gap between dashboard blocks 14 pt.
- List screens (Inventory, Settings, Kit detail, forms) use `List` with `.insetGrouped` and `bg` / `card` colors. Dashboard and Kits use custom cards with a 20 pt corner radius.
- Tap targets are at least 44 pt. Primary bottom buttons are 56 pt high, radius 16, full width inside the margins.
- One-handed use: the main action on a screen sits at the bottom (Add button on forms, Scan button on Inventory, Add/Skip on the walk confirm card).
- No custom status bar or home indicator; respect safe areas.

## 4. SF Symbols

| Use | Symbol |
| --- | --- |
| Tabs: Runway, Inventory, Kits, Settings | `gauge.with.needle`, `shippingbox`, `backpack`, `gearshape` |
| Scan | `barcode.viewfinder` |
| Add | `plus` |
| Manual entry | `pencil` |
| Food / Water | `fork.knife` / `drop` (`drop.fill` in the limiting callout) |
| State: Good / Use soon / Caution / Inspect / Expired | `checkmark` / `clock` / `arrow.triangle.2.circlepath` / `magnifyingglass` / `xmark` |
| Kit: complete / short / missing | `checkmark.circle.fill` / `minus.circle` / `circle.dashed` |
| Locked walk location | `lock.fill` |
| Torch | `flashlight.off.fill` / `flashlight.on.fill` |
| Location picker | `mappin.and.ellipse` |
| Printed date | `calendar` |
| Offline / not found | `wifi.slash` / `questionmark.circle` |
| Locations: pantry, garage, closet, vehicle | `cabinet`, `door.garage.closed`, `door.left.hand.closed`, `car` |
| Kits: go-bag, first aid, house | `backpack`, `cross.case`, `house` |
| Household person | `person.crop.circle` |
| Runway target | `target` |
| Export / import backup | `square.and.arrow.up` / `square.and.arrow.down` |
| Delete | `trash` |
| Target met | `checkmark.circle` |

## 5. Item and kit states

Badges always show a word and an icon; color is never the only signal.

| State | Badge | Runway |
| --- | --- | --- |
| Good | `good` on `goodBg`, `checkmark` icon optional | Both ends |
| Use soon | `ink` on `track`, `clock` in `amber` | Both ends |
| Caution | `amber` on `amberBg`, `arrow.triangle.2.circlepath` | High end only |
| Inspect | `amber` text and 1.5 pt `amber` outline, no fill, `magnifyingglass` | High end only |
| Expired | `red` on `redBg`, `xmark` | Not counted |

Kit requirements use Complete (`good`), Use soon (`amber` clock), Short (`amber` outline), Missing (`ink3` dashed outline), Expired (`red`).

Red appears only for Expired and for a runway below 3 days. Being under the target but above 3 days is shown in `tint`, not amber or red.

## 6. Custom components

**RunwayHeroCard.** Label "You could last about", the range in the hero style, "days", a callout, then RunwayBars. Callout variants:

- Below target: `drop.fill` + "Water is the weakest link" in `tint`.
- Below 3 days: same text pattern in `red` inside a `redBg` pill ("Water is below the 3-day minimum").
- At or above target: `checkmark` + "At your 14-day target" in `good`.

**RunwayBars.** One row per category on a shared scale from 0 to twice the target (28 days for a 14-day target).

- Track: 12 pt high, `track`, fully rounded.
- Low end: solid fill. High end: 45° stripes (3 pt on, 3 pt off) in the same color at about 55% opacity.
- Target tick: 2 pt `ink`, extending 5 pt above and below the track.
- Colors: the limiting category is `tint` (or `red` when critical); others are `ink3`.
- Accessibility: each row is one element: "Water, 9 to 11 days, target 14 days".
- At accessibility text sizes the label and value move above the bar and the axis reduces to a single "▲ 14-day target" marker.

**CategoryCard.** Two-up grid: icon and name (`.subheadline` semibold), value (`.title` rounded), one caption line. The limiting card gets a 2 pt inset `tint` stroke (`red` when critical). Stacks to one column at accessibility sizes.

**FocusRow.** 38 pt rounded-square icon tile (radius 12) with a soft background in the state's color, title (`.headline`), subtitle (`.subheadline`), chevron. Order follows the spec's Focus next priority. At accessibility sizes the text wraps freely and the chevron is hidden.

**StateBadge.** Capsule, 4 × 10 pt padding, `.footnote` semibold, 12 pt symbol. At accessibility sizes it moves to its own line under the row text.

**KitMeter.** One segment per requirement, 8 pt high, 3 pt gaps, 2 pt radius. Colors:

- Complete: `tint`.
- Use soon: `amberLine` fill.
- Short: `amberBg` with a 1.5 pt `amberLine` stroke.
- Missing: `track`.
- Expired: `red`.

**LotTimeline** (item detail). A single bar from acquired date to the end of the extension window, split into Good, Use soon, Caution and Inspect (outline) segments, with a 3 pt `ink` "Today" marker. Labels: Bought, Best by, Today, Rotate by.

**StretchGoalCard.** Shown on the dashboard only when every category's low end meets the target. `goodBg` card with "Every target met", a primary button for the next target up (3 → 7 → 14 → 30) and a "Not now" button that hides it until the target changes.

**WalkConfirmCard.** A light card floating over the camera with item, category, quantity stepper, date chip, and a 1:2 Skip / Add row. A running "N added this walk" pill sits under the locked-location chip.

## 7. Interaction notes

- **Haptics:** `.sensoryFeedback(.success)` on add; `.warning` when the same barcode is scanned again in a walk.
- **Duplicate scans in a walk:** offer "Add another (makes N)", "Oops, double scan" and "Different date".
- **Already in inventory:** list the existing lots with their dates and states, plus a "Different date: start a new lot" option (the default).
- **Barcode not found or offline:** keep the barcode, ask for name, category and (for food) calories per unit, then continue to the normal form.
- **Date entry:** Best by / Use by, year arrows, 12-month grid, a live state preview, and "No date on the package".
- **Large text:** use `@Environment(\.dynamicTypeSize).isAccessibilitySize` (or `ViewThatFits`) to:
  - stack category cards into one column;
  - move bar labels above their bars;
  - stack inventory row content (name, quantity, date, badge);
  - swap the By location / By category segmented control for a "Group: …" menu.
  Tab bar labels keep their system size.

## 8. Screen map

| Canvas artboard | Screen | Notes |
| --- | --- | --- |
| A · Hearth, A · Hearth dark | `RunwayView` | Dashboard tab |
| Dashboard · empty / critical / all good / expired | `RunwayView` states | Same view, different data |
| Water drill-down | `CategoryRunwayView` | Pushed from a category card; Food uses the same layout |
| Inventory (+ dark, AX) | `InventoryView` | Searchable list, group toggle, Expiring soon filter, Scan button |
| Item detail | `LotDetailView` | Pushed from a row |
| Add · scan, Scan · not found / offline, Scan · already have this | `ScanView` and sheets | Full-screen cover |
| Add · details, Unit picker, Printed date picker | `LotFormView` and sheets | Sheet |
| Pantry walk, same item again, done | `PantryWalkView` | Full-screen cover |
| Kits, Kit detail, Edit kit | `KitsView`, `KitDetailView`, `KitEditView` | Kits tab |
| Settings, Edit person, Edit location | `SettingsView` and sheets | Settings tab |
| First run · household | `OnboardingView` | Shown once, before the dashboard |
| Item states | Reference only | Badge and state rules |

## 9. Open decisions

- The designs show four tabs; the spec lists five (with Tasks). Tasks is out of scope for v1 screens.
- Target choices in the designs are 3 / 7 / 14 / 30 days; the spec's defaults are 3 / 14 / 30.
- The date picker preview assumes canned goods stay usable 24 months past best-by (the real value comes from the shelf-life profile and location climate).
- Items saved with no printed date count as Good.
