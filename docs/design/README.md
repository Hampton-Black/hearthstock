# Design references

Visual references for every screen on the Hearthstock design canvas. `docs/design.md` is the source of truth for tokens, text styles, SF Symbols, components and state rules; these files show what each screen looks like.

- `screens/` holds a PNG of each screen (390 pt wide, rendered at 2×). Look at these for layout, hierarchy and proportion.
- `canvas/` holds the source of each screen. Read these for exact copy, colors, sizes and spacing.

## How to use them

- **These are references to translate into SwiftUI, not code to port.** The source files are a prototyping format: `{{…}}` placeholders, `<sc-for>` / `<sc-if>` blocks, and a small `Component` class with `renderVals()` that fakes state for clickable prototypes. Ignore that machinery and the hover, swipe and toggle logic; build the screen with native SwiftUI views, the tokens in `design.md`, and the Core and view-model rules in `CLAUDE.md`.
- **Behavior comes from `docs/spec.md`.** If a screen and the spec disagree on what something does, the spec wins.
- **The screenshots use Inter as a stand-in for SF Pro.** The app uses the system font and Dynamic Type text styles, with rounded numerals (`.fontDesign(.rounded)`) for numbers, so real spacing and line breaks will differ slightly. Some screens with tweakable variants show their default variant only (noted below).
- **Screens marked "scrolled" are taller than a phone screen** so the whole scroll content is visible.

## Which screens apply now

**Slice 3 builds the `S3-*` screens.** They supersede the earlier rows for this slice: three tabs (Runway, Inventory, Settings), a "+" toolbar button instead of Scan, and manual entry first. The other screens show the fuller app (scanning, pantry walk and the Kits tab arrive in later slices) and are still the reference for visual style, states and components.

| Screen | File stem | Notes |
| --- | --- | --- |
| Dashboard | `S3-Dashboard` | Task 10 |
| Dashboard, no household | `S3-Dash-NoHousehold` | Task 10 problem state |
| Inventory, swipe + filter | `S3-Inventory` | Task 9; first row shown swiped to Use / Adjust |
| Use / Adjust sheet | `S3-UseSheet` | Task 9; Use mode shown, Adjust is the same sheet |
| Lot detail | `S3-LotDetail` | Task 9 |
| Add lot, manual | `S3-AddLot` | Task 8 |
| Add lot, saved | `S3-AddSaved` | Task 8; "old beans" example shown |
| Product picker | `S3-ProductPicker` | Task 7 |
| Product form | `S3-ProductForm` | Task 7; New mode shown, Edit mode adds the warning banner and locks unit kind |
| Settings | `S3-Settings` | Tasks 6 and 11 |
| Edit location | `S3-Location` | Task 6 |
| Restore backup | `S3-Restore` | Task 11; valid-file state shown |

Later-slice and reference screens:

| Group | File stems |
| --- | --- |
| Dashboard directions (A is the chosen one) | `Main`, `Main-Dark`, `DashB-Ledger`, `DashC-Timeline` |
| Dashboard states | `Dash-Empty`, `Dash-Critical`, `Dash-AllGood`, `Dash-Expired` |
| Item states reference | `States` |
| Core screens | `Inventory`, `Inventory-Dark`, `Add-Scan`, `Add-Form`, `Walk-Mode`, `Kits`, `Kit-Detail`, `Settings` |
| Details and setup | `Item-Detail`, `Water-Detail`, `Onboarding`, `Edit-Member`, `Edit-Location`, `Kit-Template` |
| Adding items, edge cases (Slice 4) | `Scan-NotFound`, `Scan-Existing`, `Picker-Unit`, `Picker-Date`, `Walk-Duplicate`, `Walk-Summary` |
| Dark mode | `AddForm-Dark`, `Kits-Dark`, `KitDetail-Dark`, `Settings-Dark` (each wraps its light screen with dark mode on) |
| Accessibility text size (AX1) | `Main-AX`, `Inventory-AX` |

Each stem has `screens/<stem>.png` and `canvas/<stem>.dc.html`.
