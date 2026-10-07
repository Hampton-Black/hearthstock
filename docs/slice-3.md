# Slice 3: first real UI (manual entry)

**Goal:** Hampton can enter his real pantry by hand on the phone and read the answer back. After this slice the app has a Dashboard that shows food, water and effective runway as a low–high range with the top of the Focus next list, an Inventory that lists every lot with its shelf-life state and lets him use up, adjust, edit or delete it, an Add flow that creates a lot (and a product, if new) quickly with any expiry date past or future, and Settings for the household, locations and backup. Barcode scanning comes next; this slice proves the screens, the view-model pattern and the entry fields against real shelves first.

Read first: CLAUDE.md (Architecture rules, Working style), docs/spec.md → **Runway dashboard**, **Screens and flows** and **Data model** (Units, Consumption, Shelf life), and the Slice 1–2 code: `RunwayCalculator`, `ShelfLifeEvaluator`, `ShelfLifeProfileResolver`, `resolvedClimate`, the repository protocols in `Repositories.swift`, `GRDBBackup`, and the app target (`AppServices`, `RootView`, `ContentView`, `SamplePantry`).

**Slices 1 and 2 are the ground truth for type names and shapes.** Where this file names a type or field differently from the code, follow the code and mention the difference in your plan. If a Core or Store type needs to change, list it in the plan before touching it.

Start in plan mode: propose the new Core types (per-lot status, Focus next, inventory query), the Store additions, the screen and view-model list with file layout, and the test plan, then wait for approval. Work the tasks in dependency order and commit after each task.

**View models subscribe, they don't poll.** Every screen that shows site data is driven by `RunwayInputsLoader.observeRunwayInputs(siteID:)` (or `LotRepository.observeLots(siteID:)` where lots alone are enough), as Slice 2 set up. Writes go through the repository protocols; the observation brings the new state back. No screen keeps its own copy of the data and patches it after a save.

**Logic lives in HearthstockCore, not in views.** Anything that decides what to show (a lot's state, the Focus next order, what "expiring soon" means, grouping and search) is a pure, tested Core function that takes `today` as a parameter. View models are `@MainActor @Observable` and stay thin: subscribe, call Core, format. There is no app test target in this slice, so whatever isn't in Core is verified by hand.

## Decisions taken in this plan

These are defaults chosen where the spec leaves a choice open. Hampton can overturn any of them before this goes into Beads.

1. **Manual entry only.** VisionKit barcode scanning, Live Text dates, Open Food Facts and pantry walk mode are Slice 4. The Add flow opens on manual entry, and the spec's "camera opens by default" arrives with the scanner. A barcode can still be typed into the product form.
2. **Three tabs now: Dashboard, Inventory, Settings.** Kits and Tasks tabs arrive with the slices that give them content, so no tab is a placeholder. Add is a toolbar button on Dashboard and Inventory.
3. **Days are shown as whole days, rounded down** ("12–19 days"; "under 1 day" below 1; a single number when both ends round the same). Core keeps returning unrounded `Double`s.
4. **Backup restore replaces everything.** `GRDBBackup.import` only fills an empty database, and the app always has the default site, so restore becomes "erase and import" in one transaction, behind a confirmation that says what will be lost and offers to export first.
5. **A lot can be deleted** (for entry mistakes), separately from using it up. Using it up archives at zero, as Slice 2 built; delete removes the row and its shelf-life override.
6. **Calories are entered per base unit, with a per-package helper.** The product form shows "kcal per lb" (or per count, per gal) and offers "kcal per package + package size" that converts on entry. Only the per-base-unit value is stored.
7. **"Expiring soon"** means Caution, Inspect or Expired, or Good with a printed date within the next 30 days. The 30 days is a named constant in Core.
8. **Last-used location** is remembered per site in `UserDefaults`. It's a UI convenience, not domain data, so it stays out of the database and the backup.
9. **Shelf-life profiles get display names in the bundled JSON** (a `name` field per profile), so the product form's picker reads as words, not keys. Defaults stay data.
10. **Kits are a toggle on a location** in this slice ("This is a kit", plus "Counts toward runway", off by default). Templates, inspection and the Kits tab are later.

## Out of scope for this slice

Barcode and Live Text scanning, Open Food Facts lookup, pantry walk mode (Slice 4); the Kits and Tasks tabs, kit templates and gap checking, readiness templates, maintenance tasks; capabilities and water treatment, power runway, cooking fuel; Focus next items 3–5; editing targets, climate multipliers or the shelf-life table in Settings (per-product and per-lot overrides included); a site switcher or a second site in the UI; notifications, widgets, App Intents; CSV export; CloudKit sync.

## Definition of done

- `swift test` green; report the test count, including every Slice 1 and Slice 2 test. The sample-pantry fixture test and its Store round-trip must still pass with unchanged expected values.
- `xcodegen generate` and the `xcodebuild` build (Debug and Release) both succeed.
- HearthstockCore still imports only Foundation; no view or view model imports GRDB or HearthstockStore apart from `AppServices`.
- Hampton has walked the Task 12 script on the simulator and confirmed each step.
- The summary lists the screens and view models, the new Core and Store API, every assumption made, and any Slice 1–2 types changed and why.

## Task 1: Per-lot status in Core

The Inventory and the Focus next list need each lot's state, and that state must be exactly what the runway used. Today that logic is private to `RunwayCalculator`.

- [ ] A Core function that takes `RunwayInputs`, the profile table and `today`, and returns a status per unarchived lot: the lot, its product, its location chain (for a "Garage › Shelf 2" path), resolved climate and humidity, the `ShelfLifeEvaluation` (state, usable-by, flags), and whether it counts toward this site's runway (kit exclusion included). Lots the runway can't place (missing product, unresolved location, missing profile) come back with that problem rather than being dropped.
- [ ] `RunwayCalculator` uses this function for its own per-lot step, so the two can't drift. Its public API and results don't change.

**Tests:** the fixture's lots get the states the Slice 1 tests imply (the 14-month-old beans, the go-bag MRE excluded from runway, the Mylar beans with no printed date flagged `missingDate`); a lot at another site is absent; a missing product is reported, not dropped; the fixture runway test passes unchanged.

**Done when:** every lot state the UI shows comes from this one function.

## Task 2: Focus next in Core

- [ ] A Core function that builds the Focus next list from a `SiteRunway` and the Task 1 statuses, in the spec's priority order, for items 1 and 2 only:
  1. The limiting category with the amount needed to reach the next target, in the category's natural unit ("+18 gal water to reach 14 days", "+42,000 kcal food to reach 14 days"). Expressed as data (category, amount, unit, target days); wording is the app's job.
  2. Lots in Caution or Inspect, soonest usable-by first, ties broken by product name.
- [ ] Runway problems that stop the math (no occupants) come first as their own item; lots missing nutrition or water volume appear as one item each with their count.
- [ ] Items 3–5 (missing capabilities, kit gaps, maintenance) are not built; the type leaves room for them.

**Tests:** limiting-category item uses the next target's shortfall; no item 1 when the effective low is already past the last target; Caution and Inspect ordered by usable-by; expired lots aren't listed as "eat or rotate"; zero occupants puts the problem first; the fixture produces the expected list.

**Done when:** the Dashboard can render Focus next without deciding anything itself.

## Task 3: Inventory query in Core

- [ ] Group the Task 1 statuses by location (full path, parents before children, kits marked) or by category, with lots inside each group ordered by state severity (Expired, Inspect, Caution, Good) then usable-by.
- [ ] Search matches product name or lot notes, ignoring case and diacritics.
- [ ] Filters: expiring soon (Decision 7), and one category (for the Dashboard's drill-in). Filters and search combine.

**Tests:** table-driven grouping and ordering over the fixture; search hits name and notes; the expiring-soon boundary at exactly 30 days; category filter plus search together; an empty result is an empty list, not an error.

**Done when:** Inventory's view model is a subscription plus one call to this function.

## Task 4: Store and data gaps

Small additions the screens need. Each one is listed in the plan before it's made.

- [ ] `LotRepository.delete(_:)`: removes the lot and its shelf-life override; deleting a missing lot does nothing.
- [ ] `KitRepository.delete(_:)`: removes the kit and clears its location's kit link, so a location can stop being a kit and later be deleted.
- [ ] `ProductRepository.list()`, if `search(name: "")` isn't clear enough at the call site; otherwise note that `search` covers it.
- [ ] Shelf-life profiles gain a display `name` in `shelf-life-defaults.json` and `ShelfLifeProfile` (Decision 9). Loading still fails clearly on a profile without one.
- [ ] Restore (Decision 4): a Store operation that erases every table and imports a backup document in one transaction, so a bad file leaves the old data in place. `GRDBBackup.import` keeps its empty-database rule.
- [ ] `GRDBBackup` joins `AppServices` behind a small protocol in Core, so Settings doesn't see GRDB.

**Tests:** delete a lot with an override and both are gone; delete a kit and its location can then be deleted; every bundled profile has a non-empty name; restore over a populated database leaves exactly the file's contents; a restore that fails partway leaves the original data intact; export → restore → export matches apart from `exportedAt`.

**Done when:** every write the screens need exists as a repository call.

## Task 5: App shell and view-model pattern

- [ ] A `TabView` with Dashboard, Inventory and Settings, replacing the smoke `ContentView`. `RootView`'s open-or-show-error behavior stays.
- [ ] One view-model pattern, used by every screen: `@MainActor @Observable`, started from `.task`, subscribing to `observeRunwayInputs(siteID:)` and holding the latest snapshot plus Core results. Cancelling the task ends the subscription.
- [ ] `today` is computed once in the app and refreshed when the app becomes active and when the calendar day changes, so a phone left open overnight moves lots from Good to Caution without a relaunch.
- [ ] Errors from a write show as an alert with the error text; a failed subscription shows the error in place of the screen's content.
- [ ] The DEBUG "Load sample pantry" button moves to a Developer section at the bottom of Settings (DEBUG builds only).

**Done when:** the app launches into the three tabs, each tab shows live data for the default site, and Release builds have no sample loader.

## Task 6: Settings: household and locations

- [ ] Site name, editable.
- [ ] Household: add, edit and remove people (name, kcal/day defaulting to 2,000, water gal/day defaulting to 1.0).
- [ ] Locations as a tree: add, rename, move under a parent, set climate class (with "inherit from parent"), humidity, and the kit toggles (Decision 10). Show each class's multiplier and example spots from the spec's climate table as help text.
- [ ] Deleting a location that still holds lots, has children or is a kit shows why, using the typed `RepositoryError`s, instead of failing silently.

**Done when:** a new user can describe their household and storage without the sample loader.

## Task 7: Product form

- [ ] Create and edit a product: name, category, unit kind (mass, volume, energy, count), calories per base unit with the per-package helper (Decision 6), potable water per base unit (prefilled 1 gal per gal for water by volume, with a "not potable" switch that clears it), shelf-life profile picked by name, optional barcode typed by hand. Role is fixed to supply in this slice.
- [ ] Unit kind can't change once the product has lots, since their quantities are stored in its base unit.
- [ ] A product picker: search existing products by name, most recently used first when the search is empty, with "New product" always one tap away.
- [ ] Editing a product says it affects every lot of that product.

**Done when:** a product can be created inline from the Add flow and edited later from a lot.

## Task 8: Add flow

The spec's goal is a bulk item or an old can entered in under 15 seconds.

- [ ] One sheet: product (picker or new), quantity with a unit picker limited to the product's unit kind and an optional "× packs" multiplier (24 × 0.5 L → 3.17 gal), printed date (any date, past or future, or "No expiry"), acquired date (defaults to today, editable), packaging, location (last-used preselected, Decision 8), opened, notes.
- [ ] Conversion to the base unit happens on save with `Quantity.inBaseUnit()`; the sheet shows the stored amount ("= 3.17 gal") before saving.
- [ ] Save and add another keeps product-independent choices (location, acquired date) for the next entry.
- [ ] After saving, the new lot's state is visible on the confirmation, so a back-filled old can shows Caution or Expired right away.

**Done when:** Hampton can enter "20 lb white rice, garage, best-by 2025-03" and "6 cans black beans, printed 14 months ago" and see their states.

## Task 9: Inventory

- [ ] Lots grouped by location or by category (segmented control), with search and an Expiring soon filter (Task 3). Each row: product name, quantity in a readable unit, location path when grouped by category, state badge (Good normal, Caution and Inspect amber with Inspect's check prompt, Expired red) and flag icons (missing date, power-dependent, humidity risk).
- [ ] Swipe to **Use**: enter an amount in any unit of the product's kind (count products prefill 1); over-consuming shows the available amount. Swipe to **Adjust**: set the remaining quantity directly, for corrections.
- [ ] Lot detail: every field, usable-by date, why it's in its state (printed date, profile, window, climate), and Edit, Delete (Decision 5) and Archive.
- [ ] Opening Inventory from a Dashboard category shows that category, with a visible way to clear the filter.

**Done when:** every lot in the sample pantry is findable by search and by location, and Use, Adjust, Edit and Delete each change the Dashboard live.

## Task 10: Dashboard

- [ ] Food and water cards, each with days as a range (Decision 3), the amount on hand (kcal, gal) and the daily need. Water shows untreated non-potable gallons beside the figure, never inside it.
- [ ] Effective runway range with the limiting category called out, and a one-line reminder to plan around the low number.
- [ ] Focus next (Task 2), with each Caution or Inspect lot opening its lot detail.
- [ ] Empty and problem states: no people ("Add your household to compute runway" linking to Settings), no lots ("Add your first item"), and lots missing calories or water volume linking to their products.
- [ ] Tapping a category card opens Inventory filtered to that category (Task 9).

**Done when:** the Dashboard with the sample pantry shows the same food, water and effective low/high as the fixture test, rounded down.

## Task 11: Backup in Settings

- [ ] Export: writes the JSON backup and opens the share sheet, named with the site and date.
- [ ] Restore: picks a file, shows what it contains (export date, counts of sites, lots and products) and what will be replaced, offers "Export current data first", then replaces everything (Task 4). The app reloads onto the restored default site.
- [ ] A file that isn't a readable backup shows the `BackupError` text and changes nothing.

**Done when:** export, erase-and-restore and a second export round-trip on the simulator with the same lots.

## Task 12: Simulator walk-through

- [ ] Write the step-by-step script (what to tap, what to see) covering a fresh install, household and locations, adding the two Task 8 items plus a case of water, using and adjusting lots, the Dashboard drill-in, an Expiring soon filter, and an export/restore round-trip.
- [ ] Run `swift test`, `xcodegen generate` and both builds; hand the script to Hampton and wait for his report. Fixes found here go in this task's commits.

**Done when:** Hampton confirms every step.

## Dependencies

- Task 1 blocks Tasks 2 and 3.
- Tasks 1, 4 and 5 have no Slice 3 dependencies and can start in any order.
- Task 6 depends on Tasks 4 and 5.
- Task 7 depends on Tasks 4 and 5.
- Task 8 depends on Tasks 6 and 7.
- Task 9 depends on Tasks 3, 4 and 5.
- Task 10 depends on Tasks 2, 5 and 9 (for the category drill-in).
- Task 11 depends on Tasks 4 and 5.
- Task 12 depends on Tasks 8, 9, 10 and 11.
