# EducateED — Canadian K-12 Tutoring (Demo)

EducateED is a Canadian JK–Grade 12 one-to-one online tutoring marketplace built as a **single Next.js application** with domain-oriented server modules for the core marketplace flows: parent/family, tutor, payments, sessions, and admin. This repository is a **standalone EducateED Canada demo** prepared for client review — all 13 provinces and territories, bilingual (EN/FR), and marketplace-complete.

> **Scope notice — source of truth:** Business rules, pricing, curriculum, schedules, and tax treatment shown here follow the three EducateED source documents. EducateED has **two equal growth engines**: *Parent / Student acquisition* and *Tutor acquisition / recruitment* — visible as the “Two-Sided Marketing” hub at `/admin`. Only **approved** tutors appear in family-facing tutor search.

## Highlights

- **Pan-Canadian** — 13 provinces and territories; province-aware curriculum, matching, and tax.
- **Bilingual** — EN/FR throughout; QC defaults to French; no PII in analytics.
- **Marketplace-correct** — Tutor applies → Pending review → Approved → Discoverable to families (pending/flagged/rejected tutors never appear in family search).
- **Two-Sided Marketing** — Parent/Student demand and Tutor supply as equal panels, clickable journeys, distinct channels and UTM/audience tracking, connected at “Available Approved Tutors.”
- **Checkout-accurate** — Server-side tax (Section 7.3) with per-component rounding; Stripe amount equals the total; invoices match.

## Stack

- Next.js 16, React 19, Tailwind CSS 4 + shadcn/ui
- Supabase (Auth, Postgres with RLS, Storage)
- Stripe (session checkout, Connect Express, payouts, refunds)
- Daily.co (live sessions), Resend (email), Telnyx (SMS)

## Pricing shown

- **Basic — Free** · **Premium — CAD $29.99/month** · Recurring monthly tutoring (when applicable) shows an **automatic 10% discount** experience. $1 from each Premium subscription supports school libraries in Nigeria through the AVID Foundation. Policy-leave items (Premium inclusions at renewal, AVID renewal pass-through, recurring eligibility) remain open per source.

## App structure

```text
src/
  app/
    (auth)/         # login, signup/parent, signup/tutor, MFA
    (dashboard)/    # admin, family, student (family aliases), tutor
    find-a-tutor/   # parent-focused landing
    become-a-tutor/ # tutor recruitment landing — distinct from contact pages
    privacy/        # consent & PIPEDA overview
    terms/
    api/            # checkout, payments, tutor, admin, etc.
  domains/
    admin/ family/ payments/ sessions/ tutors/
  lib/              # provinces, tax, pricing, analytics, consent
  platform/         # runtime config
  types/
```

## Environment variables

```bash
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PREMIUM_PRICE_ID=
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=
DAILY_API_KEY=
RESEND_API_KEY=
SMS_PROVIDER=telnyx
TELNYX_API_KEY=
TELNYX_PHONE_NUMBER=
TELNYX_MESSAGING_PROFILE_ID=
NEXT_PUBLIC_APP_URL=https://educateed.ca
PLATFORM_FEE_PERCENT=10
PAYOUT_DELAY_HOURS=48
CRON_SECRET=
SENIOR_ADMIN_EMAILS=
# Optional analytics beacon (no PII): anonymous UTM + audience + province/language only
NEXT_PUBLIC_ANALYTICS_ENDPOINT=
```

For local phone-code testing without sending real SMS, use `SMS_PROVIDER=console`.

## Local development

```bash
npm install
npm run dev
```

## Database

Supabase migrations in `supabase/migrations/` are the source of truth (apply in timestamp order with the Supabase CLI or dashboard SQL editor). Documented snapshot in `supabase/schema.sql` is historical only — do not bootstrap from it.

- **Week 3 adds:** `public.tax_rates` (Section 7.3 reference rates as data) plus session tax snapshot columns `tax_province / tax_total_cents / total_cents`. No hardcoded 13% remains in pricing paths.

## Marketing & analytics (demo)

- **Two-Sided Marketing** at `/admin` — equal-weight Parent/Student and Tutor panels; each shows audience, purpose, channels, CTA, journey, UTM/audience tracking, and landing destinations (`/find-a-tutor` and `/become-a-tutor`).
- **Channels (source-aligned):** Parent — Facebook, Instagram, Google Search, TikTok, organic; Tutor — LinkedIn (primary), Facebook/Instagram where appropriate, TikTok, organic recruitment content. No fixed tutor-campaign budget is invented; the demo shows “Budget allocation: To be confirmed” for the tutor side and keeps the confirmed **CAD $500** allocation unchanged.
- **Tracking:** `utm_source` / `utm_medium` / `utm_campaign` / `utm_content` + `Audience Type = Parent/Student OR Tutor`, province, language, event, timestamp — no PII. Respects the in-app consent banner (essential-only vs analytics).
- **Admin reporting:** `/admin/analytics` splits Parent/Student vs Tutor metrics and shows marketplace health (parent demand ↔ available approved supply).

## Campaigns, content & tax notes

- Tutors are discovered only when **approved + active + not suspended/banned** (family search, profile, availability, favorites, booking).
- Search is **national, curriculum-driven** (SRC-01..08): removed Ontario-only default, province/curriculum filter (child’s curriculum province by default), subject / grade / language / availability / rate filters (AND), result count + empty-state messaging, per-card **alignment score (40/25/25/10)** with hover breakdown, sorting by alignment (default when filtered), rating, or price, and a **Tax Rates** + province-aware financial reporting surface in admin.
- Tax is calculated **server-side** using the billing province and shown **before payment** (BKG-04, PAY-05); the rate table is data in `tax_rates` (Rule 1–6 in code: per-component rounding, shared function for checkout/Stripe/invoice, historical invoices immutable, refunds proportional).
- Tax reference rates are **starting values only** — accountant confirmation (C9) is required before go-live; tutoring may be exempt under Schedule V, Part III of the Excise Tax Act. The engine supports `applies_to` scoping (session/subscription/commission) and `0%`.
- **Privacy:** Consent banner on first visit; privacy-safe analytics (no email/name/phone); children’s data via parent-managed learner profiles; PIPEDA deletion-queue at `/admin/privacy`.

## Testing & acceptance

- `src/lib/__tests__/tax.test.ts` — PAY-01..04 / TST-01: rates, per-component rounding, QC QST, invoice-equals-charge identity, refund proportionality.
- `src/domains/tutors/server/find.ts` — `calculateAlignmentScore` and approved-only discovery.
- Tutor approval: a pending tutor does not appear in `/family/find` or `/family/tutors/[id]`; after admin approval the tutor is discoverable and bookable.

## Notes

- Existing `/student/*` routes remain active; new `/family/*` aliases cover the parent-student backlog flow without breaking links.
- Payout delay is metadata-driven in-app; production should move delayed transfers to a job runner.
- Authentication, role-based access (including `/admin` MFA), accessibility, and responsive behavior are governed by `docs/business-rules.md`.
