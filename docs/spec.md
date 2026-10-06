# Prep Inventory App — v1 Spec

Oct 4, 2026 · @Hampton Black

## Overview

A local-first iOS app that tracks household food, water, power and gear, and answers one question at a glance: how many days could we last, and what is the weakest link?

**Why build it.** PrepVault's model logs items per serving and assumes everything was added today. Bulk goods (a 20 lb bag of rice) and older stock with past or near expiry dates are painful or impossible to enter. Here, quantities live on lots in real units, and every date is editable.

**Goals**

- Enter a bulk item or an old can in under 15 seconds, with any expiry date, past or future.
- Show runway in days for food, water and power, plus an effective runway (the minimum of the three).
- Track go-bags and other kits against a required manifest, flagging gaps and expiring items.
- Remind about rotation and maintenance (expiring lots, battery checks, fuel rotation).
- Work fully offline with no account; the data stays on the device unless sync is turned on.

**Non-goals for v1:** multi-user permissions, Android, recipes or meal planning, shopping integrations, any server.

## Data model

The key decision is splitting the **Product** (what something is) from the **Lot** (a specific quantity of it, with its own dates and location). Servings, calories, gallons and watt-hours are always derived from a lot's quantity, never typed in by hand.

&#91;embedded content: data model · 6 core entities\]

A kit is just a location with a template attached, so a go-bag's contents are ordinary lots and count toward the house totals unless you exclude them.

| Entity | What it is | Key fields |
| --- | --- | --- |
| Site | An independent place with its own runway (Main house, Bug-out cabin) | name, occupants (each a Person with name, kcal/day defaulting to 2,000, and water gal/day defaulting to 1.0), pets |
| Category | Drives the runway math | food, water, power, medical, tools, hygiene, other |
| Product | Reusable definition, often from a barcode | name, barcode?, category, role (supply, capability, consumable), base unit (lb, oz, gal, L, Wh, count), kcal per base unit, water per base unit, Wh per unit, shelf-life profile |
| ShelfLifeProfile | How a kind of item ages | date type (best-by or use-by), extension window (months), storage sensitivity |
| Lot | A specific quantity of a product | product, quantity + unit, acquired date (editable, can be in the past), printed date (optional, can be past), packaging (none, Mylar + O2, bucket, stabilized), location, climate override (optional, for a spot that differs from its room), notes, opened flag |
| Capability | What a capability product can do | kind (water treatment, recharge, cooking, preservation, fuel stabilization, lighting, comms), capacity + unit (gal treatable, Wh/day, meals per fuel unit), amount used |
| Location | Where a lot lives | name (Garage shelf, Pantry, Truck), site, parent location?, climate class, humidity (dry or humid), isKit flag |
| KitTemplate | Required manifest for a kit | name (72-hr go-bag), requirements: product or category + target quantity |
| ReadinessTemplate | Household-level capability checklist per category | site, category, required capability kinds (Water: storage, primary treatment, backup treatment, containers) |
| Kit | A location tied to a template | location, template, home site, counts toward site runway (default off for go-bags and vehicle kits), last inspected date |
| PowerLoad | Daily energy demand | site, device name, watts, hours/day, essential flag |
| MaintenanceTask | Recurring care for gear | target lot or product, interval (days), last done, instructions |

**Units.** Each lot stores quantity in its product's base unit, with conversion handled at entry ("20 lb" or "9 kg" → lb). Bulk rice is one lot of 20 lb. A case of water is one lot of 24 × 0.5 L, stored as 3.17 gal.

**Consumption.** Using something reduces a lot's quantity instead of deleting it. When a lot hits zero it's archived, which keeps a history for later "burn rate" estimates.

**Sites.** Every runway is scoped to one site. Locations belong to a site, so lots and capabilities (the cabin's wood stove and solar setup) count only where they physically are. Site ships in the v1 schema even while the UI shows a single site, because adding a site ID later would mean a migration touching every runway query. Kits keep a home site but are mobile: go-bags and vehicle kits are excluded from their site's runway by default, since their job is to leave with you.

**Shelf life.** A lot's estimated usable-by date is its printed date plus the profile's extension window, adjusted for packaging and the location's climate. Use-by items (infant formula, medications, refrigerated goods) get no extension. Mylar with oxygen absorbers switches a dry-goods lot to a much longer profile, and a hot garage shortens it. Bundled defaults are conservative and editable per product and per lot.

**Storage climate.** Each location has a climate class that scales the extension window. A common rule of thumb is that shelf life roughly halves for every 10 °C (18 °F) of extra storage temperature, so the multipliers below are approximate defaults, editable per location. A child location inherits its parent's class unless it sets its own.

| Climate class | Typical examples | Temperature | Window multiplier | Notes |
| --- | --- | --- | --- | --- |
| Cool and dry | Basement, interior closet, insulated pantry | Below 65 °F, stable | 1.25× | Best general storage |
| Root cellar / earth-sheltered | Root cellar, buried or bermed storage | 40–60 °F, stable | 1.25× | Usually humid: flags cans, cardboard and paper for rust or mold; sealed buckets and Mylar are fine |
| Climate controlled | Living space, conditioned room | 65–75 °F, stable | 1.0× | Baseline |
| Insulated, unconditioned | Insulated garage or shed | Moderate swings | 0.75× |  |
| Hot / unconditioned | Uninsulated garage, attic, outdoor shed | Above 85 °F in summer, large swings | 0.5× | Also flags lithium batteries and stored fuel |
| Vehicle | Car kit, truck bed box | Extreme swings | 0.33× | Shortens water bottle, food bar and battery checks for car kits |
| Refrigerated / frozen | Fridge, chest freezer | Below 40 °F / below 0 °F | Per product | Power-dependent: counts toward runway only while power runway lasts, unless a generator or solar covers the load |

Humidity is its own flag because it affects packaging, not temperature: a humid location shortens unsealed paper, cardboard and can-based lots, and adds a rust check to tools and gear stored there.

| State | Rule | Shown as |
| --- | --- | --- |
| Good | Before printed date | Normal |
| Caution | Past best-by, inside the extension window | Amber: eat or rotate first |
| Inspect | Final 20% of the window | Amber with a check prompt; bulging, rusted or leaking cans are discarded regardless of date |
| Expired | Past the window, or past any use-by date | Red, excluded from runway |

**Capabilities.** Some products add no supply of their own; they unlock, replenish, extend or enable supply. A filter, solar panel, stove or box of oxygen absorbers is a Product with role *capability* (or *consumable*, for tabs and absorbers) plus a Capability record. Capacity is consumed over time: a filter rated for 1,000 gallons tracks gallons used, and a tab count converts to gallons treatable.

## Runway dashboard

Each site has its own runway. Effective runway is the shortest of that site's supply runways, shown as a range: the low end counts only in-date stock, the high end adds Caution and Inspect lots. Plan around the low number; the gap between the two is how much stock needs rotating soon. The category that sets the low end is the top priority.

```latex
\text{food days}_{\text{low}} = \frac{\sum_{\text{Good lots}} \text{qty} \times \text{kcal per unit}}{\sum_{\text{occupants}} \text{kcal per day}} \qquad \text{food days}_{\text{high}} = \frac{\sum_{\text{Good + Caution + Inspect lots}} \text{qty} \times \text{kcal per unit}}{\sum_{\text{occupants}} \text{kcal per day}}
```

```latex
\text{water days} = \frac{\text{potable gal} + \min(\text{non-potable gal}, \text{treatment capacity left})}{\sum_{\text{occupants}} \text{gal per day}}
```

```latex
\text{power days} = \frac{\text{usable Wh (batteries + fuel)}}{\sum_{\text{essential loads}} \text{watts} \times \text{hours per day} - \text{derated recharge Wh per day}}
```

```latex
\text{effective runway} = \min(\text{food}, \text{water}, \text{power}) \text{, as a low to high range}
```

**Rules**

- Expired lots never count. Caution and Inspect lots count only toward the high end of the range; a single discounted number is an optional setting, off by default.
- Non-potable water (water heater, rain barrels, pool) counts only up to the remaining capacity of treatment capabilities. With no treatment on hand it is shown beside the main figure, not inside it.
- Usable Wh applies a derate (default 80%) for depth-of-discharge and inverter losses. Fuel counts only if a generator Product gives Wh per gallon.
- Recharge (solar, hand crank) is derated for weather (default 50% of rated output). If derated recharge covers the essential load, power shows "sustainable in sun" instead of a day count.
- Cooking check (end of v1.1, see Cooking and fuel): dry goods that need cooking are compared against cooking fuel (meals per fuel unit). A shortfall is flagged but doesn't reduce food days.

**"Focus next" list**, in priority order:

1. The limiting category, with the amount needed to reach the next target (for example, "+18 gal water to reach 14 days"). Targets default to 3, 14 and 30 days.
2. Lots in Caution or Inspect (eat or rotate), soonest first.
3. Missing capabilities from the readiness templates (for example, "No backup water treatment") and cooking shortfalls ("Rice exceeds cooking fuel by \~40%").
4. Kit gaps: missing or short requirements, and expired items inside kits.
5. Overdue maintenance tasks and capabilities near their rated limit (a filter at 90% of its gallons).

A home screen widget shows the effective runway range, the limiting category, and the count of items needing attention.

**Multiple sites (v2).**

- **Site switcher and all-sites summary:** each site's runway range side by side, never summed, since stock at the cabin doesn't feed the house.
- **Relocation scenario:** destination site's stock plus the kits and vehicle loads you bring, for example "Cabin alone: 21 days; with go-bags and truck kit: 26 days."
- **Resupply list:** what to stage at another site on the next trip, driven by that site's Focus next list.

## Cooking and fuel

Scheduled last in v1.1 polish. Cooking fuel becomes a fourth runway, measured in cooking hours, so dry goods aren't counted as edible without a way to cook them. Utility natural gas and grid power are excluded by default; a toggle shows utility gas as a note beside the figure, never inside it.

```latex
\text{cooking days} = \frac{\sum_{\text{allocated fuel lots}} \text{energy} \times \text{stove efficiency} \,/\, \text{stove burn rate}}{\text{daily cooking hours for food that needs cooking}}
```

- **Fuel lots** carry energy content: propane (20 lb tanks, 1 lb cylinders), butane and isobutane canisters, white gas, kerosene, firewood (cords or partial), charcoal, pellets, denatured alcohol, solid fuel tabs, canned heat. Defaults are approximate, such as about 430,000 BTU per 20 lb propane tank and 15–30 million BTU per cord of firewood depending on species.
- **Stoves** are capabilities with a burn rate, an efficiency and the fuels they accept (camp stove, rocket stove, wood stove, grill, backpacking stove). Electric cooking (induction plate, kettle, pressure cooker) draws Wh from the power runway instead of fuel, and a solar oven needs no fuel but only counts on sunny days.
- **Foods** get a cook time per batch: zero for canned goods, about 20 minutes for white rice, an hour or more for dried beans (much less with a pressure cooker). Cooking water is subtracted from the water runway.
- **Shared fuel pools.** Propane or firewood may also feed a generator or heater. Fuel is a pool with consumers drawing from it, split by a user-set allocation with a sensible default, so nothing is counted twice. The dashboard shows the trade-off, for example "propane covers 30 days of cooking or 4 days of generator."

## Screens and flows

Five tabs cover v1: Dashboard, Inventory, Kits, Tasks, Settings. Adding stock is the most frequent action, so it gets the most attention.

| Screen | Purpose | Notes |
| --- | --- | --- |
| Dashboard | Runway per category, effective runway, Focus next list | Tapping a category drills into its lots |
| Inventory | All lots, grouped by location or category | Search, filter by expiring soon, swipe to consume or adjust |
| Add / Scan | Create a lot, and a product if new | Camera opens by default; manual entry is one tap away |
| Kits | Each kit against its template, plus household readiness checklists | Green / short / missing per requirement; "Mark inspected" |
| Tasks | Maintenance due and overdue | Complete resets the interval |
| Settings | Household, defaults, targets, export | CSV/JSON export and import for backup |

**Add flow (the PrepVault fix)**

1. Scan a barcode with VisionKit's live scanner. A known barcode prefills the product from local data; an unknown one optionally looks it up in Open Food Facts for name and kcal.
2. Enter quantity with a unit picker ("20 lb", "6 cans", "5 gal"). One bulk item is one lot.
3. Set expiry: point the camera at the printed date and Live Text fills it in, or pick any date, including past ones. "No expiry" is a valid choice.
4. Acquired date defaults to today but is editable, which matters when back-filling an existing pantry.
5. Pick a location; the last-used one is preselected.

**Back-fill mode.** A "pantry walk" mode keeps the camera open and the location fixed, so you can scan shelf by shelf and confirm each item with a single tap.

## Tech stack

Recommendation: **SQLite through GRDB**, with domain logic in a plain Swift package that doesn't know about storage. SwiftData is the faster start, but this app is mostly aggregate math over lots, and that's where SQL is strongest.

**Fixed choices:** SwiftUI, iOS 18+ minimum, VisionKit `DataScannerViewController` (barcodes and Live Text dates), WidgetKit, App Intents (Siri / Shortcuts), UserNotifications for local reminders, Swift Testing for the runway math.

|  | SwiftData | SQLite via GRDB |
| --- | --- | --- |
| Getting started | Fastest: `@Model` classes, `@Query` in views | A bit more setup: record structs, explicit migrations |
| Runway queries (sums, group by) | Weak: `#Predicate` can't aggregate, so you fetch and sum in memory (fine at this scale) | Natural: `SUM(qty * kcal) GROUP BY category` in one query |
| Schema changes | `VersionedSchema` + migration plans; quirks when things go wrong | Explicit numbered migrations you write and test |
| SwiftUI reactivity | Built in | `ValueObservation`, or a wrapper library |
| iCloud sync | Built in for your private database, but adds constraints (optional properties, no unique constraints). No shared-database support for a household | Not built in. Options: `CKSyncEngine` by hand, or a GRDB-based library with CloudKit sync such as Point-Free's SQLiteData (verify current status before relying on it) |
| Debugging and inspection | Opaque, Core Data underneath | Open the `.sqlite` file in any SQL tool |
| Feel | Apple magic, macros | Explicit, closer to how you'd work with Postgres |

**Why GRDB here:** the dashboard is aggregate queries, migrations stay predictable, and the file is easy to inspect and back up. SwiftData's main advantage, effortless sync, doesn't cover the household-sharing case anyway. With a second user likely later, that settles it: GRDB now, CloudKit sharing in v2.

**Hedge:** keep the domain layer (`Product`, `Lot`, `RunwayCalculator`, unit conversion) as plain Swift value types in their own package, behind a small repository protocol. Switching storage later only touches the repository implementation, and the math is unit-tested without a database.

## Build plan

v1 is the smallest app that beats PrepVault for your house: fast scanning with Open Food Facts, pantry walk mode for back-filling, real-unit lots, any expiry date with Caution and Inspect states, food and water runway as a range, and go-bags. Capabilities, power and polish come once the pantry is actually entered.

&#91;embedded content: build plan · 3 phases, 2 gates\]

Each gate is about real use, not features: the schema should survive contact with your actual shelves before sync locks it in.

## Decisions

- **Users:** just you for now, possibly your wife later. Storage stays GRDB so CloudKit sharing can be added in v2.
- **Calories and water:** per-person targets, in v1.
- **Power scope:** everything: power stations, AA/AAA stock, vehicle fuel, propane.
- **Starter kit templates:** a per-person go-bag, first-aid kit, house preps, and a vehicle kit for when you build one.
- **Readiness templates:** all six ship as defaults: water, power, cooking, food preservation, lighting, comms.
- **Shelf life:** a bundled conservative table, editable per product and per lot.
- **Platform:** iPhone only.
