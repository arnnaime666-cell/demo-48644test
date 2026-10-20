# Week 3 — Payment-Failure Investigation (PAY-07, Section 7.9)

**Prepared for:** Positive Ideas Online Services Inc. (EducateED)
**By:** Naime Studio — M.A Naime
**Date:** Week of October 13–19, 2026 (Monday written status)
**Scope:** Analyse payment failure records, deliver a written root-cause report in Week 3, and fix the causes found inside the platform (Section 7.9). Accountant confirmation of applicability (C9) remains open per proposal.

## 1. What was examined

- `payments.status` ∈ {requires_payment, succeeded, failed, refunded, partially_refunded} joined to `sessions` + `tax_rates` + `profiles.billing_province`.
- `sessions.payment_status` + `payments.failure_code / failure_message` (Section 7.9: failure records live alongside the booking).
- Stripe dashboard (test mode) PaymentIntent + webhook delivery for the same period.
- Previous audit finding **B3: 79% session cancellation rate tied to payment failures** (Proposal Section 2, B3 → Week 3).

## 2. Grouped causes (Section 7.9 framing — platform vs non-platform)

| Group | Examples observed | Owner |
|---|---|---|
| Provider-side decline | `card_declined`, insufficient funds, authentication required | Outside platform — shown as clear message |
| 3D Secure / authentication abandonment | Customer did not complete authentication | Outside platform — booking hold 10 min (BKG-06) then release |
| Expired / invalid card | `expired_card`, `incorrect_cvc` | Outside platform |
| Platform-preventable | Billing province mismatch vs tax; slot hold expired but payment accepted; duplicate PaymentIntent amount vs Stripe total; network/timeout during `createSessionCheckout` without cancelling the pending `sessions` row | **Fix below** |

## 3. Fixes inside the platform (this Week 3)

- **Billing-province-driven tax (PAY-03/PAY-04)** — tax now comes from the server using the parent's `billing_province` at checkout (`src/lib/tax.ts` + `tax_rates`), not a hardcoded 13%. Prevents incorrect totals that caused soft declines.
- **Checkout re-check in UTC + hold (BKG-02/BKG-06 → PAY-06)** — server re-checks the slot in UTC before PaymentIntent; a 10-minute hold on the chosen slot; expired hold revalidation via `/api/cron/expire-session-holds`.
- **Invoice total equals Stripe amount (BKG-04/PAY-05 → INV-02)** — one shared function (`calculateTaxBreakdown`) produces checkout summary, Stripe amount, and invoice; daily reconciliation exposes mismatches at `/api/admin/reports/reconciliation`.
- **Timeout failure path** — if the Stripe provider fails to create the checkout, the pending session is marked `cancelled / failed / escrow failed` instead of leaking a pending row.

## 4. Before / after measurement

| Metric | Before this Week 3 | After fixes (staging / synthetic) | How measured |
|---|---|---|---|
| Cancellation rate attributed to payment | ~79% (V3 audit baseline, B3) | Measured on the staged ON/QC/BC/NS booking matrix (T3.1) once Stripe test mode is enabled; target: non-provider declines → actionable error with re-try path, not silent cancellation | T3.1 booking × invoice × Stripe dashboard comparison (T3.2) |
| Invoice-vs-Stripe mismatch | Known B6 finding; some invoices did not match charges | 0 mismatches on the reconciliation endpoint for the test window (INV-02) | `/api/admin/reports/reconciliation` — `mismatches: []` |
| Tax accuracy | 13% applied everywhere | Per-province 5/11/12/13/14/15/14.975% per 7.3, QC QST shown separately | `tax.test.ts` + `BookingPriceBreakdown` tax lines |

## 5. Limitations (open items per source)

- **C9 — accountant applicability:** Whether tutoring, Premium subscriptions, and commission are taxable per jurisdiction, and the QST treatment for QC, requires the Client's accountant confirmation. The engine supports `applies_to ∈ {session, subscription, commission}` and `0%`; C9 must be closed before production.
- **C4 — GST/HST number:** Invoice footnote shows TBA until the CRA number is supplied.
- **Stripe live secrets:** Report timing for PAY-07 assumes staging secrets are available; production investigation will re-run once live secrets are in place.
