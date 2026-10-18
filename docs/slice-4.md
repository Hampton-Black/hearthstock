# Slice 4: scanning, pantry walk and undated lots

**Goal:** Hampton can back-fill the real pantry by walking it with the phone. Pointing the camera at a barcode is the default way to add an item: a known barcode fills in from local data, an unknown one is looked up in Open Food Facts once and remembered, and either way one save writes the product and its lot together. The printed date can be read off the package with Live Text. Pantry walk mode keeps the camera open with the location locked, so a shelf goes in one tap per item, and ends with a summary showing what the walk did to the runway. Lots with no printed date stop passing silently as Good: a lot either has a date, is marked "no printed date" and gets an estimated expiry from its acquired date, or is flagged as missing a date. After this slice the whole house should be enterable in an evening.

Read first:
- `CLAUDE.md`.
- `docs/slice-3.md` (the view-model pattern and the Decisions this slice builds on).
- `docs/spec.md`: **Add flow**, **Products from a scan** (known / found / not found, the unit-kind rule, one barcode per product), **Back-fill mode**, **Shelf life** and the shelf-life state table.
- `docs/design.md`: §1 (camera screens are always dark), §6 WalkConfirmCard, §7 (haptics, duplicate scans, already in inventory, not found or offline, date entry), §8 screen map.
- The design references: `Add-Scan`, `Scan-Existing`, `Scan-NotFound`, `Walk-Mode`, `Walk-Duplicate`, `Walk-Summary`, `Picker-Date`.
- The Slice 3 code: `ProductDraft`, `LotRepository.save(_:newProduct:)`, `AddLotModel` / `AddLotSheet`, `PrintedDateSheet`, `ProductForm`, `ShelfLifeEvaluator`, `ShelfLifeOverride`, `LotStatusEvaluator`, `FocusNext`, `InventoryQuery`, `LotText`, `Preferences`.

**Slices 1–3 are the ground truth for type names and shapes.** Where this file names something differently from the code, follow the code and mention the difference in your plan. If a Core or Store type needs to change, list it in the plan before touching it.

Start in plan mode: propose the new Core types (undated-lot rules, barcode normalization, scan resolution, the debouncer, the Open Food Facts mapping, the walk session, the date parser), the new `HearthstockLookup` target, the Store migrations, the screen and view-model list with file layout, and the test plan. Then wait for approval. Work the tasks in dependency order and commit after each task.

**The save path doesn't change.** Every new product still goes through `ProductDraft` and `LotRepository.save(_:newProduct:)`, and every new lot through `save(_:)`. Scanning only decides what the draft and form start with, so a cancelled scan never leaves an orphan product.

**Logic lives in HearthstockCore; the network and the camera don't.** Barcode normalization, scan resolution, debouncing, mapping an Open Food Facts response to a draft, reading a date out of recognized text, the walk session and the undated-lot rules are pure, tested Core functions with time and `today` passed in. Core still imports only Foundation and never touches the network. VisionKit stays in the app target.

**The camera needs a real iPhone.** The simulator has no camera. Everything after "a barcode was read" must therefore be reachable by typing a barcode (Decision 13), so most of this slice can still be checked on the simulator. Camera-only behavior is called out in the Task 14 script.

## Decisions taken in this plan

These are defaults chosen where the spec or the 2026-10-08 undated-lots decision leaves a choice open. Hampton can overturn any of them before this goes into Beads.

**Undated lots**

1. **A lot records whether its package has no printed date.** `Lot` gains `noPrintedDate: Bool` (default false). A printed date and the flag can't both be set. Three cases, for profiles whose date type is best-by or use-by:
   - a printed date: aged from it, as today;
   - no printed date, flag off: Good, counted in both ends of the runway as Slice 3 does, and flagged `missingDate` so it shows in Inventory, Focus next and the walk summary until the date is added or the box is ticked;
   - no printed date, flag on: an **estimated expiry** of acquired date + the undated shelf life (Decision 2), and no `missingDate` flag.
   Profiles whose date type is none (honey, salt, stored tap water) ignore the flag and age as they do today.
2. **The undated shelf life is a per-profile default, overridable per lot** (confirmed by Hampton, 2026-10-11). It lives on the profile in the bundled `shelf-life-defaults.json`, reusing the existing `rotationMonths` field ("months from the acquired date when there's no printed date"). The per-lot override reuses `ShelfLifeOverride.rotationMonths`, which Slice 2 already stores. The product-level override exists in the schema but stays out of the UI. The proposed defaults are in Task 2.
3. **An estimated expiry ages like stored tap water does now:** Good from the acquired date, Inspect for the final 20% of the span, then Expired. There's no Caution phase, since the estimate already is the whole usable life, and no Use soon, which belongs to printed dates. Lots with an estimate carry a new `LotFlag.estimatedDate`, and every place that shows the date says "Est." so it never reads as printed.
4. **Existing lots migrate with the flag off.** Slice 3 saved "No date on the package" and "not set" the same way (no printed date), so after the migration those lots show as missing a date until Hampton ticks the box or adds the date. Lots of no-date profiles (honey, tap water) are unaffected.

**Barcodes and lookups**

5. **Barcodes are stored normalized.** UPC-A (12 digits), UPC-E (expanded) and EAN-13 become one 13-digit GTIN, and EAN-8 stays 8 digits. The check digit is validated. A scan and a hand-typed code for the same can then find the same product. A typed code with a bad check digit is refused with a clear message.
6. **Online lookup is on by default, with a switch in Settings.** It's the only network call in the app, and it sends only the barcode. When it's off, an unknown barcode that isn't already cached goes straight to the "We don't know this one yet" form. The switch lives in `Preferences` (`UserDefaults`), since it's a device setting rather than domain data.
7. **Each barcode leaves the phone at most once.** Every answer from Open Food Facts, found or not found, is kept in a local lookup cache keyed by the normalized barcode, whether or not the item is then saved. Later scans of that barcode read the cache and never touch the network, with lookups switched on or off. The only way to ask again is the explicit **Look up online** button (Task 11), which replaces that barcode's cache entry. "Couldn't look it up right now" (offline, timed out, rate limited, server error) is not cached, so the next scan tries again. Details in Task 7.
8. **The cache is part of the backup.** It's small, and keeping it means a restore onto a new phone doesn't send every barcode again. Settings shows how many lookups are saved and offers **Clear saved lookups**.
9. **Open Food Facts API v3.** The other draft of this plan says their docs mark v2 as deprecated; verify that against the current docs before building Task 7, and note the endpoint in the plan. Reads need no account, only a custom User-Agent of the form `Hearthstock/<version> (<contact>)`. The contact is an address Hampton chooses; the repo may become public, so pick one you're fine publishing. Set it in `project.yml` as a build setting, not in code.
10. **A new `HearthstockLookup` target holds the network client and the caching wrapper.** Core keeps the `ProductLookupService` and `LookupCacheRepository` protocols and the pure response-to-draft mapping. `HearthstockLookup` imports Foundation and Core only and is the one place in the codebase that uses `URLSession`. CLAUDE.md's layout and architecture rules get a line saying so (Task 7).
11. **Lookups are short and never queue.** The timeout is about 4 seconds, so a weak garage signal doesn't stall the walk. Open Food Facts lists a rate limit of 15 product reads per minute (verify), so the client keeps its own cap below that. Over the cap, offline, timed out or any server error all give the same result: "couldn't look it up right now". That leads to the not-found form, with a note that a later lookup can fill in what's missing.
12. **Unit kind for a looked-up product follows the spec's rule.** The thresholds use net quantity: over 907 g (2 lb) is mass, over 3.785 L (1 gal) is volume, anything smaller is count (one item per can, jar or bottle). An unknown net quantity defaults to count. The choice is visible and editable before the first save, as the spec requires.

**Scanning and the walk**

13. **"Type a barcode" is always one tap away on the scanner,** in every build. It covers smudged labels, devices that can't scan, and the simulator, and feeds exactly the same path as a camera read.
14. **The Add button opens the scanner.** The toolbar "+" on Dashboard and Inventory opens the Add · scan screen as a full-screen cover, with **Type it in** one tap away opening the Slice 3 sheet. Inventory also gets the design's Scan button. The three tabs stay; Kits and Tasks are still later.
15. **Pantry walk saves each item when you tap Add, not at Done.** Undo then deletes or reverts a real write (including a product created by that Add, when it has no other lots), and leaving the walk halfway or the app being killed loses nothing.
16. **Printed dates are optional during a walk.** The date chip starts unset; skipping it saves the lot flagged as missing a date (Decision 1). The walk summary gathers those under "N items need a date". The chip also offers "No printed date" (the estimated expiry) and Live Text.
17. **"Same date as one of these" and "Add another" add to the existing lot** through a new `LotRepository.add(_:amount:)`, in one write. The lot keeps its original acquired date.
18. **Live Text proposes, Hampton confirms.** A date read from the package fills the date sheet's preview with its state; it's never saved without Done. Ambiguous numeric dates (03/05/27) read as US month/day, and when two readings are possible the earlier one is offered first, since an earlier date is the safer mistake. A month-only date is saved as the 1st, as Slice 3 does. Live Text is the last task, so it can be cut without touching the rest.

## Out of scope for this slice

- Kits, kit templates and the Kits tab; onboarding and editing targets; editing the shelf-life table or climate multipliers in Settings.
- Per-product shelf-life overrides in the UI; product roles other than supply.
- Contributing new products back to Open Food Facts, product photos, and more than one barcode per product.
- An offline lookup queue, background retries, or expiring cache entries on a timer.
- Scanning to consume (Use) from the camera.
- Power, capabilities, cooking fuel, notifications, widgets, App Intents, CSV export and CloudKit sync.

## Definition of done

- `swift test` green; report the test count, including every Slice 1–3 test. The sample-pantry fixture test and its Store round-trip pass with unchanged expected values (the homemade jerky stays Good and flagged `missingDate`).
- `xcodegen generate` and the `xcodebuild` build (Debug and Release) both succeed, and the app installs and runs on Hampton's iPhone.
- HearthstockCore still imports only Foundation. Only `HearthstockLookup` uses `URLSession`, and no view or view model imports GRDB, HearthstockStore or HearthstockLookup apart from `AppServices`.
- Hampton has walked the Task 14 script on the phone and the simulator and confirmed each step.
- The summary lists the screens and view models, the new Core, Store and Lookup API, every assumption made, and any Slice 1–3 types changed and why.

## Task 0: Run on Hampton's iPhone

The camera can only be tested on a device, so device builds come first.

- [ ] Replace the placeholder bundle ID `com.example.hearthstock` with Hampton's reverse-DNS ID (Hampton supplies it). This is the last cheap moment to change it.
- [ ] Signing: `CODE_SIGN_STYLE: Automatic`, with `DEVELOPMENT_TEAM` read from a gitignored `Config/Local.xcconfig` that `project.yml` includes if present. Commit a `Config/Local.xcconfig.example` that explains what goes in it, so a fresh clone still builds for the simulator without one.
- [ ] Write the steps Hampton follows once: Apple ID in Xcode → select the team → plug in the phone → enable Developer Mode on the phone → Run. Note the 7-day re-sign on a free account.

**Done when:** Hampton runs the current Slice 3 build on the phone, and the data on it survives rebuilding and running again.

## Task 1: Barcodes in Core

- [ ] A pure `Barcode` namespace (or value type) that normalizes a raw string from the camera or the keyboard:
  - Strip spaces and dashes.
  - Accept EAN-8, UPC-E, UPC-A and EAN-13, plus a 14-digit GTIN with a leading zero.
  - Expand UPC-E to UPC-A, validate the check digit, and return the canonical form (13 digits, or 8 for EAN-8).
  - Fail with a typed error saying what's wrong (length, non-digits, check digit).
- [ ] `ProductDraft.product(id:)` stores the normalized form and throws a new `ProductDraftError.invalidBarcode` for a code that can't be normalized. The product form shows that error under the barcode field.

**Tests (table-driven):** a real UPC-A and its EAN-13 form normalize to the same string; UPC-E expansion against known pairs; EAN-8 kept at 8 digits; a 14-digit GTIN with a leading 0; a bad check digit, wrong length and letters each give their own error; spaces and dashes stripped.

**Done when:** every barcode the app compares has gone through one function.

## Task 2: Undated lots in Core

- [ ] `Lot.noPrintedDate` (Decision 1). Setting a printed date clears it; a lot can't have both.
- [ ] `ShelfLifeEvaluator`: for best-by and use-by profiles, the `rotationMonths` window applies only when `noPrintedDate` is on. A lot with no printed date and the flag off is Good and flagged `missingDate`, as today. A lot whose packaging already dates it (Mylar + O2 or bucket with a `packagedLifeMonths`) isn't flagged, as today. Profiles with date type none behave exactly as now.
- [ ] `LotFlag.estimatedDate` on lots aged by the undated shelf life (Decision 3).
- [ ] Every best-by and use-by profile in `shelf-life-defaults.json` gets a `rotationMonths`. Proposed conservative defaults, months from the acquired date:

  | Profile | Months | | Profile | Months |
  | --- | --- | --- | --- | --- |
  | Canned, low acid | 24 | | Cooking oil | 12 |
  | Canned, high acid | 12 | | Peanut butter | 9 |
  | White rice | 60 | | Freeze-dried food | 24 |
  | Dried beans and lentils | 36 | | MRE | 36 |
  | Wheat berries | 60 | | Bottled water | 24 |
  | Rolled oats | 12 | | Infant formula (use by) | 6 |
  | Dry pasta | 24 | | Medication (use by) | 12 |
  | Brown rice | 6 | | Other food (conservative) | 6 |
  | Flour | 6 | | | |

  Loading still fails clearly on a best-by or use-by profile without one, so a new profile can't forget it.
- [ ] Focus next gains one item, after missing nutrition and water volume: lots missing a date, with their count (`.missingDate(lots:)`).
- [ ] `InventoryQuery` gains a "Needs a date" filter, for the Focus next item and the walk summary to open.

**Tests:** table-driven over the three cases for a best-by, a use-by and a no-date profile; ticking the box on a lot with a printed date is refused or clears it (whichever the plan picks); a lot override of `rotationMonths` moves the estimated expiry; Inspect starts at 80% of the estimated span and Expired the day after; an estimated lot counts in the low end until Inspect; a Mylar lot with no date is neither flagged nor estimated from `rotationMonths` when its packaged life is longer; the bundled table loads and every dated profile has a `rotationMonths`; Focus next lists missing-date lots last with the right count; the fixture's states and runway are unchanged.

**Done when:** every undated lot is either estimated or flagged, and the fixture test still passes untouched.

## Task 3: Store additions

Each migration is listed in the plan before it's made.

- [ ] Migration `v3_normalize_barcodes` rewrites existing product barcodes to their normalized form (Task 1). A barcode that's invalid, or whose normalized form would collide with another product's, is left as it is; the migration logs it and the summary reports it. `GRDBProductRepository.find(barcode:)` normalizes its input before matching.
- [ ] Migration `v4_lot_no_printed_date`: a `noPrintedDate` column on lots, default false, with a check that it's false whenever `printedDate` is set. Saved and loaded through `LotRepository`.
- [ ] Migration `v5_lookup_cache`: a table keyed by normalized barcode holding the outcome (found or not found), the decoded `LookedUpProduct` fields as JSON text when found, and the fetch time. `LookupCacheRepository` (protocol in Core, implementation here): get, put (replacing), count and clear. Nothing else reads this table; products never point at it.
- [ ] Backup format version 3: the lot flag and the lookup cache (Decision 8). A version 1 or 2 file still imports, with the flag off and an empty cache.
- [ ] `LotRepository.add(_ id: LotID, amount: Double) -> Lot` (Decision 17): adds to an unarchived lot's quantity in one write. It throws `.lotArchived`, `.lotNotFound` and `.invalidAmount` as `consume` does.
- [ ] `LotRepository.lots(productID:siteID:)`: the product's unarchived lots at a site, newest first, for the "Already in your inventory" list. If `RunwayInputs` already gives the screen this cheaply, say so in the plan and skip it.
- [ ] Walk Undo (Decision 15): a lot the walk created is deleted with `delete(_:)`, a product created in the same action goes too when it has no other lots, and an `add` is reversed with `consume`. Confirm in the plan that deleting a product with no lots is possible, or add `ProductRepository.deleteIfUnused(_:)`.

**Tests:** a product saved as a 12-digit UPC-A is found by its 13-digit form and vice versa; the barcode migration normalizes a valid code, leaves an invalid one, and leaves a would-be collision without failing; the lot flag round-trips through the repository and the backup; the check refuses a lot with both a printed date and the flag; a version 2 backup imports with the flag off and an empty cache; the cache round-trips found and not-found entries, a put replaces, clear empties it, and it survives export and restore; `add` increases the quantity, refuses archived and missing lots, and two concurrent `add`s both land; `lots(productID:siteID:)` excludes archived lots and other sites; undoing a walk action that created a product and lot leaves neither behind, while undoing an `add` restores the earlier quantity.

**Done when:** every write the scanner, the walk and undated lots need exists as a repository call.

## Task 4: Undated lots in the UI

No artboard covers this; build it from the tokens and the existing date sheet, and say in the plan what it will look like.

- [ ] Printed date sheet: "No date on the package" ticks the new flag and shows the estimate under it ("Est. use by Mar 2031: White rice, 5 years from the acquired date"), with a stepper or picker to change the months for this lot only. The footer explains that the acquired date matters ("Set Acquired to when you bought it, or the estimate runs from today").
- [ ] Add form and lot edit: the printed-date row reads "Not set" (flagged), "No printed date · est. Mar 2031", or the date. Saving a lot override writes `ShelfLifeOverride.rotationMonths` for that lot; clearing it goes back to the profile's default.
- [ ] Lot detail "why" text for estimated and missing-date lots, from `LotText`; Inventory rows show "Est." beside an estimated date and keep the "No date" flag for missing ones.
- [ ] The Focus next row ("3 lots need a date") opens Inventory with the "Needs a date" filter, with a visible way to clear it.

**Done when:** a can added with no date shows "No date" in Inventory and on the Dashboard, and ticking the box on it moves it to an estimated date with the right state.

## Task 5: Scan resolution and debouncing in Core

- [ ] `ScanResolution`: a pure function that takes a normalized barcode, the local product for it (if any), that product's lots at this site with their `LotStatus`, and the lookup outcome (if one ran, cached or not). It returns what the UI shows next:
  - `known(product, lots:)` (lots may be empty);
  - `found(draft, source: .openFoodFacts)`;
  - `notFound(draft)` (barcode kept, everything else empty);
  - `lookupUnavailable(draft)` (the same draft, plus a reason: offline, rate limited, timed out, server error, or lookups switched off).

  The UI never decides which of these applies.
- [ ] `ScanDebouncer`: a pure state machine fed `(barcode, time)` sightings and `(added, barcode, time)` events, with time passed in. It turns the scanner's continuous stream into deliberate scans:
  - A code is accepted once, then ignored while it stays in frame.
  - After it has been out of frame for about 1.5 seconds, seeing it again counts as a new scan.
  - A code seen again after being added is reported as a **repeat** (the "Scanned again" card), not as a new scan.
  - While a confirm card is open, other codes are ignored, so a can sliding past in the background doesn't replace the card you're reading.

**Tests:** each `ScanResolution` case, including a known product whose lots are at another site (shown as `known` with no lots); debouncer sequences: continuous sightings → one scan; out of frame for 1 s then back → still the same scan; out for 2 s → a new scan; added then seen again after a gap → repeat; a second code during an open card → ignored.

**Done when:** the scanner screens are a debouncer, a resolution call and views.

## Task 6: Open Food Facts mapping in Core

- [ ] Record real responses first. From Hampton's Mac, save 6–8 real v3 responses for products in the pantry into `Tests/HearthstockCoreTests/Fixtures/openfoodfacts/`, with the User-Agent from Decision 9:
  - a can (count), a bulk bag over 2 lb (mass), a bottled water case or jug (water), one with kcal only per serving, one with energy only in kJ, one with no net quantity, and a not-found response.

  Note the HTTP status alongside each. **The field names below are a starting point, not verified: check them against these recordings and follow the recordings where they differ.**
- [ ] Decode tolerantly into `LookedUpProduct`. Read the v3 envelope (status, result, product) and these product fields: `product_name`, `brands`, `quantity` (the label string, such as "15 oz"), `product_quantity` plus `product_quantity_unit` (net amount in g or ml), `nutriments` (`energy-kcal_100g`, `energy-kcal_100ml`, or `energy-kj_100g` divided by 4.184), `serving_quantity` and `energy-kcal_serving`, and `categories_tags`. Numbers may arrive as JSON numbers or numeric strings; accept both. A missing or malformed field leaves that draft field empty; it never fails the whole lookup. `LookedUpProduct` is `Codable`, since the cache stores it (Task 3).
- [ ] Build the draft:
  - **Name** is brand + product name + the label size when the name doesn't already contain it ("Bush's Black Beans, 15 oz"), because different sizes are different products.
  - **Unit kind** follows Decision 12.
  - **Calories per base unit:** kcal per 100 g × net grams ÷ 100 per item for count; kcal per 100 g × 453.59237 ÷ 100 per lb for mass; the per-100 ml equivalent per gal for volume. With no net quantity, calories stay empty rather than being guessed from a serving. Empty calories surface as missing nutrition, which is the conservative outcome.
  - **Water:** products tagged as waters get category water and potable gallons per base unit (net ml ÷ 3785.41 per item, or 1 per gal).
  - **Shelf-life profile:** guessed from `categories_tags` using a bundled data file, `Resources/off-category-profiles.json` (tag → profile key). When several tags match, take the profile with the **shortest** extension window. With no match, use `unknown_food`. Seed the map from the existing profiles: canned low/high acid, white and brown rice, dried beans, pasta, oats, flour, oils, peanut butter, honey/sugar/salt, waters, freeze-dried, infant formula. The tag names are guesses to check against the fixtures and the Open Food Facts category taxonomy.
- [ ] `ProductDraft.fillingEmptyFields(from:)`: a lookup fills only what the user left empty and never overwrites anything they entered (spec).

**Tests:** each fixture maps to the expected draft (name, unit kind, kcal per base unit within tolerance, potable water, profile); the shortest-window tie-break; unknown tags → `unknown_food`; numeric strings decode; kJ-only converts; no net quantity → no calories; not-found → no draft; `LookedUpProduct` round-trips through JSON unchanged; `fillingEmptyFields` leaves every user-set field alone.

**Done when:** a recorded response turns into the draft the add form will show, with no network involved.

## Task 7: Lookup client, cache and the Settings switch

- [ ] Add a `HearthstockLookup` library target and test target to `Package.swift`. It depends on Core and contains `OpenFoodFactsClient` and `CachingProductLookup`, both `ProductLookupService`.
- [ ] `OpenFoodFactsClient`:
  - one GET to the v3 product endpoint, with a `fields` list limited to what Task 6 reads;
  - the User-Agent from Decision 9;
  - about a 4-second timeout;
  - its own per-minute cap (Decision 11).

  It returns `found(LookedUpProduct)`, `notFound`, or `unavailable(reason)`; it never throws for network conditions.
- [ ] `CachingProductLookup` (Decision 7) wraps the client and a `LookupCacheRepository`:
  - a cached found or not-found answer is returned without a request, whether the Settings switch is on or off;
  - a fresh found or not-found answer is stored before it's returned; `unavailable` is never stored;
  - `refresh(barcode:)` skips the cache read, asks the client, and replaces the entry (used only by **Look up online**, Task 11).
- [ ] `AppServices` holds the wrapper as `any ProductLookupService`. When the Settings switch is off, the wrapper still reads the cache but its client is a `DisabledLookupService` that returns `unavailable(.switchedOff)` without touching the network.
- [ ] Settings → **Online lookup** section: the switch, the count of saved lookups, and **Clear saved lookups** (with a confirmation). Footer: "Unknown barcodes are looked up in Open Food Facts. Only the barcode is sent, and each one is sent once: the answer is saved on this phone and used for every later scan."
- [ ] Update CLAUDE.md's layout, and add an architecture rule that only `HearthstockLookup` uses the network.

**Tests** (with a stub `URLProtocol`; no real network in tests): 200 with a product → found; the not-found response → notFound; timeout, no connection, 429, 503 and malformed JSON → unavailable with the right reason; the User-Agent and `fields` are sent and nothing else about the user; the per-minute cap returns `unavailable(.rateLimited)` without a request; the disabled service never builds a request. Cache: a second lookup of the same barcode makes no request; a cached not-found makes no request; an unavailable answer isn't cached and the next lookup tries again; a cached answer is served with the switch off; `refresh` makes a request and replaces the entry; clearing the cache makes the next lookup go to the network.

**Done when:** the app can ask "what is this barcode?", always gets an answer within a few seconds, and never asks the network about the same barcode twice unless told to.

## Task 8: Scanner component

- [ ] `BarcodeScannerView`: a `UIViewControllerRepresentable` wrapping VisionKit's `DataScannerViewController`. Recognize barcodes only (EAN-8, EAN-13, UPC-E; UPC-A arrives through these, and Task 1 normalizes whatever comes in), with guidance and high-frame-rate tracking on. Feed sightings into the Task 5 debouncer, and run Task 1 normalization before anything else sees a code.
- [ ] **Type a barcode** (Decision 13) on the same screen, validated by Task 1; a code that fails normalization shows the error and keeps the field open.
- [ ] Availability:
  - `DataScannerViewController.isSupported` false (old device, simulator) → the screen shows "Type a barcode" and "Type it in" only;
  - camera permission not yet asked → ask;
  - denied or restricted → explain why the camera helps, with a button to iOS Settings and the manual options.
- [ ] Torch button (`flashlight.off.fill` / `.on.fill`) through `AVCaptureDevice`. Hide it on devices without a torch. Check on the device that toggling it doesn't stop the scanner.
- [ ] Haptics per design §7: a light tick when a code is accepted, `.warning` on a repeat.
- [ ] Camera screens use the always-dark palette from design §1.

**Done when:** on Hampton's phone the scanner reads a can's barcode within a second and the torch works; on the simulator the same screen offers "Type a barcode".

## Task 9: Scan-first Add flow

- [ ] The "+" button now opens the **Add · scan** screen as a full-screen cover (Decision 14):
  - an "Into <location>" chip (last-used location preselected, same `Preferences` key as Slice 3);
  - **Type it in**, which opens the Slice 3 manual sheet;
  - **Pantry walk**.
- [ ] On a scan, run Task 5's resolution, with a cached-or-online lookup for unknown codes. Show "Looking up…" in place for up to the timeout; the camera keeps running behind it. Then:
  - **Known, with lots at this site** → **Already in your inventory** (`Scan-Existing`): those lots with location, quantity, printed date and state badge, plus **Different date: start a new lot** (selected by default) and an "Adding N" stepper. Choosing a lot adds N to it with `add` and shows the saved confirmation. Different date continues to the add form.
  - **Known, no lots here** → the add form with the product set.
  - **Found** → the add form with the new draft, and a note above the product row: "Filled in from Open Food Facts. Check the name and calories." The unit kind is shown, and changeable until the first save.
  - **Not found / unavailable** → **We don't know this one yet** (`Scan-NotFound`): name, category, and calories per item for food, with the barcode kept. When the lookup was unavailable rather than not found, say so ("Couldn't look it up right now. You can fill this in later."), with `wifi.slash` when offline. **Rescan** returns to the camera; **Next** continues to the add form.
- [ ] `AddLotSheet` / `AddLotModel` gain an initializer that presets the product choice and location. Their save path doesn't change. `.sensoryFeedback(.success)` on save.
- [ ] Inventory gets the design's **Scan** button (`barcode.viewfinder`) next to "+", opening the same screen.

**Done when:** on the simulator, typing a known code, an Open Food Facts code and a made-up code each reaches the right next screen and cancelling at any step leaves nothing behind; on the phone the same happens from the camera.

## Task 10: Pantry walk

- [ ] Core `PantryWalk` session (pure, time passed in):
  - records each action with what undoing it requires (created lot, created product + lot, or added N to an existing lot);
  - counts items and lots;
  - groups the summary by product (×N);
  - lists lots saved without a printed date;
  - reports the elapsed time.
- [ ] The walk screen (`Walk-Mode`):
  - location chosen when starting, then locked (`lock.fill` chip), with the "N added this walk" pill and **Done**;
  - the camera stays open;
  - each accepted scan raises the **WalkConfirmCard** over it.
- [ ] Confirm card by resolution:
  - **Known** → quantity stepper in the product's unit (1 for count), a printed-date chip (Decision 16; "Filled today" for no-date profiles like stored tap water), **Skip** and **Add to <location>** (1:2).
  - **Found** → the same, plus the name and category from the draft. Add saves the product and lot together.
  - **Not found / unavailable** → name, category and kcal per item inline before Add.
  - Lookups don't block the camera; the card shows "Looking up…" until the answer arrives.
- [ ] After Add: a success haptic and an "Added <name> · <qty>" row with **Undo** for the most recent action (Decision 15).
- [ ] A repeat from the debouncer opens **Scanned again** (`Walk-Duplicate`):
  - **Add another · makes N**, which uses `add` on the lot just created;
  - **Oops, double scan**, which dismisses;
  - **Different date**, which opens the date sheet and then saves a new lot.
- [ ] Done shows the **summary** (`Walk-Summary`):
  - "<Location> done", items and lots, and duration;
  - runway before → after: the start snapshot vs. now, both through `RunwayCalculator`, showing food and water ranges;
  - "N items need a date", opening Inventory with the "Needs a date" filter (Task 4), where each lot's date can be set or its box ticked;
  - the added list, where tapping a row opens its lot detail;
  - **Walk another spot** (new location, new session) and **Done**.

**Tests (Core):** a walk with a create, an add-to-lot, a product + lot create and an undo of each gives the right counts, grouping and undo plans; the needs-a-date list; elapsed time from the injected times.

**Done when:** Hampton can walk one real shelf on the phone, undo a mistake, handle a double scan, and see the runway move on the summary.

## Task 11: Look up again

- [ ] When a product has a barcode and is missing calories (or potable water, for water), the product form and its Focus next item offer **Look up online**. It calls `refresh(barcode:)` (Task 7), the one path that asks the network about a cached barcode, and merges with `fillingEmptyFields`, so nothing Hampton typed changes. It says what was filled in, or that nothing new was found. With the Settings switch off, the button explains that lookups are off.

**Tests:** covered by Task 6's merge tests and Task 7's refresh tests. Verify the button by hand in Task 14.

## Task 12: Settings and polish

- [ ] Settings → **Camera** row showing permission status, with a link to iOS Settings when it's denied.
- [ ] Every new screen meets the accessibility-size rules in design §7 (cards and steppers stack, badges move to their own line).

## Task 13: Live Text dates

Last on purpose (Decision 18): if it runs long, it can move to a later slice without touching anything else.

- [ ] A pure Core parser from recognized text to candidate printed dates, each with a precision (day or month) and the date type when the text says it ("BEST BY", "BB", "USE BY", "EXP"). Formats from real packages: `MAR 05 2027`, `05 MAR 27`, `05MAR2027`, `03/05/27`, `03/2027`, `2027-03-05`, `MAR 2027`, `BEST BY 03 05 27`, plus lot-code noise around them. Ambiguous numeric dates follow Decision 18; impossible dates are dropped; two-digit years read as 20xx.
- [ ] The printed date sheet gets **Scan the date**: `DataScannerViewController` in text mode, the parser on what it sees, and the best candidate filled into the sheet with its live state preview (Printed date picker artboard). Other candidates are one tap away; Done confirms.
- [ ] Works from the Add form, lot edit and the walk's date chip.

**Tests:** table-driven over each format, with and without a prefix; ambiguous day/month offers the earlier date first; lot codes and times ("L2304 14:32") produce no date; month-only becomes the 1st with month precision.

**Done when:** pointing at "BEST BY MAR 05 2027" on a real can fills March 5, 2027 as best-by and shows its state.

## Task 14: Device walk-through

- [ ] Write `docs/slice-4-walkthrough.md` in the style of Slice 3's: what to tap and what to see, using items Hampton actually owns. Cover:
  - undated lots: a can saved with no date (flagged, in Focus next and the "Needs a date" filter), then ticked "No printed date" (estimated date and state), then a per-lot override of the months;
  - first-launch camera permission, then denying it and recovering through Settings;
  - scanning a can already in inventory → add to an existing lot, and → different date;
  - a product found in Open Food Facts: check its name, unit kind and calories, then save;
  - the same barcode scanned again in Airplane Mode → still found, from the cache;
  - a made-up typed barcode → not found → save with calories → Focus next clean;
  - Airplane Mode with a new barcode → "Couldn't look it up right now" → save without calories → Focus next shows missing nutrition → Airplane Mode off → **Look up online** fills only the empty field;
  - Settings switch off → a new barcode isn't looked up, a cached one still fills in; **Clear saved lookups**;
  - a full pantry walk of one shelf with a double scan, an Undo and a Different date; the summary's runway change and its needs-a-date list;
  - Live Text on a real printed date;
  - torch on and off;
  - a backup round-trip with undated lots and saved lookups;
  - the simulator path with typed barcodes.
- [ ] Run `swift test`, `xcodegen generate` and both builds, hand the script to Hampton and wait for the report. Fixes found here go in this task's commits.

**Done when:** Hampton confirms every step on the phone.

## Dependencies

- Task 0 has no dependencies and should go first, since the camera needs the device.
- Tasks 1 and 2 have no Slice 4 dependencies.
- Task 3 depends on Tasks 1, 2 and 6 (the cache stores `LookedUpProduct`).
- Task 4 depends on Task 3.
- Task 5 depends on Task 1.
- Task 6 depends on Task 1.
- Task 7 depends on Tasks 3 and 6.
- Task 8 depends on Tasks 0 and 5.
- Task 9 depends on Tasks 3, 5, 7 and 8.
- Task 10 depends on Tasks 4 and 9.
- Task 11 depends on Task 7.
- Task 12 depends on Task 9.
- Task 13 depends on Tasks 4 and 8.
- Task 14 depends on Tasks 10, 11, 12 and 13.
