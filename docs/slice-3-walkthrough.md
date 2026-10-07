# Slice 3 walk-through (Task 12)

A script for the simulator: what to tap, and what you should see. Expected numbers assume today is the day you run it; dates are given relative to that where it matters. Report any step that doesn't match.

## 0. Fresh install

1. Remove the app: long-press Hearthstock on the home screen → Remove App → Delete App (or `xcrun simctl uninstall booted com.example.hearthstock`).
2. Build and run the `Hearthstock` scheme (Debug).
3. **See:** three tabs, Runway, Inventory and Settings. Runway says "Home · no one yet" with an "Add your household to compute runway" card; the Food and Water cards show "— days".

## 1. Site and household

1. Tap **Add your household**. **See:** the Settings tab opens.
2. Site → Name: change "Home" to "Main house", press Done. **See:** the Runway subtitle changes to "Main house".
3. Use soon notice: tap + then −. **See:** 31 days, then 30 days.
4. Household → **Add person**: name "Hampton", calories 2400, water 1 → Save. Add a second person "Partner" and leave the defaults (2,000 kcal, 1 gal) → Save.
5. **See:** both rows ("2,400 kcal · 1 gal a day", "2,000 kcal · 1 gal a day"). Runway now shows "Main house · 2 people" and an "Add your first item" card.

## 2. Locations

1. **Add location** "House", climate **Climate controlled** → Save.
2. **Add location** "Pantry", Inside **House**, climate **Cool and dry** → Save.
3. **Add location** "Garage", climate **Hot / unconditioned**, humidity **Humid** → Save.
4. **Add location** "Garage shelf", Inside **Garage**, climate left on **Inherit from Garage** (it says "Currently Hot / unconditioned", 0.5×) → Save.
5. **Add location** "Go-bag", Inside **Pantry**, turn on **This is a kit** (leave "Counts toward runway" off) → Save.
6. **See:** the tree House › └ Pantry › └ Go-bag (Kit tag), Garage (Hot tag) › └ Garage shelf (Inherits).
7. Open **Garage** → Delete location → Delete. **See:** red text under the button: "Can't delete: Garage shelf is inside it. Move or delete it first." Go back.

## 3. Add the two Task 8 items and a case of water

**White rice, 20 lb, garage, best-by March 2025**

1. Runway → **+** → Choose product → **New product**.
2. Name "White rice", Category Food, Measured by **Mass**. Turn on **Enter per package**: kcal per package 32600, package size 20 lb. **See:** "= 1,630 kcal per lb". Profile **White rice**. Tap **Save**.
3. Back on Add item: amount 20, unit **lb**. Printed date → **Month** → year arrows to 2025 → **Mar** → Done. Location **Garage shelf**. Tap **Save**.
4. **See:** "Saved to Garage shelf", **Expired** badge ("Past its usable-by date…": 24 months past best-by, halved by the hot garage), Runway "Not counted (expired)". Tap **Add another**.

**Black beans, 6 cans, printed 14 months ago**

5. Choose product → New product "Black beans, 15 oz can", Food, **Count**, kcal per item 385, profile **Canned, low acid (meat, beans, vegetables)** → Save.
6. Amount 6 (count products start at 1; type 6). Printed date → **Exact day** → pick the date 14 months before today → Done. **See:** under Dates, "Today this is Caution". Location **Pantry** (it isn't preselected: last used was Garage shelf, shown with a "Last used" tag). Tap **Save**.
7. **See:** **Caution**, "Past its best-by date but still usable until …", Runway "+2,310 kcal, high end only". Tap **Add another**.

**A case of water: 24 × 0.5 L**

8. New product "Bottled water, 0.5 L", Category **Water**, Measured by **Volume** (the Drinking water section says "Counts gallon for gallon"), profile **Bottled water** → Save.
9. Amount 0.5, unit **L**, turn on **× packs**, packs 24 (use + or type). **See:** "**24 × 0.5 L = 3.17 gal** will be saved". Printed date → Month → a year from now → Done. Location **Pantry**. Tap **Save + add another**.
10. **See:** the form clears the product, quantity and date but keeps **Pantry** and the acquired date, and a "Saved Bottled water, 0.5 L" banner with a **Good** badge. Tap Cancel.

## 4. Dashboard

1. **See** on Runway: "You could last about **under 1** day" in red with "Food is below the 3-day minimum" (only the Caution beans count, and only toward the high end). Food card "under 1 day", "2,310 kcal on hand", "Need 4,400 a day", outlined red. Water card "1 day", "3.2 gal drinkable", "Need 2 gal a day".
2. Focus next: "+13,200 kcal food · Reaches 3 days", then "Black beans, 15 oz can · Caution · eat or rotate · 6 items".
3. Tap the beans row. **See:** its lot detail ("Why it's Caution": printed date, Canned low acid profile, Cool and dry from Pantry ×1.25, usable by, "+2,310 kcal, high end only"). Go back.
4. Tap the **Water** card. **See:** Inventory opens with a "Water ×" chip and only the bottled water. Tap the chip to clear it; every lot shows again.

## 5. Inventory, Use and Adjust

1. Inventory **By location**: "Garage › Garage shelf" (rice, Expired, with a Humid flag) and "House › Pantry" (beans Caution, water Good). **By category**: Food then Water, each row with its location path.
2. Search "bean" → only the beans. Clear the search.
3. Tap **Expiring soon** → only the beans (Use soon, Caution and Inspect; not Good or Expired). Tap it again to turn it off.
4. Swipe left on the beans → **Use**. **See:** "Use some", 1 item prefilled; set 2 → "4 items left after this" → **Use 2 items**. Set it to 10 instead to check the guard first: "Only 6 items left." with a "Use all 6 items" button.
5. Runway: Food card now "1,540 kcal on hand"; the Focus next row says 4 items.
6. Swipe left on the water → **Adjust** → set 2 (gal) → **Set to 2 gal**. Runway water card: "2 gal drinkable", "1 day".
7. Open the rice → **Delete lot** → Delete. **See:** it's gone from Inventory; the Dashboard numbers don't move (it was expired).
8. Open the beans → Edit → **Edit product** → **See** the warning "Changes apply to every lot of this product" and Measured by locked ("Fixed: this product already has lots…"). Cancel.

## 6. Backup round trip

1. Settings → **Export backup** → Save to Files → On My iPhone → Save. **See:** "Last: <today>" next to Export backup.
2. Add a throwaway item (any product, any amount) so the database differs from the file.
3. Settings → **Restore from backup…** → pick the file. **See:** the file name and export date; "In this file" counts (2 lots, 3 products, 5 locations · 2 people); "Will be replaced" in amber with the current counts (3 lots…).
4. Tap **Replace with this backup** → confirm. **See:** the sheet closes; the throwaway item is gone; beans (4) and water (2 gal) are back; Runway matches step 5.
5. Export again → the new file lists the same lots (open both in Files, or just check the counts by restoring the second file: same numbers).
6. Optional: Restore from a JSON file that isn't a backup. **See:** "Can't restore this file" with the reason and "Nothing was changed."

## 7. Developer section

1. Debug build: Settings ends with "Developer · Debug builds only" → **Load sample pantry** refuses with "The site already has data…" (it only loads into an empty site).
2. On a fresh install, Load sample pantry → Runway shows **5–6 days**, water the weakest link, matching the fixture test (5.085–6.67 days).
3. A Release build has no Developer section (`xcodebuild … -configuration Release build`).
