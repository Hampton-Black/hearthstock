# Nutrition Facts panel fixtures

Live Text transcriptions of real Nutrition Facts panels from Hampton's pantry (Slice 5 Task 3), and what
`NutritionLabelParser` should read from each. `NutritionLabelFixtureTests` runs every pair in this folder.

Each panel is two files with the same name:

- `<name>.txt`: the panel's text exactly as Live Text returns it, line breaks included.
- `<name>.expected.json`: the expected reading. Leave a field out when the panel doesn't print it.

```json
{
  "caloriesPerServing": 80,
  "caloriesPerContainer": 280,
  "servingsPerContainer": 3.5,
  "servingsAreApproximate": true,
  "servingSize": "1/2 cup",
  "servingQuantity": { "value": 125, "unit": "g" },
  "netWeight": { "value": 15.25, "unit": "oz" }
}
```

Units: `g`, `kg`, `oz`, `lb`, `ml`, `l`, `fl oz`, `gal`.

Wanted (from `docs/slice-5.md`): the H-E-B corn, a dual-column panel, a bulk bag, a can that prints "about"
servings, and two to four more from the pantry.

| Panel | Photo taken | What it covers |
| --- | --- | --- |
