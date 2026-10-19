# Slice 5: calories and categories at scan time

**Goal:** A scanned item is finished when it's saved: calories, category and shelf-life profile are filled in at the shelf, not fixed afterwards from Focus next. Slice 4 showed why that doesn't happen today. Open Food Facts usually knows calories per serving but rarely the package size, so calories per can can't be worked out. It often has no categories either, so the profile falls back to "Other food". This slice closes both gaps from the package in Hampton's hand:

- When calories per item can't be computed, the card asks one question: servings per container, or the net weight.
- The Nutrition Facts panel can be read with Live Text.
- When categories are missing, the profile is guessed from the product's name.

After this slice, a walk along a shelf of cans should leave nothing in "missing calories".

Read first:
- `CLAUDE.md`.
- `docs/slice-4.md` (Decisions 7, 12 and 18 especially) and its walk-through.
- `docs/spec.md` → **Products from a scan** (a later lookup never overwrites what the user entered) and **Shelf life**.
- `docs/design.md` §6 WalkConfirmCard and §7 (date entry, large text).
- The Slice 4 code:
  - `LookedUpProduct`, `OpenFoodFacts` (`draft`, `suggestedKcal`, `fillingEmptyFields`), `OFFCategoryMap` and `off-category-profiles.json`;
  - `ScanResolution`, `PantryWalkModel` / `WalkConfirmCard`, `AddLotModel.Preset`, `ProductForm` (and its per-package helper from Slice 3 Decision 6);
  - `PrintedDateParser`, `DateTextScannerSheet`, the recorded fixtures in `Tests/HearthstockCoreTests/Fixtures/openfoodfacts/`.

**Slices 1–4 are the ground truth for type names and shapes.** Where this file names something differently from the code, follow the code and say so in the plan. List any Core or Store type change before making it.

Start in plan mode: propose the new Core types (calorie fill, nutrition label parser, name guesser), the `LookedUpProduct` additions, the screens touched, and the test plan. Then wait for approval. Work the tasks in dependency order and commit after each.

**The save path still doesn't change.** Everything here only decides what the draft starts with. A product is still written once, with its first lot, through `ProductDraft` and `LotRepository.save(_:newProduct:)`.

**Nothing is guessed silently.** Every value this slice fills in shows where it came from ("from the label", "80 kcal × 3.5 servings", "guessed from the name") and stays editable before the first save. A guess never overwrites something the user typed.

## What the recordings show

From the eight responses recorded in Slice 4:

| Product | Package size | Calories per serving | Serving | Categories |
| --- | --- | --- | --- | --- |
| H-E-B corn | none | 80 | 0.5 cup (125 g) | none |
| Walmart cinnamon rolls | none | 230 | 2 rolls (61 g) | snacks, cakes |
| Pure Protein bar | empty | 190 | **1 bar** (50 g) | bars |
| Kings rice, 25 lb | none | 170 | 0.25 cup (47 g) | none |
| Campbell's soup | 297.67 g | 100 | 120 g | canned foods |
| Barilla penne | 453.59 g | 200 | 56 g | dry pastas |

Two of six have a package size. All six have calories per serving and a serving size. The USDA branded-food database found only the rolls and the bar (with package sizes) of Hampton's five barcodes, so it doesn't close the gap on its own (see Out of scope).

## Decisions taken in this plan

Defaults chosen where the spec leaves a choice open. Hampton can overturn any of them before this goes into Beads.

**Calories**

1. **Calories per item are worked out in a fixed order, and the first that applies wins:**
   - (a) net quantity × kcal per 100, as Slice 4 does;
   - (b) a single-serving package (the serving is "1 bar", "1 can", "1 bottle", "1 pouch", "1 packet", "1 meal" or "1 container") is calories per serving;
   - (c) calories per serving × servings per container, when the user gives servings;
   - (d) kcal per 100 × a net weight the user gives;
   - (e) a reading from the Nutrition Facts panel (Decision 4);
   - (f) left empty, which shows as missing nutrition, as today.

   This lives in one pure Core function, `CalorieFill`, which returns the value and how it was reached. The UI words the "how".
2. **Mass and volume products need no question.** Calories per lb or per gallon come from kcal per 100, as in Slice 4. The question is only for products counted by item.
3. **One question, two ways to answer.** Where (a) and (b) don't apply, the card shows "80 kcal per serving (½ cup)" and asks **Servings per container**, with decimals allowed ("about 3.5"). A **Net weight** answer is offered instead when kcal per 100 is known. Both can be skipped; skipping saves with calories empty.
4. **Live Text reads the Nutrition Facts panel; Hampton confirms.** "Scan the label" reads Calories, Servings per container, Serving size and Net Wt, works out calories per item with Decision 1, and shows the reading next to the result. Nothing is saved until Add or Save. The parser is pure Core and table-driven, like `PrintedDateParser`. It reads the US FDA panel only: "Calories", not "Energy" in kJ.
5. **A lookup that already has a good value isn't asked about.** If (a) or (b) gives calories, the card shows them, marked "from Open Food Facts", with no question.

**Category and profile**

6. **The name guesses the profile when categories don't.** A bundled data file, `name-keyword-profiles.json`, maps words in the product name to a profile key and category: "corn", "beans", "peas", "soup", "chili", "tuna" and "chicken" with a can-size cue ("oz", "can") give canned low acid; "tomato", "peaches", "pineapple", "fruit cocktail" give canned high acid; "rice" gives white rice ("brown rice" gives brown rice); "oats", "pasta", "flour", "peanut butter", "honey"; "water" gives category Water with bottled water. It's used only when `OFFCategoryMap` found nothing. Several matches take the shortest window, as in Slice 4. No match keeps "Other food". The card and the form show "Guessed from the name: Canned, low acid", one tap to change.
7. **The guess also runs on names typed in by hand,** for not-found items, but only while the profile is still the category default. Once the user picks a profile, typing doesn't move it.
8. **The net weight sets the unit kind when it's known before the first save.** A net weight from the label or the question that's over 2 lb (or 1 gal) switches a new product to mass (or volume), following Slice 4 Decision 12, and says so. Calories are then per lb. An existing product's unit kind never changes.

**Storage**

9. **`LookedUpProduct` gains the serving label and serving quantity.** Cached answers saved by Slice 4 decode with them empty, so there's no migration and no re-lookup; only a later scan's lookup has them. **Look up online** (Slice 4 Task 11) refreshes one product on demand.
10. **Where a value came from isn't stored.** Calories are a fact on the product. "From the label" is shown only until save, like the Slice 4 "Filled in from Open Food Facts" note.

## Out of scope

- USDA FoodData Central as a second lookup source. It found 2 of 5 of Hampton's barcodes and needs an API key; reconsider once there's more data from real walks.
- Contributing package sizes or photos back to Open Food Facts.
- Reading other panels (ingredients, allergens), and reading kJ-only labels from outside the US.
- Learning keywords from Hampton's corrections. The keyword file is bundled data that's editable later, like the shelf-life table.
- Kits, onboarding and anything else listed out of scope for Slice 4.

## Definition of done

- `swift test` green, with the count reported. Every Slice 1–4 test passes unchanged, apart from fixtures that gain the new serving fields.
- The Debug and Release builds succeed. The app runs on Hampton's iPhone.
- HearthstockCore still imports only Foundation. The new parsers and guessers are pure and tested.
- Hampton has walked one real shelf of cans and the walk summary shows no item missing calories, or each one that does has a reason (no label).
- The summary lists the new Core API, the screens changed, and every assumption.

## Task 1: `LookedUpProduct` serving fields

- [ ] Add `servingLabel` (`serving_size`, such as "0.5 cup (125 g)") and `servingQuantity` with its unit (`serving_quantity` / `serving_quantity_unit`, in g or ml) to `LookedUpProduct`. Decode them tolerantly, as Slice 4 does.
- [ ] Cached entries written before this slice decode with the new fields empty.

**Tests:** each recorded fixture decodes its serving label and quantity; numeric strings decode; a Slice 4 `LookedUpProduct` JSON (without the fields) decodes unchanged; a cache row written by Slice 4 still reads back.

## Task 2: `CalorieFill` in Core

- [ ] `CalorieFill.kcalPerBaseUnit(lookedUp:unitKind:servingsPerContainer:netWeight:label:) -> (value: Double, source: Source)?`, with `Source` covering net quantity, single serving, servings, net weight and label (Decision 1). Pure, and rounded as Slice 4 rounds.
- [ ] Single-serving detection reads the serving label: "1 bar", "1 can (…)", "1 bottle", "1 pouch", "1 packet", "1 meal", "1 container". "2 rolls" and "1/2 cup" are not single servings.
- [ ] `OpenFoodFacts.draft` uses it, so single-serving products get calories with no question.

**Tests (table-driven):**
- every fixture's result and source;
- the bar is single-serving at 190, and the rolls are not;
- corn with 3.5 servings gives 280;
- corn with a 15.25 oz net weight gives kcal per 100 × 432.3 g ÷ 100;
- mass and volume products never ask;
- the order of precedence when several apply;
- zero, negative and NaN inputs are refused.

## Task 3: Nutrition label parser in Core

- [ ] `NutritionLabelParser.read(_ text: String) -> NutritionReading` with calories per serving, servings per container (with "about" and decimals), serving size (household text and grams) and net weight (oz, lb, g, kg, fl oz, ml, L). It accepts Live Text noise: line breaks inside "Servings per container", "Calories" in a large font on its own line, and the dual-column panels ("per serving" / "per container").
- [ ] Dual-column panels: prefer the per-container calories when present, since that is calories per item directly.

**Tests (table-driven, from real panel text):** Hampton photographs 6–8 panels from the pantry, including the corn and a dual-column one. I transcribe them as Live Text returns them and save them under `Fixtures/nutrition-labels/`, with the expected reading for each. Also: % Daily Value numbers are never read as calories; "Calories from Fat" (older panels) is ignored; a missing field stays empty.

## Task 4: Name-based profile guess in Core

- [ ] `Resources/name-keyword-profiles.json` (keyword or phrase → profile key, with an optional category), and `NameProfileGuesser.guess(name:quantityLabel:in:)`. Word-boundary matches, case- and diacritic-insensitive, multi-word phrases first ("brown rice" before "rice", "peanut butter" before "butter"). The shortest window wins, and no match returns nil.
- [ ] `OpenFoodFacts.draft` falls back to it when `OFFCategoryMap` finds nothing. Every key in the file must exist in the shelf-life table (a test checks this).

**Tests:**
- Hampton's products: corn → canned low acid; the rice → white rice; the water → Water / bottled water; cinnamon rolls and the protein bar → no guess (Other food);
- the phrase-before-word cases;
- no false hits inside words ("rice" in "licorice");
- every mapped key exists.

## Task 5: Calories on the walk card and the add form

- [ ] The walk card's calories row:
  - calories known → "248 kcal per can · from Open Food Facts";
  - otherwise, the serving line and **Servings per container** (a decimal field), with **Net weight** as a toggle when kcal per 100 is known, and **Scan the label**;
  - empty → Add still works, with "No calories yet" in amber.
- [ ] The add form shows the same row under the product for a new product. The product form's existing per-package helper stays, and gains the servings input.
- [ ] Decision 8: a net weight over the threshold switches a new product to mass or volume, with a one-line note.
- [ ] Large text: the row stacks, as in Slice 4 Task 12.

**Done when:** on the simulator, typing the corn's barcode in a walk and entering 3.5 servings saves it at 280 kcal per can, with no Focus next item for it.

## Task 6: Scan the label

- [ ] Generalize `DateTextScannerSheet` into a text scanner that takes a parser. Add **Scan the label** to the walk card, the add form and the not-found form.
- [ ] The sheet shows the live reading (calories, servings, net weight) and the calories per item it gives. **Use this** fills the card or form, and the user still taps Add or Save.

**Done when:** on Hampton's phone, pointing at the corn's panel fills 80 × the servings shown, and Add saves it.

## Task 7: Category guess in the UI

- [ ] On the walk card, the add form and the not-found form, a guessed profile shows as "Guessed from the name: Canned, low acid · Change". Change opens the profile picker.
- [ ] For not-found items the guess updates as the name is typed, until the user picks a profile (Decision 7).

**Done when:** the corn scanned with no categories shows the canned low acid guess, and a typed "Brown rice" picks brown rice.

## Task 8: Walk summary and Focus next

- [ ] The walk summary adds "N items have no calories", opening the same Missing calories list as Focus next. It shows only when N > 0.
- [ ] That list's rows say why each item is missing calories ("Open Food Facts had no serving data", "skipped on the card"), and offer **Scan the label** for each.

## Task 9: Device walk-through

- [ ] `docs/slice-5-walkthrough.md`, using Hampton's corn, rice, water, rolls and bar, plus one label he picks. It covers: single-serving fill (the bar); servings (the corn); net weight; the label scan on a dual-column panel; the rice switching to mass from its net weight; the name guess for corn; a typed not-found name being guessed; a walk of one shelf ending with no missing calories; and nothing overwriting a typed value.
- [ ] Run `swift test`, `xcodegen generate` and both builds, then hand the script to Hampton and wait for the report.

## Dependencies

- Tasks 1, 3 and 4 have no Slice 5 dependencies.
- Task 2 depends on Task 1.
- Task 5 depends on Tasks 2 and 4.
- Task 6 depends on Tasks 3 and 5.
- Task 7 depends on Task 4.
- Task 8 depends on Task 5.
- Task 9 depends on Tasks 6, 7 and 8.

## Needed from Hampton

- Photos of 6–8 Nutrition Facts panels from the pantry (the corn, something dual-column, a bulk bag, and a can that prints "about" servings) for Task 3's fixtures.
- A yes, no or edit on Decisions 1–10.
