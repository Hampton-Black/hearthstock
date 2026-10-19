# Slice 4 walk-through (Task 14)

A script for your iPhone, with a simulator section at the end: what to tap, and what you should see. It uses items from your pantry (the corn, the 25 lb rice, the Costco water and the Rhino-Pak jug) plus Campbell's soup. Expected dates assume today is the day you run it. Report any step that doesn't match.

Before you start: Settings → **Export backup**, so you can get today's data back afterwards.

## 0. Camera permission

1. Delete the app, then build and run it on the phone. (Or use iOS Settings → Hearthstock → Camera → off to test step 3 without reinstalling.)
2. Runway → **+**. **See:** iOS asks for the camera. Allow it. **See:** the dark Add · scan screen with corner brackets, "Point at a barcode", the "Into <location>" chip, **Type it in** and **Pantry walk**.
3. iOS Settings → Hearthstock → Camera → off. Back in the app, **+**. **See:** "Camera is off for Hearthstock", **Open Settings** and **Type a barcode**. Hearthstock Settings → Scanning also shows "Camera: Off" with **Open iOS Settings**. Turn the camera back on and return. **See:** the camera comes back without restarting the app.

## 1. Undated lots

1. **+** → **Type it in** → new product "Test can", Food, Count, profile **Canned, low acid** → Save. Amount 1, leave **Printed date** alone. **See:** the row reads "Not set" in amber. Save.
2. **See:** the lot detail says "No printed date entered, so it counts as Good for now…". Runway → Focus next ends with "N lots need a date". Tap it. **See:** Inventory filtered to **Needs a date**, with a chip that clears it. The can's row shows the **No date** flag.
3. Open the can → Edit → Printed date → turn on **No date on the package**. **See:** "Est. usable by" about 2 years after Acquired (half that in a hot location), and an Estimate stepper at "2 years". Set Acquired to a year ago first if you want to see the estimate move.
4. Step the estimate to 3 years. **See:** "Est. usable by" moves out a year and **Use the default (2 years)** appears. Done → Save.
5. **See:** the row reads "est. use by …", the detail says "No printed date, so it's estimated from when you got it…", the timeline reads "Bought … / Est. usable by …", and the can is no longer under Needs a date. Delete the test can.

## 2. Scanning a can already in inventory

1. Scan the corn (0041220156726) and save it if it's new: 2 cans, its printed date, a location.
2. **+** and scan the corn again. **See:** **Already have this** with your lot (quantity, location and badge) and "Different date: start a new lot" ticked.
3. Pick your lot, set **Adding** to 2 → **Add**. **See:** "Added 2 items to …" over the camera and a buzz. The lot now has 4.
4. Scan it once more, keep **Different date**, then Next. **See:** the add form with the corn already chosen. Cancel. Nothing new was saved.

## 3. Found in Open Food Facts

1. **+**, scan a can you haven't added yet (or type `051000012616` for Campbell's soup). **See:** "Looking up 0051000012616…", then the add form with "Filled in from Open Food Facts. Check the name and calories." and the name "Campbell's Cream Of Mushroom Soup, 10.5 oz".
2. Tap the product (Change). **See:** Count, **248** kcal per item, profile Canned, low acid, barcode 0051000012616. Cancel, then Save the item.
3. Scan the 25 lb rice (0838927509319). **See:** name "Kings Enriched Long Grain Parboiled Rice", Count, no calories (the database has no package size). Open the product, switch Measured by to **Mass**. **See:** kcal per lb fills in as **1,641**. Save.

## 4. Saved lookups

1. Turn on Airplane Mode. **+** and type `051000012616` again. **See:** **Already have this**: the product is local now. Then type the corn's code if it isn't saved yet, or any code you scanned in step 3 and cancelled. **See:** it still fills in, from the saved answer, with no network.
2. Still in Airplane Mode, scan something new. **See:** **Not found** with "Couldn't look it up right now: no internet connection." and the wifi-slash icon. Fill in a name, leave calories empty, Next → Save.
3. **See:** Runway → Focus next lists "1 product missing calories". Turn Airplane Mode off. Open that list → the product → **Look up online**. **See:** "Filled in calories…" (or "Nothing new…" if Open Food Facts has nothing). The name you typed doesn't change.
4. Settings → Online lookup. **See:** "Saved lookups" shows the count. Turn **Look up unknown barcodes** off and scan another new item. **See:** **Not found** saying "Online lookup is off", with no network used. A barcode looked up earlier still fills in.
5. **Clear saved lookups** → confirm. **See:** the count goes to 0. Turn lookups back on.

## 5. A made-up barcode

1. **+** → **Type a barcode** → `099999000016` → Use. **See:** **Not found**, the barcode kept (0099999000016), and Name, Category and Calories per item.
2. Name "Test item", calories 100 → Next → Save. **See:** saved with +100 kcal per item, and no "missing calories" item in Focus next. Delete it afterwards.
3. Type `036000291453` (wrong check digit). **See:** the sheet stays open with "That barcode doesn't add up. Check the digits for a typo."

## 6. Pantry walk

1. **+** → set the chip to a shelf → **Pantry walk**. **See:** the shelf name locked at the top left, and **Done**.
2. Scan the Costco water. **See:** a light card, Water, a quantity stepper, a date chip and **Skip** / **Add to <shelf>**. Set 2, tap the date chip → pick its best-by → Done → **Add**. **See:** a buzz, "1 added this walk", "Added … · Undo".
3. Scan the same case again. **See:** **Scanned again** with "Add another · makes …", **Oops, double scan** and **Different date**. Tap **Oops**. Scan it again → **Add another**. **See:** "now …".
4. Scan the Rhino-Pak jug. **See:** "NOT FOUND · ADD WHAT YOU KNOW" with a name field. Type "Rhino-Pak 6 gal, tap water", category **Water** → Add. It's counted per jug. Afterwards, in Inventory open it → Edit product, turn off **Not potable** if it's on, set **6** gallons per item, and set the profile to **Stored tap water**. **See:** Runway water goes up by 6 gal per jug.
5. Scan a can and leave its date chip at **Add date** → Add. Then tap **Undo** on the "Added" row. **See:** the count drops by one and the can is gone from Inventory. Scan it again and add it without a date.
6. Tap **Done**. **See:** "<Shelf> done", "N items in M lots · about X minutes", runway before → after for water and food, "1 item needs a date", and the Added list with × counts. Tap a row. **See:** its lot detail. Close it.
7. Tap **1 item needs a date**. **See:** the walk closes and Inventory opens on Needs a date.
8. Optional: start another walk, add one item, Done → **Walk another spot** → pick another location. **See:** a fresh walk there.

## 7. Live Text on a printed date

1. **+** → **Type it in** → pick any canned product → Printed date. **See:** **Scan the date** above the month grid.
2. Tap it and point at a can's printed date. **See:** "Use this date" with the date and its type (for example "Best by Mar 5, 2027"), and other readings as smaller buttons when the date is ambiguous (03/05/27 offers March 5 first, then May 3).
3. Tap Use this date. **See:** the grid or the day picker set to that date, "Read from the package… Check it before tapping Done", and "Today this is <state>" below. Done.
4. Lot codes and times on the package ("L2304 14:32") should never be offered as dates.

## 8. Torch

1. In any scanner, tap the flashlight button. **See:** the light comes on and scanning keeps working. Tap it again. Leaving the screen turns it off.

## 9. Backup round trip

1. Settings → **Export backup** → save.
2. Restore from that file. **See:** "This backup matches what's on this iPhone". This file is format version 3: it includes the no-printed-date flags and the saved lookups.
3. Restore the backup you made before step 0 if you want your earlier data back.

## 10. Simulator (typed barcodes)

1. Run on the iPhone 17 Pro simulator. **+**. **See:** "Scanning isn't available here" with **Type a barcode**; no torch button.
2. Type `051000012616` → found (or Already have this). Type `099999000016` → Not found. Type `036000291453` → the check-digit error.
3. **Pantry walk** → Type a barcode → the card → Add → type the same code → **Scanned again** → Done → the summary.
4. Settings → Scanning reads "Camera: Not available".
