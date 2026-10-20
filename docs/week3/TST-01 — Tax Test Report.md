# Week 3 — Tax Test Report (TST-01/PAY-01..04, Section 7.3)

**Scope:** Automated tests for the tax engine covering all 13 jurisdictions, every component, rounding edge cases, and effective-date changes (TST-01). Source: `src/lib/__tests__/tax.test.ts` + `src/lib/tax.ts` + migration `20261013000000_week3_tax_rates.sql`.

## What is tested

- **All 13 jurisdictions** — AB/BC/MB/NB/NL/NS/NT/NU/ON/PE/QC/SK/YT against Section 7.3 (AB 5%, BC 12% GST+PST 5+7, MB 12%, NB/NL/PE 15% HST, NS 14%, NT/NU/YT 5%, ON 13%, QC 14.975% GST 5 + QST 9.975%, SK 11% GST+PST 5+6).
- **Every component** — GST, HST, PST, QST as stored in `tax_rates` (`applies_to ∈ {session, subscription, commission}`; engine currently wired for `session` with subscription support in data).
- **Rounding** — Half-up per component: `Math.round(subtotal_cents * rate)` in whole cents; sum = total. Includes QC QST edge (9.975%) and minimal subtotals (1¢).
- **Effective dates** — `getApplicableRates` filters by `effective_from / effective_to` (proposal Rule 5); historical invoices are never rewritten.

## How to run

```bash
npm test -- src/lib/__tests__/tax.test.ts
# or: npx vitest run src/lib/__tests__/tax.test.ts
```

## Open item

- **C9 (applicability):** Whether tutoring, Premium subscriptions, and commission are taxable per jurisdiction, and the exact QST treatment, requires the Client's accountant confirmation. The engine supports `0%` per jurisdiction per `applies_to`; closing C9 before production changes no code.
