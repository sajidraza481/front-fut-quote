# ADR-001: Pure Dart quote engine with integer money and geometry

- **Status:** Accepted
- **Date:** 2026-10-27
- **Context:** BRIEF §4 principle 3, §7

## Context

Quotes become legally binding contracts and invoices. The same inputs must always produce the same totals on every device, in tests, and (later) when the server re-checks them. The original `quotepainter` scaffold is lost, so the engine is rebuilt from scratch.

## Decision

1. `packages/quote_engine` is a plain Dart package: no Flutter, no I/O, no clock, no randomness. Callers pass everything in.
2. **Money** is `int` minor units (pence/cents) end to end. Formatting happens only at the UI edge.
3. **Geometry** is integer too. Lengths are stored as tenths of a millimetre, so metric (1 mm = 10) and imperial feet, inches and half-inches (1 in = 254, 1 ft = 3048) convert exactly; finer inch fractions round to the nearest 0.1 mm (≤ 0.05 mm error). Areas are exact integers; conversion to m² (÷ 10⁸) or ft² (÷ 9 290 304) happens once, rounded half-up to 0.01 of the price list's unit.
4. **Rounding** is half-up, applied at line level: `lineTotal = roundHalfUp(qty × unitPrice)`. Tax is computed once on the subtotal, also half-up. Rates (tax, markup) are integer basis points.
5. `TradePack` follows BRIEF §7 with these differences: `defaultCatalog(UnitSystem)` instead of one catalog (metric and imperial price lists); `extraQuantityIds`, `suggestedExtraSources` and `validatePriceList` added for trader extras; `PdfTemplateSpec` deferred to on-device PDFs in Phase 1. Extras, trader defaults, markup and per-quote extra price overrides are handled once in `QuoteEngine`, not in each pack. Pack size and waste are data on `CatalogItem`; the pack decides how they are applied (painting: whole packs after waste, no intermediate rounding). Invalid input returns `Invalid` with error codes; the engine does not throw.
6. Trade-specific rules (coats, openings, primer, paint-coverage rounding, later flooring waste and box rounding) live in the TradePack, not the engine.

## Consequences

- No floating-point drift; golden vectors are exact.
- Values stay well inside 2⁵³, so a TypeScript mirror (portal / Edge Functions) can use `number` safely for any realistic room.
- If the flooring pack (Phase 5) needs engine changes, they get a new ADR.
