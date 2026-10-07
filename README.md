# Hearthstock

A personal, local-first iPhone app for tracking emergency-preparedness supplies (food, water, power, gear and go-bags) that answers one question at a glance: **how many days could we last, and what is the weakest link?**

Quantities live on lots in real units, so a 20 lb bag of rice is one entry, and every date is editable, so an old can with a past best-by date goes in as easily as one bought today. Everything stays on the device: no account, no server.

> Work in progress. The domain core and the database are built and tested; the first real screens are next. See the [Roadmap](#roadmap).

## How it works

- **Products and lots.** A product is what something is (white rice, measured in lb, about 1,650 kcal per lb). A lot is a specific quantity of it with its own dates, packaging and location. Calories, gallons and watt-hours are always derived from a lot's quantity, never typed in.
- **Sites.** Every runway belongs to one site (the house, a cabin). Locations belong to a site, so stock only counts where it physically is. The UI shows one site for now, but the schema has had sites from day one.
- **Shelf life.** A lot's usable-by date is its printed date plus an extension window from a conservative bundled table, adjusted for packaging (Mylar with O₂ absorbers lasts much longer) and the storage location's climate (a hot garage halves the window). Lots move through **Good → Caution → Inspect → Expired**; use-by items like formula and medication skip straight to Expired.
- **Runway.** Food and water runway are shown as a low–high range in days: the low end counts only in-date stock, the high end adds Caution and Inspect lots. Expired lots never count. Effective runway is the shortest category, and that category is the top priority.
- **Kits.** A go-bag or vehicle kit is a location with a manifest. Its lots are ordinary lots, excluded from the site's runway by default since their job is to leave with you.

The full product spec, including the data model, climate table, runway formulas and screens, is in [`docs/spec.md`](docs/spec.md).

## Roadmap

The work is built in slices, each a vertical piece that ends with tests green and, once there are screens, a walk-through on the simulator. Phases end at gates about real use rather than features: the schema has to survive contact with real shelves before sync locks it in.

### Done

- **Slice 1: domain core.** Calendar dates, typed IDs, units and quantities, shelf-life profiles and evaluator, climate resolution, the food and water runway calculator, and the sample-pantry regression fixture.
- **Slice 2: persistence.** The GRDB database and `v1_initial` migration, repositories behind Core protocols, live observation streams, shelf-life and climate overrides, and JSON backup export and import.

Today the app opens the database and shows a smoke screen with the site's lot count and effective runway; Debug builds add a "Load sample pantry" button. `swift test` runs 240 tests in 26 suites.

### Now: Slice 3, first real UI

Planned in [`docs/slice-3.md`](docs/slice-3.md). The goal is entering a real pantry by hand and reading the answer back:

- **Dashboard** with food, water and effective runway as a range, and the top of the Focus next list
- **Inventory** grouped by location or category, with search, an expiring-soon filter, and use, adjust, edit and delete
- **Add flow** for manual entry: a lot (and a product, if new) with any expiry date, past or future
- **Settings** for the household, locations and backup restore
- The **Use soon** shelf-life state, a nudge in the weeks before a printed date

### Next: Slice 4, scanning

- Barcode scanning with VisionKit, with Open Food Facts lookup for unknown products
- Live Text for reading printed dates
- Pantry walk mode: camera open, location fixed, one tap per item to back-fill shelf by shelf

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
- [Swift Testing](https://developer.apple.com/documentation/testing) for tests
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates the Xcode project from `project.yml`
- [Beads](https://github.com/gastownhall/beads) (`bd`) for task tracking

## Project layout

```
.
├── project.yml                     # XcodeGen manifest; the .xcodeproj is generated and gitignored
├── App/                            # SwiftUI app target
├── Packages/HearthstockKit/
│   ├── Sources/HearthstockCore/    # Pure domain: types, units, shelf life, runway math (Foundation only)
│   ├── Sources/HearthstockStore/   # GRDB schema, migrations, repositories, backup
│   ├── Tests/HearthstockCoreTests/ # Includes Fixtures/sample-pantry.json, the runway regression fixture
│   └── Tests/HearthstockStoreTests/
├── docs/
│   ├── spec.md                     # Product spec, the source of truth for behavior
│   └── slice-3.md                  # Plan for the next slice
└── .beads/                         # Beads issue database (managed by bd)
```

`HearthstockCore` imports only Foundation and never reads the clock: anything that depends on "today" takes the date as a parameter. Repository protocols live in Core and their GRDB implementations in Store, so the app only sees protocols and storage could be swapped without touching the math.

## Getting started

You need Xcode with Swift 6 and the iOS 18 SDK, and XcodeGen (`brew install xcodegen`).

```sh
# Run the domain and store tests (natively on the Mac, no simulator needed)
cd Packages/HearthstockKit && swift test

# Generate the Xcode project, then build the app for a simulator
xcodegen generate
xcodebuild -project Hearthstock.xcodeproj -scheme Hearthstock \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Use `xcrun simctl list devices available` to find a simulator name. Re-run `xcodegen generate` after adding or removing files or editing `project.yml`; never edit the generated project by hand.

The app stores its database at `Application Support/Hearthstock/hearthstock.sqlite`, which you can open in any SQLite tool.

## Contributing

Conventions for code, tests, migrations and commits are in [`CLAUDE.md`](CLAUDE.md). Work is tracked in Beads: `bd ready` lists unblocked tasks, and each task's description holds its acceptance criteria.

## License

[Apache 2.0](LICENSE)
