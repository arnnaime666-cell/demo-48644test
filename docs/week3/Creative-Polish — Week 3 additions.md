# Week 3 — Profit: Creative Polish (non-invasive, source-aligned)

This week added a safe creative layer with **no** new business rules, pricing, curriculum, tax, qualification, guarantee, statistic, or fixed tutor-campaign budget invented. All copy, pricing (Basic Free / Premium $29.99), recurring-booking discount messaging, 10% where demonstrated, and 13-province scope are unchanged and remain the source of truth.

## What was added (on top of the required Week 3)

- **Home hero:** Badge now reads “Canadian curriculum · JK–Grade 12 · Pan-Canadian curricula”; hero sub stays province-aware (“matched to the student, the subject, and the province”); highlights read “Pan-Canadian curricula”.
- **Feature cards:** “Thoughtfully vetted — only approved tutors appear in family search” + “Curriculum aware — matched to your child’s province” state the approval gate without inventing a requirement.
- **Find a Tutor header:** Now explicitly notes “only approved tutors appear · filter by province, subject, grade, language; sort by match.”
- **Marketplace storyboard:** The `TwoSidedMarketingHub` funnel and the admin Analytics split make the two growth engines equally legible — no budget or guarantee invented.
- **Checkout clarity:** `BookingPriceBreakdown` can show tax lines (Subtotal → per-component tax → Total incl. tax with province) so BKG-04/PAY-05 is demonstrable in the demo even before live Stripe.
- **Consent UX:** A single `ConsentBanner` (essential-only vs analytics) — dismisses with a choice, dispatches an `educateed:consent` event, and gates `trackEvent` (no PII).

## Why this is safe

- Every phrase above is already supported by the three source documents or by the built Week 3 tax/search/invoice/admin state. Nothing here creates a new requirement the tracker would need to pass.
- Responsive behavior and existing flows (parent/tutor signup, children, tutor review, booking, session, analytics) are untouched apart from additive props/optional rendering.
