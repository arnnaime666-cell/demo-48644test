# EducateED — Canada-wide expansion: scope, inventory, risks

Status: scoping analysis (not an implementation plan). Requirement: open the platform from Ontario-only to all of Canada.
Prepared: 2026-09-06 · Codebase: educateed/app @ 38e4817 · Author: Egg

> **Scoping baseline:** analysis ran on branch `fix/invoice-province-code-tax-label`, which carries one
> unmerged fix (94c8d07, 2026-09-06): on **main**, Ontario invoices charge 13% HST but label it "GST" (the
> pipeline compares the stored province *name* against the code `'ON'` — never matches), and that commit
> adds `src/lib/provinces.ts` (13-province reference data + normalization), which main does not have yet.
> Statements below that reference provinces.ts / invoice labels are true on the branch; merge 94c8d07
> before relying on them on main.

---

## Executive summary

The engineering footprint is smaller than it looks. The app is already province-flexible in most of its architecture: a full 13-province reference module exists, booking is timezone-aware, `profiles.province` is free text with no constraints, and grade levels/subjects are generic. What pins the service to Ontario is a **short list of gates**: one service-area constant, a tutor-discovery filter, a hardcoded signup default, the tax rate, and marketing copy.

The real size is **not the code**. It is four non-code workstreams:

1. **Tax compliance** — 13% Ontario HST is hardcoded for every province; the tax-exemption question is documented as unresolved; CRA registration is pending.
2. **Quebec** — Bill 96 (French) and Law 25 (privacy) are real obligations if Quebec is served.
3. **Timezone correctness in emails** — session times in emails render in server-UTC, not the session's stored timezone; latent bug that becomes severe cross-province.
4. **Supply & curriculum positioning** — every current tutor is Ontario (signup hardcodes it), discovery is province-locked, and the marketing promise is "Ontario curriculum" (EQAO/OSSLT).

Verdict: **Phase 1 (service-area unlock) is ~1–2 dev days.** The meaningful cost is tax/compliance advice, content positioning, and per-province tutor supply — decisions and professional services, not code.

---

## A. Service-area gates (code that hardcodes Ontario)

| # | Location | What it does | Change |
|---|----------|--------------|--------|
| 1 | `src/types/index.ts:412` | `CANADIAN_PROVINCES = [SERVICE_PROVINCE]` — the "service area" constant. Parent signup dropdown ("Service Province") renders only Ontario. | Replace with all 13 provinces/territories (data already exists in `lib/provinces.ts`). **Trivial.** |
| 2 | `src/app/(auth)/signup/tutor/page.tsx:304` | Tutor signup hardcodes `province: SERVICE_PROVINCE` into auth metadata — **every tutor in the system is Ontario today**. There is no province field on the tutor form. | Add a province select to tutor signup + zod validation + metadata passthrough. **Small.** |
| 3 | `src/components/tutor/tutor-profile-client.tsx` | Tutor profile edit form has **no province field** — tutors can never correct their province post-signup. | Add to profile form + `/api/tutor/profile` upsert. **Small.** |
| 4 | `src/domains/tutors/server/find.ts:28` | Tutor discovery: `.eq('profiles.province', SERVICE_PROVINCE)` — families can only ever see same-province tutors. The filter is a backend hardcode, not a user-facing parameter. | Product decision: province-matched (recommended) vs cross-province. Code change is trivial either way. **Decision-gated.** |
| 5 | `src/app/api/auth/ensure-profile/route.ts:48` | Defaults missing province metadata to Ontario. | Keep as fallback. **None.** |
| 6 | `supabase/migrations/20260620120000_default_province_ontario.sql` | DB trigger: `coalesce(province, 'Ontario')` for new profiles. Comment explains why: profiles without province are invisible in discovery (which filters `province = 'Ontario'`). | Keep; it only fires when metadata is missing. **None.** |
| 7 | `src/app/api/auth/e2e-signup/route.ts:47,62` | Test-only signup helper defaults Ontario. | Update when touched. **Trivial.** |
| 8 | Admin UI | No province display or filter anywhere in admin screens. | Optional: surface province in the admin tutor list for ops visibility. **Optional.** |

Data model notes: `profiles.province` is free TEXT (no CHECK constraint — migration 20260427000000), the auth trigger `handle_new_user` copies `raw_user_meta_data->>'province'`, and the tutors table has no province column (province rides the profiles join). No RLS policy keys on province. All of this is expansion-friendly.

## B. Tax & money — the highest-risk area

1. **13% HST hardcoded in two places**: `src/domains/payments/server/subscriptions.ts:189` (`HST_RATE = 0.13`, with a comment already saying "In production, this should use the parent's province") and `src/app/api/payments/invoice/route.ts:106` (`gstHstRate: 0.13`).
2. **Pricing is tax-inclusive** — the invoice renders "Total: $X (incl. HST 13%)", so customers pay the same price today regardless. The exposure is the *accounting split*: how much of each payment is remittable sales tax differs per province, and the code assumes 13% for all of Canada.
3. **PST/QST are not modelled** (provinces.ts states this explicitly). BC, SK, MB (RST), QC (QST ~9.975%) have separate provincial sales taxes; the invoice only labels HST vs GST.
4. **Open tax question, already documented** in `src/lib/provinces.ts` + `TOKEN_PACKAGE_OPEN_DECISIONS`: whether curriculum-aligned private tutoring is exempt under Schedule V, Part III of the Excise Tax Act is unresolved and pending professional advice. Provincial exemptions differ.
5. **CRA registration pending** — the invoice template renders "Registration No: [pending — to be added upon CRA registration]".
6. **Token packages are a draft** (flagged off, not purchasable) — their gift-card rules and GST/HST-at-purchase-vs-redemption decisions are future work, not current risk.
7. **Current production mislabel (on main):** every Ontario invoice charges 13% HST but labels it "GST" — PDF line item, PDF footer, and confirmation email all fall through to the GST branch because the pipeline compares the stored province *name* ('Ontario') against the code 'ON'. Fixed on branch `fix/invoice-province-code-tax-label` (94c8d07, unmerged) via `toProvinceCode()` normalization + a typed `ProvinceCode`. Rates stay hardcoded 0.13 either way; already-issued invoices may need a compliance review/reissue decision.
8. `salesTaxLabel()` labels HST (ON, NB, NL, NS, PE) vs GST correctly per province **once 94c8d07 merges** — the label logic is ready, the rates are not.

## C. Content & curriculum

1. `ONTARIO_CURRICULUM_TAGS` (types:417–432): 12 tags — Ontario Curriculum, EQAO Grade 3/6/9, OSSLT, IB Support, AP Support, French Immersion, Core French, STEM Enrichment, Homework Support, Test Preparation. Tutors pick these on their profile (stored as free-text strings, **not** enum-validated) and they render on tutor cards + profiles. Tutor form helper text says "Add Ontario curriculum tags to improve discovery."
2. FAQ (`src/app/faq/page.tsx`): "The platform is designed around Ontario curriculum expectations for Ontario families who want Canadian-aligned tutoring." (also two Canada-flavoured answers that need no change).
3. Landing page (`src/app/page.tsx`): "Curriculum aware — Learning support aligned with Ontario curriculum from JK through Grade 12." + "Ontario curriculum" feature chip + metadata description. (The hero line already says "Canadian curriculum · JK–Grade 12".)
4. Grade levels (`Kindergarten`, `Grade 1`–`Grade 12`) and subjects (14 generic subjects) are **not** Ontario-specific — no change needed.

## D. Timezone — the sleeping giant

Already built (better than expected):
- Booking captures the client's IANA timezone (`book-session-client.tsx:203`), converts wall-clock to a correct instant (`checkout.ts:126 parseWallClockInTimeZone`), and **persists `timezone` on every session** (checkout.ts:245, "Bug #17"). This is the hardest part of multi-province scheduling and it is already built.
- In-app time displays render client-side in the viewer's browser timezone (booking calendar, notifications, admin pages) — correct by construction.
- Stripe Connect payouts, video rooms (Daily.co), and crons are timezone-agnostic/UTC — fine.

Still wrong:
- **Session emails render times in server-UTC.** `src/lib/resend.ts` booking-confirmation and reminder emails call `toLocaleString('en-CA', ...)` with no `timeZone` option → Vercel's server timezone (UTC). A 3:00 PM ET session stored at 19:00Z likely renders as "7:00 PM GMT" in emails — possibly already wrong for Ontario users today, and unusable for cross-province. Emails must render in the session's stored timezone. (~half day + QA.)

## E. What needs no change (already Canada-ready)

GRADE_LEVELS, SUBJECTS, LANGUAGES (English/French already), commission tiers, Stripe CAD payment infrastructure, booking timezone capture/persistence, auth/OTP/admin-review/quality systems, PIPEDA baseline privacy handling, payouts (Stripe Connect, national), video rooms, crons. Admin UI has no province logic (and could optionally display it). (`lib/provinces.ts` full reference data ships with the unmerged 94c8d07 — move back into this list once merged.)

## F. Risks, ranked

1. **Tax (HIGH).** Charging/labelling 13% Ontario HST for every province is wrong for most of Canada; PST/QST unmodelled; Schedule V tutoring-exemption question open; CRA registration pending. Shipping nationwide before resolving this creates genuine compliance exposure. Needs an accountant/Stripe Tax decision — not code.
2. **Quebec (HIGH if included).** Bill 96 French-language obligations for consumer-facing sites/contracts; Law 25 privacy regime. Cleanest v1: exclude QC and territories, or ship English-only outside QC with QC deferred pending legal.
3. **Email timezone rendering (MEDIUM).** Latent today, severe cross-province. Fix: render session emails in the stored session timezone.
4. **Supply liquidity (MEDIUM, GTM).** Every tutor is Ontario (signup hardcodes it) and discovery is province-matched — a BC family sees an empty marketplace until BC tutors onboard. Expansion without a per-province tutor plan ships empty shelves. Either sequence supply before demand or relax province matching with timezone disclosure.
5. **Tutor credential verification (MEDIUM).** Teaching certificates are provincial (Ontario College of Teachers vs BC TRB vs Quebec). Admin verification guidance needs provincial awareness; document set may need per-province nuance. Background checks are national — fine.
6. **Curriculum positioning (MEDIUM, decision).** "Ontario curriculum" is a core marketing claim and EQAO/OSSLT are Ontario-only assessments. Genericize copy (fast) vs per-province curriculum support (bigger product).
7. **Terms/governing law (LOW-MEDIUM).** T&C version 2026-04-01 is likely Ontario-framed; needs legal review + version bump.
8. **Insurance (UNKNOWN).** Verify platform insurance isn't Ontario-scoped.
9. **Vercel↔GitHub deploy hook (OPERATIONAL, already known).** Broke during the org-permission incident — pushes to main no longer auto-deploy until the GitHub app is re-authorized. Deploys currently need the CLI.

## G. Suggested phasing

- **Phase 1 — service-area unlock (≈1–2 dev days + QA):** extend `CANADIAN_PROVINCES`; add province to tutor signup + profile; decide discovery policy and implement; copy updates (FAQ, landing, metadata); keep DB trigger default.
- **Phase 2 — tax (advice-gated):** resolve Schedule V exemption + marketplace rules + CRA with an accountant; then province rate table or Stripe Tax; invoice route picks rate by parent's province. ≈1–2 dev days after advice.
- **Phase 3 — timezone-correct emails:** render session emails using the stored session timezone. ≈half dev day.
- **Phase 4 — curriculum:** genericize copy immediately (trivial); per-province tag sets only if the product wants them (≈1–3 days).
- **Phase 5 — Quebec/French:** separate project (translation + Law 25/Bill 96 review).
- **Ops (non-code):** provincial tutor recruitment (supply is the constraint), per-province SEO pages, support coverage.

## H. Decisions needed from founders/product

1. Cross-province tutor matching — allowed, or province-strict discovery? (Timezone reality favours province-strict, or cross-province with explicit timezone disclosure.)
2. Quebec in v1? (Recommendation: not in v1.)
3. Tax path: Stripe Tax vs manual rate table; CRA registration status; Schedule V exemption advice.
4. Curriculum strategy: genericize copy vs per-province tag sets.
5. Tutor supply plan per province (recruiting, incentives).

## I. Verification items (found during scoping, not fully verified)

1. Booking-confirmation email time rendering against a live email (code path suggests UTC rendering; confirm whether Ontario users already see wrong times).
2. Whether the curriculum-tag picker in the tutor profile restricts choices to `ONTARIO_CURRICULUM_TAGS` in the UI or is free-text (schema is free-text `z.array(z.string())`; helper copy says "Add Ontario curriculum tags").
3. Whether any insurance/coverage docs are Ontario-scoped.
4. Whether the Vercel project's GitHub app authorization survived the org demotion (deploy hook is currently broken — related, but distinct from the app code).