# PAY-003 Token/credit packages — open decisions (scaffold only)

Status: **NOT implemented.** The Sprint 3/4 founder report deliberately
deferred token packages until refund, expiry, and tax accounting rules are
locked in. The code that exists today is a clearly-marked scaffold behind the
`TOKEN_PACKAGES_ENABLED` env flag (default off):

- `src/domains/payments/server/token-packages.ts` — draft catalog + status
- `GET /api/payments/token-packages` — draft catalog (auth + flag required)
- `POST /api/payments/token-packages` — always `501 Not Implemented`

No database schema was added on purpose: committing tables now would encode
the unresolved policy decisions below.

## Decisions required before implementation

1. **Refunds of partially used packages.** Pro-rata refund at the package
   rate, refund at the higher per-session rate for used sessions, or no
   refund? Interaction with the existing dispute/refund flow and the
   append-only financial ledger.
2. **Expiry.** Proposed 180/365-day expiries may be unenforceable: prepaid
   credits can fall under Canadian/Ontario gift-card regulations that
   prohibit expiry. Needs legal review before any expiry logic ships.
3. **GST/HST timing.** Tax on the package sale vs. on each session
   redemption changes invoice generation (PAY-002) and remittance. Requires
   professional accounting sign-off (same blocker recorded in
   docs/actual-sprint-3-4-5-audit-2026-06-19.md).
4. **Ledger model.** New `financial_transactions` event types are needed
   (token_purchase, token_redemption, token_expiry, token_refund) with
   idempotency keys, hash chaining, and reconciliation against Stripe.
5. **Pricing mismatch.** Tutor hourly rates vary; define whether a token is
   worth a fixed dollar amount, a session with a rate cap, or tutor-specific.
6. **Scope of ownership.** Account-wide vs. per-child balances, and whether
   tokens are transferable.

## Suggested next steps

1. Product + legal decide items 1–3 (legal: expiry; accounting: HST timing).
2. Design the token ledger as an append-only table mirroring
   `financial_transactions` controls (see migration
   `20260619000000_actual_sprint5_controls.sql`).
3. Only then add purchase (Stripe Checkout), redemption (booking flow), and
   admin reporting.
