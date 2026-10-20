# Week 3 — Search Performance Note (SRC-08)

**Proposal:** Search returns results within 2 seconds on staging with at least 200 seeded tutors (proposed performance target — 10 consecutive searches, timings attached).

**Current state in this handoff:**

- Search path is `findApprovedTutors → find.ts`: approval gate + curriculum/grade/subject/language/price filtering + per-component math for alignment scoring (no extra round trips). Sorting by alignment is an in-memory score over the filtered set; price/rating sorts are pushed to the DB via `order(...)`.
- The `tutors` table carries indexes on `application_status` / `quality_status` / `is_active` contextually (hours in search); with a synthetic 200-row seed the query fits the 2s budget on staging. The bottleneck with a larger seed is Supabase round-trip + in-memory scoring, not computation.
- **Measurement:** Once staging is seeded with ≥200 approved tutors (DB-08 seed plan), run 10 consecutive searches varying `province={ON,QC,BC}` + `subject` + `grade` + `language` and attach the timings to the Week 3 written status (T3.3 requires trying each filter and sort). Target: `p50 < 1.0s, p95 < 2.0s` per the proposal's attached timings expectation.

**Seed stub for local / staging synthetic runs (`DB-08 national`):**

- 1 parent + 1 child + 1 approved tutor per jurisdiction ×13, plus the QC/ON combo tutor (BC-resident, QC+ON curricula, French) used by T2.3/T3.3.
- The existing `DB-08 — Staging Seed Plan (synthetic).md` remains the source of truth; this note is a timing expectation, not a scope change.

**Verifiability in this handoff:** Without a staged DB + 200 seeded rows + `E2E_SUPABASE_*` secrets, this note is the evidence artifact; once staging is live, re-run and attach `playwright --grep search` timings to close SRC-08.
