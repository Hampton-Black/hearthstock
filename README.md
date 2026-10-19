# Hearthstock

A personal, local-first iPhone app for tracking emergency-preparedness supplies (food, water, power, gear and go-bags) that answers one question at a glance: **how many days could we last, and what is the weakest link?**

Quantities live on lots in real units, so a 20 lb bag of rice is one entry, and every date is editable, so an old can with a past best-by date goes in as easily as one bought today. Point the camera at a barcode to add an item, or walk a shelf with the camera open and add it one tap per item. Everything stays on the device: no account, no server.

> Work in progress. Manual entry, barcode scanning, pantry walks and the runway dashboard work on a real iPhone; kits, tasks and reminders are still to come. See the [Roadmap](#roadmap).

## How it works

- **Products and lots.** A product is what something is (white rice, measured in lb, about 1,650 kcal per lb). A lot is a specific quantity of it with its own dates, packaging and location. Calories, gallons and watt-hours are always derived from a lot's quantity, never typed in.
- **Sites.** Every runway belongs to one site (the house, a cabin). Locations belong to a site, so stock only counts where it physically is. The UI shows one site for now, but the schema has had sites from day one.
- **Shelf life.** A lot's usable-by date is its printed date plus an extension window from a conservative bundled table, adjusted for packaging (Mylar with O₂ absorbers lasts much longer) and the storage location's climate (a hot garage halves the window). Lots move through **Good → Use soon → Caution → Inspect → Expired**; use-by items like formula and medication skip straight to Expired.
- **Undated lots.** A package with no printed date can be marked as having none: it then ages from an estimate (when you got it, plus a per-profile number of months that you can change per lot), and every date shown for it says "Est.". A lot with no date that isn't marked counts as Good but is listed under "needs a date" until you fix it.
- **Scanning.** A barcode you've scanned before fills in from your own data. An unknown one is looked up in [Open Food Facts](https://world.openfoodfacts.org) for its name, calories and a shelf-life guess, and either way one save writes the product and its lot together. Barcodes are normalized, so a scanned UPC and a typed EAN-13 find the same product.
- **Runway.** Food and water runway are shown as a low–high range in days: the low end counts only in-date stock, the high end adds Caution and Inspect lots. Expired lots never count. Effective runway is the shortest category, and that category is the top priority.
- **Pantry walk.** Lock a location, keep the camera open, and each scan raises a card: quantity, printed date, Add. Each Add saves immediately and can be undone; scanning the same item again offers "add another". The summary shows what the walk did to your runway and which items still need a date.
- **Kits.** A go-bag or vehicle kit is a location with a manifest. Its lots are ordinary lots, excluded from the site's runway by default since their job is to leave with you.

### Privacy

The only network call the app makes is the Open Food Facts lookup, and it sends only the barcode, with a User-Agent naming the app and a contact address, as Open Food Facts asks. Each barcode is looked up at most once: the answer (found or not) is saved on the phone and reused for every later scan, offline too. Lookups can be switched off in Settings, and the saved answers cleared.

The full product spec, including the data model, climate table, runway formulas and screens, is in [`docs/spec.md`](docs/spec.md).

## Roadmap

The work is built in slices, each a vertical piece that ends with tests green and, once there are screens, a walk-through on the simulator. Phases end at gates about real use rather than features: the schema has to survive contact with real shelves before sync locks it in.

### Done

- **Slice 1: domain core.** Calendar dates, typed IDs, units and quantities, shelf-life profiles and evaluator, climate resolution, the food and water runway calculator, and the sample-pantry regression fixture.
- **Slice 2: persistence.** The GRDB database and `v1_initial` migration, repositories behind Core protocols, live observation streams, shelf-life and climate overrides, and JSON backup export and import.
- **Slice 3: first real UI** ([plan](docs/slice-3.md)). The Runway dashboard (food, water and effective runway as a range, with Focus next), Inventory (by location or category, search, expiring-soon filter, use, adjust, edit and delete), a manual Add flow with any date past or future, Settings for the household, locations and backup restore, and the **Use soon** state.
- **Slice 4: scanning, pantry walk and undated lots** ([plan](docs/slice-4.md), [walk-through](docs/slice-4-walkthrough.md)). Barcode scanning with VisionKit and a hand-typed fallback; Open Food Facts lookups with a local cache and a Settings switch; "Already have this" to add to an existing lot; pantry walk mode with undo and a runway before/after summary; estimated dates for packages with no printed date; Live Text for reading printed dates; and running on a real iPhone.

`swift test` runs 438 tests in 54 suites, and the Slice 4 walk-through has been run on an iPhone 15 Pro.

### Now: Slice 5, calories and categories at scan time

Being planned. Open Food Facts usually knows calories per serving but rarely the package size, and often has no categories, so a scanned can tends to need its calories and shelf-life profile fixed by hand afterwards. Slice 5 fills them in at the shelf:

- Calories per item from a single-serving package, from servings per container or the net weight (one question on the scan card), or by reading the Nutrition Facts panel with Live Text
- A shelf-life profile guessed from the product name when there are no categories, shown as a guess you can change

### Rest of v1

- Kit templates and gap checking (per-person go-bag, first-aid kit, house preps, vehicle kit) and the Kits tab
- Household readiness checklists for water, power, cooking, food preservation, lighting and comms
- Maintenance tasks and the Tasks tab
- Local reminders for expiring lots and maintenance
- The rest of the Focus next list: missing capabilities, kit gaps and overdue maintenance

### After the pantry is entered

- Capabilities such as water filters, solar panels and stoves, with non-potable water counted up to treatment capacity
- Power runway from batteries and fuel, with derated solar recharge
- Cooking fuel as a fourth runway, scheduled last in v1.1
- A home screen widget, Siri and Shortcuts, and CSV export

### v2

- CloudKit sharing so a second person in the household can use the same data
- Multiple sites: a site switcher, side-by-side runways that are never summed, relocation scenarios and resupply lists

## Stack

- Swift 6 in language mode 6 with strict concurrency, SwiftUI, iOS 18+, iPhone only
- SQLite through [GRDB 7](https://github.com/groue/GRDB.swift), the only third-party dependency
- VisionKit's `DataScannerViewController` for barcodes and Live Text
- [Open Food Facts](https://world.openfoodfacts.org) API v3 for unknown barcodes, the only network service
- [Swift Testing](https://developer.apple.com/documentation/testing) for tests
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the Xcode project from `project.yml`
- [Beads](https://github.com/gastownhall/beads) (`bd`) for task tracking

## Project layout

```
.
├── project.yml                     # XcodeGen manifest; the .xcodeproj is generated and gitignored
├── Config/                         # Signing (Signing.xcconfig; your team ID goes in a gitignored Local.xcconfig)
├── App/                            # SwiftUI app target: Dashboard, Inventory, Add, Scan, Walk, Settings
├── Packages/HearthstockKit/
│   ├── Sources/HearthstockCore/    # Pure domain: types, units, shelf life, runway math, barcodes, scan logic (Foundation only)
│   ├── Sources/HearthstockStore/   # GRDB schema, migrations, repositories, backup
│   ├── Sources/HearthstockLookup/  # Open Food Facts client and lookup cache: the only code that uses the network
│   ├── Tests/HearthstockCoreTests/ # Fixtures: sample-pantry.json (runway regression) and recorded Open Food Facts responses
│   ├── Tests/HearthstockStoreTests/
│   └── Tests/HearthstockLookupTests/ # Stubbed network; no test reaches the internet
├── docs/
│   ├── spec.md                     # Product spec, the source of truth for behavior
│   ├── design.md, design/          # Visual design: tokens, components, screen references
│   ├── device-setup.md             # Running on your own iPhone
│   └── slice-N.md                  # Each slice's plan, with a walk-through script for the finished ones
└── .beads/                         # Beads issue database (managed by bd)
```

`HearthstockCore` imports only Foundation and never reads the clock: anything that depends on "today" takes the date as a parameter. Repository protocols live in Core and their GRDB implementations in Store; the lookup protocol lives in Core and its network client in Lookup. The app only sees protocols, so storage or the lookup source could be swapped without touching the math.

## Getting started

You need Xcode with Swift 6 and the iOS 18 SDK, and XcodeGen (`brew install xcodegen`).

```sh
# Run the domain and store tests (natively on the Mac, no simulator needed)
cd Packages/HearthstockKit && swift test

# Generate the Xcode project, then build the app for a simulator
xcodegen generate
xcodebuild -project Hearthstock.xcodeproj -scheme Hearthstock \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Use `xcrun simctl list devices available` to find a simulator name. The simulator has no camera, so the scanner offers **Type a barcode** instead; everything after a barcode is read works the same.

To run on your own iPhone (needed for the camera), copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, put your Apple developer team ID in it, and follow [`docs/device-setup.md`](docs/device-setup.md). Re-run `xcodegen generate` after adding or removing files or editing `project.yml`; never edit the generated project by hand.

The app stores its database at `Application Support/Hearthstock/hearthstock.sqlite`, which you can open in any SQLite tool.

## Contributing

Conventions for code, tests, migrations and commits are in [`CLAUDE.md`](CLAUDE.md). Work is tracked in Beads: `bd ready` lists unblocked tasks, and each task's description holds its acceptance criteria.

## License

[Apache 2.0](LICENSE)
