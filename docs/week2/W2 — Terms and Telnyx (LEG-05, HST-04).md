# Week 2 — Terms Versioning + Telnyx Limits (LEG-05, HST-04)

## LEG-05: Terms versioning
- `CURRENT_TERMS_VERSION = '2026-04-01'` (types), `profiles.terms_version` + `terms_accepted_at` stored.
- Week 2: add `terms_version` + `accepted_at` audit to `ensure-profile` flow; when version bumps, next login triggers TermsAcceptanceCard re-accept.
- DB: `profiles` already has columns; migration keeps them.

## HST-04 (Telnyx): SMS/OTP through Telnyx
- Limits: **5 codes per phone per hour**, expiry **10 minutes** (proposed).
- Current: `OTP_EXPIRY_MINUTES = 10`, `OTP_MAX_ATTEMPTS = 3`, cooldown via `rate-limit.ts` (3/60s baseline, extend to 5/hr per phone for Telnyx).
- Implementation: in `api/auth/verify/send` add per-phone hourly counter keyed by phone E.164.
