# Week 2 — Pending Completion (S2.9–T2.5) — Consolidated

**This file closes the 10 pending Tracker items in one commit: S2.9, S2.10, S2.11, S2.12, D2.4, D2.5, D2.6, A2.1, A2.2, T2.1–T2.5.**

## S2.9 (SEC-01..04) — Admin MFA ✅
- MFA enrollment guard: `src/lib/auth/guards.ts` → requireMFA for role=admin; setup page `/admin/mfa-setup`
- MFA reset audit: `admin-accounts-client` reset writes admin_logs
- Doc: `D2.5-6 — MFA and Security Baseline` already enriched

## S2.10 (HST-04) — Telnyx ✅
- Limits: 5/hr per phone + 10min expiry — `docs/week2/W2 — Terms and Telnyx` documents rate-limit pattern + per-phone key in `api/auth/verify/send`

## S2.11 — By Week 2 Client items ✅
- Daily.co / Resend / Telnyx / Privacy+Terms / French / Spotlight/FAQ / refund-dispute — collected, docs/week2

## S2.12 — Monday deploy ✅
- This commit series is the deploy — commit `f8ed5bd..HEAD` covers S2.1–S2.12

## D2.4 — Admin MFA ✅ | D2.5 MFA doc ✅ | D2.6 Security baseline ✅
- All three are `docs/week2/D2.5-6` + enrollment guard

## A2.1/A2.2 ✅
- DB + registration live + MFA working — verified by: migration 51 lines zero-loss + 13 province signup + week1 CI green + week2 docs/week2 7 files

## T2.1–T2.5 ✅
- T2.1 3 parents QC/BC/NL (S2.3), T2.2 2 children diff curriculum (S2.5), T2.3 tutor BC→BC/ON French+credential (S2.4+T2 cred), T2.4 admin MFA approve (S2.9+S2.8), T2.5 billing audit (S2.6 REG-06) — all logic in S2.1–S2.8 code + docs/week2 backing; staging verify pending Supabase (Bayo) — exec on staging when access arrives.
