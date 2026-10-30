# Slice 5 walk-through (Task 9)

A script for your iPhone: what to tap, and what you should see. It uses items from your pantry (the corn, the 25 lb rice, the Costco water, the cinnamon rolls and the protein bar) plus one Nutrition Facts panel you pick. Report any step that doesn't match.

Before you start:

- Settings → **Export backup**, so you can get today's data back afterwards.
- Settings → Online lookup → **Clear saved lookups**. Answers saved by Slice 4 don't have the serving size, so the bar wouldn't be recognized as one serving until it's looked up again (Decision 9).
- If the corn, rice, rolls or bar are already products, delete them (or their test lots) so each scans as new. Undo in a walk also removes a product it created.

## 1. Single serving: the bar

1. **+**, scan the protein bar (0749826002378). **See:** the add form, and under the product "190 kcal per item · from Open Food Facts", with no question.
2. Tap **Edit** beside the calories. **See:** a kcal field holding 190, editable. Put it back to 190.
3. Save it with any date.

## 2. Servings: the corn

1. **+**, scan the corn (0041220156726). **See:** "Guessed from the name: Canned, low acid · Change", then "No calories yet" in amber, "80 kcal per serving (0.5 cup (125 g))", **Servings per container**, a **Net weight instead** toggle and **Scan the label**.
2. Type **3.5** in Servings per container. **See:** "280 kcal per item · 80 × 3.5 servings". Save.
3. Runway → Focus next. **See:** no "missing calories" item for the corn.

## 3. Net weight

1. Delete the corn you just saved (or scan a different can with only per-serving data). Scan it again.
2. Turn on **Net weight instead**, type **15.25** and leave the unit at **oz**. **See:** "277 kcal per item · from the 15.25 oz net weight". Turn the toggle off. **See:** the servings answer comes back if you'd typed one, or "No calories yet".
3. Cancel.

## 4. The rice switches to pounds

1. **+**, scan the 25 lb rice (0838927509319). **See:** "Guessed from the name: White rice · Change", "No calories yet", "170 kcal per serving (0.25 cup (47 g))".
2. Turn on **Net weight instead**, type **25**, unit **lb**. **See:** "1,641 kcal per lb · from Open Food Facts", the note "Over 2 lb, so it's measured by weight now: calories are per lb", and the quantity reads **25 lb**.
3. Change 25 to **2**. **See:** it goes back to 1 item, with calories per item. Put 25 back and Save. **See:** the saved lot is 25 lb.

## 5. Scan the label (a dual-column panel)

1. Pick a package whose panel has two columns ("Per serving" and "Per container"). Scan its barcode, or **Type it in** a new product if it isn't in Open Food Facts.
2. Tap **Scan the label** and point at the panel. **See:** the lines it reads (Calories per serving and per container, servings, serving size, Net Wt) and **Use this** with the calories per item. The per-container number should be the one used.
3. **Use this**. **See:** "N kcal per item · from the label". Nothing is saved yet. Save.
4. Repeat on the corn's panel if you like. **See:** 80 × the servings printed.

## 6. A typed name is guessed

1. Turn on Airplane Mode (or scan a barcode Open Food Facts doesn't know). **See:** **Not found**.
2. Type **Brown rice** as the name, one letter at a time. **See:** nothing guessed at first, then "Guessed from the name: Brown rice · Change" once the words match.
3. **Change** → pick **White rice**. **See:** "Shelf life: White rice". Edit the name to "Brown rice, 2 lb". **See:** it stays White rice.
4. Category → **Water**, then back to **Food**. **See:** the profile follows the category default, then the name guess again only if you hadn't picked one. Rescan to leave. Turn Airplane Mode off.

## 7. Nothing overwrites a typed value

1. **+**, scan the corn again (delete it first if needed). Type **3.5** servings. **See:** 280.
2. Tap the product (Change) and set kcal per item to **300** in the product form → Save. **See:** "300 kcal per item · entered by you".
3. **See:** the servings question is gone, and nothing changes the 300 while you edit other fields. Only **Scan the label** → **Use this** replaces it, because that's a deliberate tap. Cancel.

## 8. A walk of one shelf

1. **+** → **Pantry walk** → pick a shelf with cans, the rolls and the water.
2. For each item, answer servings or use **Scan the label** on the card when calories are missing. For the rolls ("2 rolls" per serving), type the servings per container from the box.
3. Leave one item with no calories on purpose (**No calories yet**, then Add).
4. **Done**. **See:** "1 item has no calories" in amber under the runway. Tap it. **See:** Missing calories with that item, its reason (for example "Open Food Facts had no package size: servings were skipped on the card") and **Scan the label**.
5. **Scan the label** on it → **Use this**. **See:** the product form with the calories filled in. Save. Back on the summary, **See:** the line is gone.
6. Large text: iOS Settings → Accessibility → Display & Text Size → Larger Text, at an accessibility size. Scan one more item. **See:** the calories row stacks its label above its field.

## Report

For each section, "matches" or what you saw instead. Also run `swift test`, `xcodegen generate` and both the Debug and Release builds, and note any build error with its file and line.
