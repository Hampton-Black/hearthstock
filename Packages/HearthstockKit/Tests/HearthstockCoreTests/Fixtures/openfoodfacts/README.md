# Open Food Facts fixtures

Responses from `GET https://world.openfoodfacts.org/api/v3/product/<barcode>?fields=code,product_name,product_name_en,brands,quantity,product_quantity,product_quantity_unit,serving_quantity,serving_quantity_unit,serving_size,nutriments,categories_tags`, recorded 2026-10-18 with the User-Agent `Hearthstock/0.1.0 (hampton.j.black@gmail.com)`. They're pretty-printed with sorted keys; otherwise exactly as received.

| File | Barcode | HTTP | What it covers |
| --- | --- | --- | --- |
| `corn.json` | 0041220156726 | 200 | A can from Hampton's pantry. No net quantity, no categories. |
| `cinnamon-rolls.json` | 0078742298603 | 200 | Bakery box. No net quantity; snack and cake tags only. |
| `protein-bar.json` | 0749826002378 | 200 | Single bar. Empty `quantity` string, no net quantity. |
| `rice-25lb.json` | 0838927509319 | 200 | 25 lb bag of rice. No net quantity, no categories. |
| `water-40pack.json` | 0096619879212 | 200 | Costco water case. No name, brand, categories or energy; `serving_quantity` is the string `"500"`. |
| `not-found-rhino-pak-jug.json` | 0060823858011 | 404 | 6 gal water jug (the container's barcode): not found. |
| `campbells-soup.json` | 0051000012616 | 200 | Condensed soup can with a net quantity (297.67 g) and `en:canned-foods`. |
| `barilla-penne.json` | 0076808280739 | 200 | 1 lb box of pasta: net quantity 453.59 g, `en:dry-pastas`. |

Real responses rarely carry a net quantity, so three cases the mapping must handle are **derived** from the recordings above, changing only the fields named:

| File | From | Changed |
| --- | --- | --- |
| `derived-rice-25lb-with-size.json` | `rice-25lb.json` | `quantity` "25 lb", `product_quantity` "11339.809" (a numeric string), unit g, rice category tags |
| `derived-soup-kj-only.json` | `campbells-soup.json` | every kcal nutriment removed, `energy-kj_100g` 348.67 |
| `derived-water-named.json` | `water-40pack.json` | name, brand, `quantity`, `product_quantity` "500" ml, water category tags |

What the recordings showed about the v3 shape: the envelope has `status` (`success` / `failure`) and `result.id` (`product_found` / `product_not_found`), not `status_id`; not found is HTTP 404 with the same envelope. Numbers can arrive as strings (`serving_quantity: "500"`).
