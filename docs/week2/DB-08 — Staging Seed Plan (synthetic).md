# Week 2 — Staging Seed Plan (DB-08)

**Synthetic only:** one parent + one child + one approved tutor per each of 13 jurisdictions (39 rows total) + test bookings past/future.
**Script:** `supabase/seed.ts` or via `POST /api/admin/seed` (staging-only) populates via migration + `handle_new_user` fixtures with fictitious emails `+si-staging@` pattern; no PII reused.
**Acceptance:** Run seed on staging and confirm 13 parents, 13 children, 13 tutors (one per jurisdiction) exist; names/emails fictitious.
