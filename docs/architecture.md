# EducateED Platform Architecture

This repository remains a single deployable Next.js app, but it is now structured around the core product flows instead of only route folders. The goal is to keep the current app working while making the repo ready to live as the org-owned `platform` repository.

## Principles

- Keep one deployable app until there is real pressure to split services.
- Organize server logic by domain flow: `admin`, `tutors`, `family`, `payments`, `sessions`.
- Leave route URLs stable where possible and add transition aliases instead of breaking changes.
- Centralize runtime configuration and keep third-party integrations shared.

## Current Repo Shape

```text
src/
  app/
    (auth)/                     # Login and signup routes
    (dashboard)/                # User dashboards and protected UI
      admin/
      tutor/
      student/                  # Existing student URLs still work
      family/                   # Parent-student alias routes for backlog alignment
    api/
      admin/
      stripe/
      sessions/
      daily/
      auth/
  components/
    admin/
    layout/
    sessions/
    tutors/
    ui/
  domains/
    admin/server/              # Tutor approval workflow
    family/server/             # Parent-student dashboard queries
    payments/server/           # Checkout and Stripe webhook handling
    sessions/server/           # Session completion and payout attempts
    tutors/server/             # Tutor Stripe Connect onboarding
  lib/
    supabase/
    stripe.ts
    daily.ts
    resend.ts
    utils.ts
  platform/
    config/runtime.ts          # Shared env/runtime settings
  types/
```

## Flow Mapping

- `admin`: tutor queue review, approval, rejection, audit log creation
- `tutors`: onboarding, profile, availability, earnings, Stripe Connect state
- `family`: current parent-student booking surface; `/family/*` redirects to existing `/student/*` pages for now
- `payments`: checkout creation, Stripe webhook orchestration, payout schedule metadata
- `sessions`: room/session lifecycle and tutor payout execution

## Why This Increment

The current sprint does not justify a monorepo split, separate backend service, or package extraction. The practical next step is a domain-oriented app folder inside one Next.js deployment:

- lower risk than moving route trees or splitting repos
- easier handoff to an org-owned `platform` repo
- clearer seams for future extraction if the team later adds workers, cron jobs, or separate admin tooling

## Next Recommended Increments

1. Move the remaining server-heavy tutor and family queries into `src/domains/*/server`.
2. Replace the immediate payout in session completion with an actual delayed job runner.
3. Keep Supabase migrations as the database source of truth; regenerate or retire `supabase/schema.sql` before using it for onboarding.
4. If a second deployable surface is needed later, split from these domain seams rather than by UI folder.
