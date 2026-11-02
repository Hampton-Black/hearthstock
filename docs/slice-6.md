# Slice 6: kits and the Kits tab

> **Draft for review.** Nothing here is in Beads yet. The proposed tasks are in `docs/slice-6-beads.jsonl`, to import once the plan is approved (see the end of this file). The open question below comes first.

**Goal:** Hampton can see, for each go-bag, first-aid kit and car kit, what's packed, what's short, missing or expiring, and when it was last checked, and can pack it from stock already in the house. Kits are the main v1 promise still missing (spec → Goals: "Track go-bags and other kits against a required manifest, flagging gaps and expiring items").

- A kit is still a location with a manifest. Its contents are ordinary lots, and nothing about lots changes.
- Each kit gets its own list of requirements, copied from a bundled template when it's made and editable afterwards.
- The Kits tab shows every kit against its list, and Focus next lists kit gaps and checks that are due.
- Stock can be moved, whole or in part, from a shelf into a kit, keeping its dates.

After this slice, Hampton's real go-bag should be in the app, with every requirement either packed or showing why not.

## Open question: kits or reminders first

The README's Next up list names kits as the likely next slice, and says local reminders "could move ahead of kits if real dates make them more useful sooner". This plan drafts kits. **Recommendation: kits first.** Go-bags are the bigger missing promise; kits need the schema change, which is better made before more real data goes in; and kit checks give reminders one more thing to remind about, so a reminders slice right after can cover expiring lots and kit checks in one go. If entering the real pantry has turned up many Use soon dates that are easy to miss, reminders first is the better order, and this plan waits.

Read first:
- `CLAUDE.md`.
- `docs/spec.md` → **Data model** (Kit, KitTemplate, Location), **Sites** (kits keep a home site and are excluded from runway by default), **Runway dashboard** → Focus next item 4, **Screens and flows** (Kits row), **Decisions** (the four starter templates).
- `docs/design.md` §4 (kit symbols), §5 (kit requirement states), §6 KitMeter, §8 screen map (`KitsView`, `KitDetailView`, `KitEditView`).
- The design references: `Kits`, `Kit-Detail`, `Kit-Template` (Edit kit), and their dark variants.
- The code kits already have:
  - Core: `Kit`, `KitID`, `KitTemplateID`, `Location.kitID`, `LotStatus.kitLocation` and `countsTowardSiteRunway`, `RunwayEffect.excludedByKit`, `InventorySection.isKit`, `RunwayInputs.kits`;
  - Store: the `kit` table from `v1_initial` (with the deferred `location.kitId` link and the home-site triggers), `KitRecord`, `GRDBKitRepository`, the kit rows in `BackupDocument`;
  - App: the "This is a kit" and "Count toward home runway" switches in `LocationForm`, the Kit tag in Settings, the backpack icon on Inventory sections, the go-bag in `SamplePantry`.
- `ShelfLifeProfileTable` and `shelf-life-defaults.json`, the pattern the kit templates follow.

**Slices 1–5 are the ground truth for type names and shapes.** Where this file names something differently from the code, follow the code and say so in the plan. List any Core or Store type change before making it.

Start in plan mode: propose the new Core types (templates, requirements, the kit evaluator, the lot split), the `v6` migration, the repository changes, the screens and view models with file layout, and the test plan. Then wait for approval. Work the tasks in dependency order and commit after each.

**Lots don't change.** A lot in a kit is an ordinary lot in the kit's location. Its shelf life, climate and state come from the same evaluator, and the runway still skips it unless the kit counts toward the site.

**Nothing is stored that can be derived.** Requirement states, "11 of 14", "short by 2" and "check due" are computed from the requirements, the lots and the date. Only the requirements, the product links and the last check date are stored.

## Decisions taken in this plan

Defaults chosen where the spec or the design leaves a choice open. Hampton can overturn any of them before this goes into Beads.

**Kits and templates**

1. **A kit's name is its location's name, and "Location" on Edit kit is the location it sits in.** The design shows "Go-bag (Hampton)" with "Hall closet" under it. That's the kit's location, named "Go-bag (Hampton)", whose parent is Hall closet. Renaming a kit renames its location. No name column is added.
2. **Templates are bundled data, like the shelf-life table.** `Resources/kit-templates.json` holds the four starter templates from the spec's Decisions (Task 1 lists their contents). A template is keyed by a string, like a shelf-life profile, and isn't stored in the database. CLAUDE.md rule 10 already says kit templates ship as bundled data.
3. **A kit gets its own copy of the template's requirements.** Editing a kit's list changes that kit only, as the design's Edit kit footer says. The kit remembers which template it came from, for the "72-hour template" subtitle. Updating the bundled file later never changes an existing kit. Saving a kit as a new template, and editing templates, are out of scope.
4. **Kit.templateID becomes `templateKey`.** `KitTemplateID` (a UUID) has never been set by the app, so it's removed from Core, and the column is renamed in the migration (Decision 14). This is a Core type change.
5. **Quantities can be per person.** A kit has a number of people (default 1). Each requirement is either per person (water, food, blankets, masks) or per kit (a radio, a multi-tool), and per-person targets are multiplied by the kit's people. A go-bag is for one person; a house-preps kit defaults to the site's number of occupants.
6. **Whether a kit counts toward the home runway comes from its template:** off for the go-bag and the vehicle kit, on for the first-aid kit and house preps, as the spec says. It stays editable, as today.
7. **The vehicle template sets a new kit location's climate to Vehicle** (0.33×), so water and food bars in a car age as the spec's climate table says. Hampton can change it.

**Requirements and their states**

8. **A requirement measures one of three things:**
   - **Food days:** kcal of the food lots in the kit ÷ (2,000 kcal × people). It uses the spec's 2,000 kcal per person per day, not a household member's own number, since a kit isn't tied to a person.
   - **Water:** potable gallons of the water lots in the kit, worked out as the runway does. Targets are in gallons like the rest of the app, so the design's "3 L" becomes 0.8 gal.
   - **Items:** the quantity of the lots whose product is linked to the requirement, in that product's base unit (count, lb or gal). A count can carry a word for display ("1 set", "2 pair").
9. **Item requirements are matched by linked products.** A template can't know Hampton's products, so a new kit's item requirements start with no product and show as Missing. Packing a requirement (Task 8) links the product chosen. A requirement can link several products (two brands of AAA), and a product links to at most one requirement in a kit. A food or water lot counts toward food days or water unless its product is linked to an item requirement in that kit.
10. **Which lots are in a kit:** unarchived lots whose nearest kit location (`LotStatus.kitLocation`) is this kit's location, so a pouch inside a go-bag counts toward the go-bag, and a kit inside another kit counts only toward the inner one.
11. **Requirement states, from design.md §5:**
    - **Expired** lots never count.
    - **Complete** when the Good lots alone meet the target.
    - **Use soon** when the target is met only by counting Use soon, Caution or Inspect lots. It counts as packed in "11 of 14", as the design does.
    - **Short** when something counts but less than the target.
    - **Expired** (the state) when nothing counts and an expired matching lot is in the kit; **Missing** when nothing counts and nothing is there.
    - An expired lot in a kit is always listed under Needs attention, to remove or replace, whatever its requirement's state.
    - Lots in the kit that match no requirement are listed under "Not on the list" and don't change any state.
12. **Kit checks.** A kit has "Check every N months" (default 6, 3 for the vehicle kit, or never) and its last check date. A check is due once that many months have passed, and a kit never checked is due. "Mark inspected" sets the date to today. Nothing else changes.
13. **Focus next gains kit items** (spec item 4): one entry per kit with anything short, missing or expired ("Go-bag (Hampton): 2 short, 1 missing"), then one per kit whose check is due. They go after Use soon lots and before the missing-data items, keeping the spec's order. Kit lots in Caution, Inspect or Use soon are already in those lists today and stay there.

**Storage**

14. **One migration, `v6_kit_requirements`.** It's the first new migration since Slice 4 (Slice 5 needed none). Migrations have run on Hampton's iPhone, so `v1_initial` isn't touched:

    ```sql
    ALTER TABLE kit RENAME COLUMN templateId TO templateKey;
    ALTER TABLE kit ADD COLUMN peopleCount INTEGER NOT NULL DEFAULT 1 CHECK (peopleCount > 0);
    ALTER TABLE kit ADD COLUMN checkEveryMonths INTEGER DEFAULT 6
        CHECK (checkEveryMonths IS NULL OR checkEveryMonths > 0);

    CREATE TABLE kit_requirement (
        id TEXT PRIMARY KEY NOT NULL,
        kitId TEXT NOT NULL REFERENCES kit(id) ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK (position >= 0),
        name TEXT NOT NULL CHECK (name <> ''),
        measure TEXT NOT NULL CHECK (measure IN ('foodDays', 'waterGallons', 'items')),
        target REAL NOT NULL CHECK (target > 0),
        perPerson INTEGER NOT NULL DEFAULT 1 CHECK (perPerson IN (0, 1)),
        unitKind TEXT CHECK ((measure = 'items') = (unitKind IS NOT NULL)
            AND (unitKind IS NULL OR unitKind IN ('mass', 'volume', 'count'))),
        countNoun TEXT CHECK (countNoun IS NULL OR countNoun <> ''),
        createdAt …, updatedAt …          -- as in v1_initial
    );
    CREATE INDEX kit_requirement_on_kit ON kit_requirement(kitId, position);

    CREATE TABLE kit_requirement_product (
        requirementId TEXT NOT NULL REFERENCES kit_requirement(id) ON DELETE CASCADE,
        productId TEXT NOT NULL REFERENCES product(id) ON DELETE CASCADE,
        createdAt …,
        PRIMARY KEY (requirementId, productId)
    );
    CREATE INDEX kit_requirement_product_on_product ON kit_requirement_product(productId);
    ```

    Kits already on the phone keep their location, runway switch and check date, get 1 person and a 6-month check, and have no requirements until Hampton adds some or applies a template (Task 7). Deleting a kit takes its requirements and links with it; deleting an unused product takes its links. The "one requirement per product per kit" rule (Decision 9) is the repository's, since the link table has no kit column. The CHECK lists repeat the Core raw values on purpose, and `SchemaTests` checks them as it does today.
15. **The backup goes to format 4,** with the new kit fields and two new arrays (`kitRequirements`, `kitRequirementProducts`). Formats 1–3 still restore: their kits read `templateId` (always empty in practice) as no template, and get the migration's defaults.
16. **`RunwayInputs` gains the kits' requirements,** so the one observation that drives the dashboard also drives the Kits tab and Focus next.

**Packing**

17. **Stock moves into a kit, whole or in part, keeping its dates.** `LotRepository.move(_:amount:to:)` moves a whole lot by changing its location, or splits it: the source lot goes down by the amount and a new lot with the same product, dates, packaging, opened flag and no-printed-date flag, plus a copy of any lot-level shelf-life override, appears in the destination, in one write. A climate override isn't copied, since the lot is now somewhere else. Moving within the site only, as the triggers already enforce. The sheet says what the move does to the home runway ("Home runway 41 → 40 days") when it takes stock out of it.
18. **The Settings switch stays.** "This is a kit" on a location still works and makes a kit with no requirements, which then shows in the Kits tab. The Kits tab is the main way to make one.
19. **The tab bar becomes Runway, Inventory, Kits, Settings,** as the design shows. Tasks waits for its own slice.

## Out of scope

- Household readiness checklists (water, power, cooking, preservation, lighting, comms), including a "whole home" house-preps list that counts gear anywhere in the house. Here, house preps is a kit in one place, such as a closet tote.
- Maintenance tasks, the Tasks tab, and battery "charged on" dates (the design's "Battery bank · Charged Aug 30").
- Local reminders and notifications, including for kit checks.
- Saving a kit as a template, editing the bundled templates, and sharing a list between kits.
- Capabilities: a water filter in a go-bag is an item here, not a capability with gallons treatable.
- Relocation scenarios and anything else multi-site.

## Definition of done

- `swift test` green, with the count reported. Every Slice 1–5 test passes unchanged, apart from the `Kit` initializer and the backup format number. The sample pantry fixture's runway is unchanged.
- The Debug and Release builds succeed. The app runs on Hampton's iPhone, and the migration has run there on his real data.
- HearthstockCore still imports only Foundation. The template loader, the kit evaluator and the lot split are pure and tested.
- Hampton's real go-bag is in the app: every requirement is packed or says why not, and Focus next agrees with the Kits tab.
- The summary lists the new Core API, the migration, the screens changed, and every assumption.

## Task 1: Kit templates and requirements in Core

- [ ] `KitTemplate` (key, name, symbol, default people, counts toward runway, check every months, optional location climate) and `KitRequirement` (ID, name, measure, target, per person, unit kind, count noun, linked product IDs, position). `KitRequirementID` is a new typed ID.
- [ ] `Kit` gains `templateKey`, `peopleCount` and `checkEveryMonths`; `templateID` and `KitTemplateID` go (Decision 4).
- [ ] `Resources/kit-templates.json` and `KitTemplateTable`, loaded like `ShelfLifeProfileTable`. `KitTemplate.makeRequirements()` copies a template's list for a new kit.
- [ ] Proposed contents (Hampton to review; these are the "Needed from Hampton" lists):
  - **72-hour go-bag** (1 person, off runway, every 6 months): water 0.8 gal, food 3 days, water filter, headlamp, AAA batteries 8, first-aid pouch, emergency blankets 2, rain shell, fire starter, multi-tool, battery bank, N95 masks 2, document copies 1 set, socks 2 pair. The design's 14 items.
  - **First-aid kit** (per kit, on runway, every 6 months): adhesive bandages 25, gauze pads 10, roller bandages 2, adhesive tape 1 roll, antiseptic wipes 10, antibiotic ointment, nonlatex gloves 2 pair, tweezers, scissors, instant cold pack, emergency blanket, pain reliever, thermometer, triangular bandages 2, first-aid guide. Based on the Red Cross family kit list; check it against the current list when building this task.
  - **House preps** (household, on runway, every 6 months): battery or hand-crank radio, flashlight per person, spare batteries 1 set, whistle per person, dust masks 2 per person, plastic sheeting and duct tape 1 set, manual can opener, wrench or pliers for the utilities. No food or water: the home runway covers those.
  - **Vehicle kit** (1 person, off runway, every 3 months, Vehicle climate): water 0.5 gal, food 1 day, jumper cables, flashlight, first-aid pouch, emergency blanket per person, phone charging cable, tire inflator or sealant, reflective triangles 1 set, work gloves 1 pair, multi-tool, rain poncho per person.

**Tests:** the file loads; every template has a unique key, a name and at least one requirement; every target is above zero; item requirements have a unit kind and food and water ones don't; `makeRequirements()` gives new IDs and keeps the order; a `Kit` encodes and decodes with the new fields.

## Task 2: Kit evaluation in Core

- [ ] `KitEvaluator.report(for:requirements:statuses:people:on:) -> KitReport`, pure, taking the site's `LotStatus` list as the runway does. `KitReport` holds each requirement's state, counted amount, target and the lots behind it; the expired lots; the lots not on the list; "packed of total"; and the check state (not checked yet, due on a date, overdue, never).
- [ ] Decisions 8–12, including nested kits, products linked to an item requirement not also counting as food or water, and the first requirement by position winning if a product is somehow linked twice.

**Tests (table-driven):**
- each state, including Use soon only when the Good lots fall short;
- food days with 1 and 2 people, and a food lot with no calories (it can't count, and the report says why);
- water from count-based bottles with gallons per item, and a bottle missing them;
- an expired lot under a Complete requirement still listed;
- a pouch inside a go-bag counts; a kit inside a kit counts only inward;
- check due from the last check date and the interval, never checked, and "never";
- the design's go-bag (11 of 14: 1 use soon, 2 short, 1 missing) as a fixture.

## Task 3: Kit items in Focus next

- [ ] `FocusItem.kitGaps(kit:short:missing:expired:)` and `FocusItem.kitCheckDue(kit:since:)`, placed as Decision 13 says. `FocusNext.items` takes the kit reports.

**Tests:** the order against the existing items; a kit with only Use soon requirements adds no gap item; a kit with nothing wrong adds nothing; existing `FocusNextTests` pass unchanged.

## Task 4: Migration `v6_kit_requirements` and the Store

- [ ] The migration in Decision 14. `KitRecord` gains the new columns; new `KitRequirementRecord` and `KitRequirementProductRecord`.
- [ ] `KitRepository` gains: create a kit with its new location and requirements in one write; save a kit with its whole requirement list (Edit kit's Done); link and unlink a product (refusing a second requirement in the same kit); mark inspected. `RunwayInputs` gains the requirements (Decision 16).
- [ ] Backup format 4 (Decision 15).

**Tests:**
- the migration on a v5 database holding a kit with lots: the kit, its location link and its runway switch survive, with the defaults;
- the CHECKs refuse an empty name, a zero target, an item requirement without a unit kind and a food one with one;
- deleting a kit removes its requirements and links but not its lots' products; deleting an unused product removes its links;
- creating a kit is all or nothing;
- a format 3 backup restores, a format 4 one round-trips byte for byte, and the fixture round-trip still passes.

## Task 5: Moving and splitting lots

- [ ] `LotSplit` in Core: given a lot and an amount, the source after the move and the new lot (Decision 17). Pure, refusing zero, negative and over-quantity amounts.
- [ ] `LotRepository.move(_:amount:to:) -> Lot` in Store, in one write, copying a lot-level shelf-life override.

**Tests:** a whole move changes only the location; a split keeps dates, packaging and the no-printed-date flag, copies the lot override and not the climate override; the source and destination quantities add up; a move to another site is refused; a failed write leaves both lots as they were.

## Task 6: The Kits tab

- [ ] Four tabs (Decision 19). `KitsView`: one card per kit with its symbol, name, "where it is · template", "N of M", the `KitMeter` and one status line ("Water: use soon, Oct 27 · 2 short · 1 missing", "Antibiotic ointment expired", "Check due"), and the footer about go-bags and the runway. "+" opens New kit.
- [ ] Empty state: no kits yet, with a button to make one.
- [ ] `KitMeter` per design.md §6, and the requirement states per §5, with a word and an icon on every state.

**Done when:** on the simulator, the sample pantry's go-bag shows as a card that matches its Kit detail.

## Task 7: New kit and Edit kit

- [ ] New kit: pick a template (or "Empty kit"), then the Edit kit form prefilled: name, where it sits (parent location), people, check every, count toward home runway, and the requirement list. Done creates the location, the kit and the list in one write.
- [ ] Edit kit, per the `Kit-Template` design: the same fields; requirements added, edited (name, measure, target, per person, unit, count word), deleted and reordered. The footer names the template it came from and says edits apply to this kit only.
- [ ] A kit made from the Settings switch, or migrated with no list, offers "Start from a template", which adds that template's requirements.
- [ ] Delete kit: the location stays as an ordinary one with its lots, as `KitRepository.delete` does today.

**Done when:** a go-bag made from the template shows 14 requirements, and editing one target changes only that kit.

## Task 8: Kit detail and packing

- [ ] `KitDetailView`, per the `Kit-Detail` design: the summary ("1 to use soon, 2 short, 1 missing. Last checked Aug 30."), All / Needs attention, the Needs attention rows (with expired lots), Packed, Not on the list, Mark inspected, Edit.
- [ ] Tapping a requirement opens **Pack**: choose a product (picker filtered by unit kind, scan, or a new product), then **Move from** a lot elsewhere in the site (Task 5, with the runway note) or **New lot** (the Add flow, preset to the kit's location). Saving links the product (Decision 9). Food and water requirements skip the product step.
- [ ] A lot under Not on the list offers "Count toward…", which links its product to a requirement.
- [ ] Large text: rows stack as on Inventory.

**Done when:** on the simulator, packing the go-bag's AAA batteries by moving 8 from a 24-pack in the garage leaves 16 in the garage, 8 in the bag with the same dates, and the requirement Complete.

## Task 9: Focus next, Inventory and Settings wiring

- [ ] Dashboard rows for `kitGaps` and `kitCheckDue`, each opening its Kit detail.
- [ ] Inventory's kit sections open their Kit detail.
- [ ] Settings: the Kit tag on a location opens its kit; the "This is a kit" footer mentions the Kits tab.
- [ ] `SamplePantry` (DEBUG) gains a go-bag from the template with a few lots in different states.

## Task 10: Device walk-through

- [ ] `docs/slice-6-walkthrough.md`, using Hampton's real go-bag. It covers: the migration on his phone keeping any kit he's already marked; making the go-bag from the template; packing by moving part of a lot and by adding a new one; the water and food-days requirements; an expired item; Use soon; Not on the list and Count toward; Mark inspected; the go-bag not counting toward the home runway and the runway note on a move; Focus next agreeing with the Kits tab; a backup made before the update restoring after it.
- [ ] Run `swift test`, `xcodegen generate` and both builds, then hand the script to Hampton and wait for the report.

## Dependencies

- Tasks 1 and 5 have no Slice 6 dependencies.
- Task 2 depends on Task 1.
- Task 3 depends on Task 2.
- Task 4 depends on Task 1.
- Task 6 depends on Tasks 2 and 4.
- Task 7 depends on Task 6.
- Task 8 depends on Tasks 5 and 7.
- Task 9 depends on Tasks 3 and 6.
- Task 10 depends on Tasks 8 and 9.

## Needed from Hampton

- Kits or reminders first (the open question at the top).
- A yes, no or edit on Decisions 1–19.
- The four template lists in Task 1, edited to what you'd actually pack.
- Which kits exist today and where they sit, and whether any location on your phone is already marked as a kit, so the walk-through uses real ones.

## Proposed Beads

`docs/slice-6-beads.jsonl` holds an epic and ten tasks in the same shape as `.beads/issues.jsonl`, all open, each task's description copied from its section above with its dependencies. The IDs (`hearthstock-k6t`, `.1` to `.10`) are placeholders; change them if `bd` would rather mint its own. It isn't in `.beads/` on purpose, so nothing syncs until it's imported on the Mac. Once the plan is settled, update the file to match, import it there, and delete it.
