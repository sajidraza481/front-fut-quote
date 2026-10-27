# Painting pack: field specs, quantities and golden vectors

Status: **Approved 2026-10-27** (V1–V11). Implemented in `packages/quote_engine`; vectors in `packages/quote_engine/test/vectors/painting/`.

All hand calculations below were cross-checked with an independent reference script (exact rational arithmetic, separate from the Dart engine).

---

## 1. Section fields (`sectionFields()`)

One section = one room. Each field has a pack default; a trader can set their own default per business (stored on the server), and override any field per room.

| Field id | Type | Unit | Pack default | Limits | Notes |
|---|---|---|---|---|---|
| `length` | length | m or ft/in | — (required) | > 0, ≤ 100 m | |
| `width` | length | m or ft/in | — (required) | > 0, ≤ 100 m | |
| `height` | length | m or ft/in | — (required) | > 0, ≤ 10 m | Wall height |
| `openings` | list of {width, height, count, kind} | m or ft/in | empty | count ≥ 1 | `kind` = `door` / `window` / `other` (default `other`); subtracted from walls |
| `coats` | whole number | — | 2 | 1–4 | Finish coats on walls, and ceiling if included |
| `includeCeiling` | yes/no | — | no | | |
| `primer` | yes/no | — | no | | One primer coat on the surface area |
| `surfaceCondition` | choice | — | `good` | `good` / `fair` / `poor` | Selects the prep rate (not a multiplier) |
| `wallPaintItem` | price item | — | `wall_paint` | packed material, same unit | Which tin supplies wall paint (e.g. `wall_paint_5l`) |
| `ceilingPaintItem` | price item | — | `ceiling_paint` | packed material, same unit | Which tin supplies ceiling paint |
| `primerItem` | price item | — | `primer` | packed material, same unit | Which tin supplies primer |
| `extras` | list of extras (§4) | — | empty | | Trader-chosen extra lines |

Cutting-in and corners are included in the wall rate; they have no field.

## 2. Measured quantities

Computed by the pack, rounded half-up to 0.01 of the price list's unit (m² / m for metric lists, ft² / ft for imperial lists). Extras can use the ones marked *exposed*.

| Quantity id | Formula | Used by | Exposed to extras |
|---|---|---|---|
| `grossWallArea` | 2 × (length + width) × height | | no |
| `openingsArea` | Σ width × height × count | | no |
| `netWallArea` | max(0, grossWallArea − openingsArea), clamped per room | wall lines; wallpaper removal | **yes** |
| `ceilingArea` | length × width if `includeCeiling`, else 0 | ceiling lines | **yes** |
| `surfaceArea` | netWallArea + ceilingArea, counted once | prep, primer | **yes** |
| `coatedArea` | surfaceArea × coats | painting labour and paint (split into wall and ceiling parts, which have separate rates) | no |
| `perimeter` | 2 × (length + width), linear | | **yes** |
| `openingsCount` | Σ count | | **yes** |
| `doorCount` | Σ count of `door` openings | | **yes** |
| `windowCount` | Σ count of `window` openings | window frames default | **yes** |

Areas are computed exactly in integer units and rounded once (ADR-001); `surfaceArea` is the sum of the two already-rounded areas. Prep and primer are never multiplied by coats.

## 3. Pack lines and pricing rules

Lines appear in this order everywhere (engine, app, PDF): **labour before its material**.

| Line | Quantity | Kind | Metric default (UK) | Imperial default (USD) |
|---|---|---|---|---|
| Wall painting | netWallArea × coats | labour | 450p / m² | 45¢ / ft² |
| Wall paint | packs for netWallArea × coats | material | 3000p per 2.5 L tin, 12 m²/L, 10% waste | 4200¢ / gal, 350 ft²/gal |
| Ceiling painting | ceilingArea × coats | labour | 550p / m² | 55¢ / ft² |
| Ceiling paint | packs for ceilingArea × coats | material | 3000p per 2.5 L tin, 12 m²/L, 10% waste | 3800¢ / gal, 350 ft²/gal |
| Preparation | surfaceArea, at the rate for `surfaceCondition` | labour | good 0p · fair 150p · poor 300p / m² | good 0¢ · fair 14¢ · poor 28¢ / ft² |
| Primer application | surfaceArea (if `primer`) | labour | 300p / m² | 30¢ / ft² |
| Primer | packs for surfaceArea (if `primer`) | material | 1000p / L, 10 m²/L | 3500¢ / gal, 300 ft²/gal |

All default rates are placeholders; every trader edits them in their price list. Each vector embeds its own full price list, so changing a default never changes a vector.

**Tin size per room.** Each consumable line has a default item with its own pack size. A trader default or the room can choose another packed material in the same unit (e.g. 5 L instead of 2.5 L tins); the line then uses that item's price, pack size, coverage and waste, in the same position. There is no cheapest-mix of tin sizes.

Rules

1. **Packs.** A material item has a pack size (default 1 unit) and a waste % (default 0). Packs = ⌈area ÷ coverage × (1 + waste) ÷ pack size⌉, computed exactly with no intermediate rounding. The line quantity is the number of packs; the unit price is per pack. With the defaults this equals whole litres / gallons.
2. **Labour line total** = roundHalfUp(qty × unit price), in minor units.
3. **Markup** is one percentage per business, applied to **material** lines only, *inside* the unit price: marked-up unit price = roundHalfUp(unit price × (1 + markup)); line total = qty × marked-up unit price. The customer sees only the marked-up price, never a markup line.
4. Lines with quantity 0 or a 0p rate are omitted.
5. Subtotal = Σ line totals. Tax = roundHalfUp(subtotal × tax rate), once. Total = subtotal + tax. Prices are tax-exclusive.
6. Pack lines are priced from the price list only; a pack item without a price is a price-list error.

## 4. Extras

### 4.1 How an extra is priced

An extra is a price-list item added to a room. Its quantity comes from exactly one source:

| Source | Quantity | Example |
|---|---|---|
| A measured quantity (§2, exposed) | That quantity; units must match the item | Wallpaper removal, 500p / m² of `netWallArea` |
| `count` | A whole number the trader types (packs, for a packed material) | Radiators, 2500p × 2 |
| `entered` | A decimal the trader types, in the item's unit (not for `each` items) | Skirting boards, 13.10 m × 400p |
| `flat` | 1 | Protection and furniture moving, 2500p |

**Per-quote price.** The trader may set an extra's unit price on a quote. It is used as typed (no markup), flagged on the line, and stored in the quote snapshot. An extra whose catalog price is empty (high access) must have one, or the quote is invalid (`priceRequired`).

Extras otherwise follow the pack-line rules: line-level half-up rounding; markup inside the unit price for materials.

### 4.2 Launch extras catalog (UK only)

In the metric (UK) default catalog. The imperial catalog gets extras at US launch.

| Code | Extra | Unit | Quantity from (app pre-selects) | Default rate |
|---|---|---|---|---|
| `skirting_boards` | Skirting boards | m | entered | 400p |
| `doors` | Doors (both sides) | each | count | 4500p |
| `door_frames` | Door frames / architraves | each | count | 2000p |
| `window_frames` | Window frames and sills | each | `windowCount` (trader can change to a count) | 2500p |
| `radiators` | Radiators | each | count | 2500p |
| `wallpaper_removal` | Wallpaper removal | m² | `netWallArea` | 500p |
| `stain_block` | Stain block / mould treatment | m² | entered | 800p |
| `high_access` | High access (tower/scaffold) | each | flat | none — entered per quote |
| `protection` | Protection and furniture moving | each (room) | flat | 2500p |
| `wall_paint_5l` | Wall paint (5 L tin) | 5 L tin | chosen per room via `wallPaintItem`, or counted as an extra | 5500p (placeholder), 12 m²/L, 10% waste |

V9 and V10 use test-only extras to exercise the mechanism.

---

## 5. Vectors

Metric vectors use GBP and VAT 20%; V7 uses USD and 8% sales tax. Common openings: door 0.90 × 2.10 m = 1.89 m²; window 1.20 × 1.00 m = 1.20 m². Unless stated otherwise: 2 coats, no ceiling, no primer, condition good, markup 0%, no extras. "→" marks a half-up rounding.

V2–V10 carry the price list approved with them (paint 1200p / L in 1 L packs, no waste; good prep 50p), so their totals did not change when the UK defaults moved to tins and 0p good prep.

### V1: Golden vector

Room 4.0 × 3.5 × 2.5 m, door 0.8 × 2.0 m, window 1.2 × 1.0 m, 2 coats, condition good (0p). Price list: labour 600p / m²; wall paint 3000p per 2.5 L tin, 12 m²/L, 10% waste; markup 0%.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 2 × 7.50 × 2.50 = 37.50 − 1.60 − 1.20 | 34.70 m² |
| Labour – walls | 34.70 × 2 = 69.40 m² × 600p | 41 640 |
| Wall paint (2.5 L tin) | 69.40 ÷ 12 = 5.78 L × 1.10 = 6.36 L ÷ 2.5 = 2.54 → 3 tins × 3000p | 9 000 |
| Preparation (good) | 0p rate → omitted | — |
| Subtotal | | 50 640 |
| VAT 20% | 10 128.0 | 10 128 |
| **Total** | | **60 768 (£607.68)** |

### V2: No openings

Room 4.00 × 3.00 × 2.50 m.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 2 × 7.00 × 2.50 | 35.00 m² |
| Wall painting | 70.00 m² × 450p | 31 500 |
| Wall paint | ⌈70.00 ÷ 12 = 5.83⌉ = 6 L × 1200p | 7 200 |
| Preparation (good) | 35.00 m² × 50p | 1 750 |
| Subtotal | | 40 450 |
| VAT 20% | 8 090.0 | 8 090 |
| **Total** | | **48 540 (£485.40)** |

### V3: Openings larger than the wall (clamp), ceiling still priced

Room 2.00 × 1.00 × 1.00 m, openings 2 × (2.00 × 2.00 m), ceiling yes.

| Step | Calculation | Result |
|---|---|---|
| Gross wall − openings | 6.00 − 8.00 = −2.00 → clamp | 0.00 m² (wall lines omitted) |
| Ceiling | 2.00 × 1.00 | 2.00 m² |
| Ceiling painting | 4.00 m² × 550p | 2 200 |
| Ceiling paint | ⌈4.00 ÷ 12 = 0.33⌉ = 1 L × 900p | 900 |
| Preparation (good) | surface 0.00 + 2.00 = 2.00 m² × 50p | 100 |
| Subtotal | | 3 200 |
| VAT 20% | 640.0 | 640 |
| **Total** | | **3 840 (£38.40)** |

### V4: Primer coat, fair condition

Room 4.00 × 3.00 × 2.50 m, door + window, primer yes, condition fair.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 35.00 − 1.89 − 1.20 | 31.91 m² |
| Wall painting | 63.82 m² × 450p | 28 719 |
| Wall paint | ⌈63.82 ÷ 12 = 5.32⌉ = 6 L × 1200p | 7 200 |
| Preparation (fair) | 31.91 m² × 150p = 4 786.5 → | 4 787 |
| Primer application | 31.91 m² × 300p | 9 573 |
| Primer | ⌈31.91 ÷ 10 = 3.19⌉ = 4 L × 1000p | 4 000 |
| Subtotal | | 54 279 |
| VAT 20% | 10 855.8 → | 10 856 |
| **Total** | | **65 135 (£651.35)** |

### V5: Business markup 15% (inside material prices)

Room 5.00 × 4.00 × 2.40 m, door + window, markup 15%.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 2 × 9.00 × 2.40 = 43.20 − 3.09 | 40.11 m² |
| Wall painting (labour, no markup) | 80.22 m² × 450p | 36 099 |
| Wall paint | ⌈80.22 ÷ 12 = 6.69⌉ = 7 L × (1200p × 1.15 = **1380p**) | 9 660 |
| Preparation (good) | 40.11 m² × 50p = 2 005.5 → | 2 006 |
| Subtotal | | 47 765 |
| VAT 20% | 9 553.0 | 9 553 |
| **Total** | | **57 318 (£573.18)** |

The quote shows "Wall paint, 7 L @ £13.80". There is no markup line.

### V6: Ceiling included, poor condition

Room 3.65 × 2.75 × 2.40 m, door only, ceiling yes, condition poor.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 2 × 6.40 × 2.40 = 30.72 − 1.89 | 28.83 m² |
| Ceiling | 3.65 × 2.75 = 10.0375 → | 10.04 m² |
| Wall painting | 57.66 m² × 450p | 25 947 |
| Wall paint | ⌈57.66 ÷ 12 = 4.81⌉ = 5 L × 1200p | 6 000 |
| Ceiling painting | 20.08 m² × 550p | 11 044 |
| Ceiling paint | ⌈20.08 ÷ 12 = 1.67⌉ = 2 L × 900p | 1 800 |
| Preparation (poor) | 28.83 + 10.04 = 38.87 m² × 300p | 11 661 |
| Subtotal | | 56 452 |
| VAT 20% | 11 290.4 → | 11 290 |
| **Total** | | **67 742 (£677.42)** |

### V7: Imperial units (USD, US gallons, sales tax 8%)

Room 12 × 10 × 8 ft, door 3 × 7 ft, window 4 × 3 ft. Imperial price list.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 2 × 22 × 8 = 352.00 − 21.00 − 12.00 | 319.00 ft² |
| Wall painting | 638.00 ft² × 45¢ | 28 710 |
| Wall paint | ⌈638.00 ÷ 350 = 1.82⌉ = 2 gal × 4200¢ | 8 400 |
| Preparation (good) | 319.00 ft² × 5¢ | 1 595 |
| Subtotal | | 38 705 |
| Tax 8% | 3 096.4 → | 3 096 |
| **Total** | | **41 801 ($418.01)** |

### V8: Three coats (field override)

Room 4.00 × 3.00 × 2.50 m, door + window, coats 3.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 35.00 − 3.09 | 31.91 m² |
| Wall painting | 31.91 × 3 = 95.73 m² × 450p = 43 078.5 → | 43 079 |
| Wall paint | ⌈95.73 ÷ 12 = 7.98⌉ = 8 L × 1200p | 9 600 |
| Preparation (good) | 31.91 m² × 50p = 1 595.5 → | 1 596 |
| Subtotal | | 54 275 |
| VAT 20% | 10 855.0 | 10 855 |
| **Total** | | **65 130 (£651.30)** |

### V9: Extra priced per m² of net wall

Room 4.00 × 3.00 × 2.50 m, door + window. Extra: *Mould treatment*, labour, 150p / m², source `netWallArea`.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 35.00 − 3.09 | 31.91 m² |
| Wall painting | 63.82 m² × 450p | 28 719 |
| Wall paint | 6 L × 1200p | 7 200 |
| Preparation (good) | 31.91 m² × 50p = 1 595.5 → | 1 596 |
| Mould treatment | 31.91 m² × 150p = 4 786.5 → | 4 787 |
| Subtotal | | 42 302 |
| VAT 20% | 8 460.4 → | 8 460 |
| **Total** | | **50 762 (£507.62)** |

### V10: Extras by count and flat

Same room as V9. Extras: *Radiator off and refit*, labour, 1500p each, `count` = 2; *Furniture moving*, labour, 4000p, `flat`.

| Step | Calculation | Result |
|---|---|---|
| Wall painting | 63.82 m² × 450p | 28 719 |
| Wall paint | 6 L × 1200p | 7 200 |
| Preparation (good) | 31.91 m² × 50p = 1 595.5 → | 1 596 |
| Radiator off and refit | 2 × 1500p | 3 000 |
| Furniture moving | 1 × 4000p | 4 000 |
| Subtotal | | 44 515 |
| VAT 20% | 8 903.0 | 8 903 |
| **Total** | | **53 418 (£534.18)** |

### V11: Launch extras on the default UK catalog

Room 4.00 × 3.00 × 2.50 m, door 0.90 × 2.10 m, 2 × window 1.20 × 1.00 m. Default UK catalog (§3, §4.2). Extras: skirting boards entered 13.10 m (perimeter 14.00 − door 0.90); window frames from `windowCount`; protection and furniture moving, flat.

| Step | Calculation | Result |
|---|---|---|
| Net wall | 35.00 − 1.89 − 2.40 | 30.71 m² |
| Wall painting | 30.71 × 2 = 61.42 m² × 450p | 27 639 |
| Wall paint (2.5 L tin) | 61.42 ÷ 12 = 5.12 L × 1.10 = 5.63 L ÷ 2.5 = 2.25 → 3 tins × 3000p | 9 000 |
| Preparation (good) | 0p rate → omitted | — |
| Skirting boards | 13.10 m × 400p | 5 240 |
| Window frames and sills | windowCount 2 × 2500p | 5 000 |
| Protection and furniture moving | 1 × 2500p | 2 500 |
| Subtotal | | 49 379 |
| VAT 20% | 9 875.8 → | 9 876 |
| **Total** | | **59 255 (£592.55)** |

---

## 6. Covered by unit tests, not vectors

- Tin size per room: 5 L tins for the V2 room give ⌈70 ÷ 12 × 1.10 ÷ 5 = 1.28⌉ = 2 tins × 5500p = 11 000p (vs 3 × 2.5 L = 9 000p); trader default and switching back; primer tins; invalid choices rejected.
- Pack rounding: waste is applied before rounding up (4.5 L + 10% = 4.95 L → 2 tins; 5.0 L + 10% → 3 tins).
- Per-quote price overrides: used without markup, flagged; `priceRequired` for high access without a price.
- Half-up at exactly .5 at line level (also exercised by V4, V5, V8, V9, V10) and on tax.
- Markup rounding inside the unit price, e.g. 999p × 1.15 = 1148.85 → 1149p.
- Imperial measurements on a metric price list and the reverse (exact conversion per ADR-001).
- Field validation: limits in §1, coats 1–4, an extra has exactly one quantity source, `count` ≥ 1.
- Trader defaults: a business default of 3 coats applies when the room doesn't override it.
- Property tests: totals are never negative, and a line total is within half a minor unit of the exact product.

## 7. Vector file format

Each vector is stored as `packages/quote_engine/test/vectors/painting/vNN-*.json`, holding its full price list (no reliance on pack defaults), the field values, and the expected lines, subtotal, tax and total. Files are validated against `test/vectors/schema.json`. Expected values change only when an approved spec changes.
