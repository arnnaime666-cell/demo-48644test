# BR Deferred Rationale

This document records why the remaining deferred BRs are not claimed as met in the current codebase, and what would be required to close each item defensibly.

## PAY-003 BR-4 — Escrow Segregated From Operating Funds

**Rationale:** The platform records `escrow_status = 'held'` and delays tutor payout until completion/dispute checks pass, and Stripe Connect keeps payment processing outside EducateED application servers. That is not the same as a legal escrow arrangement or proof that funds are segregated from operating funds in a counsel-approved trust/escrow structure.

**Founder sign-off update (2026-07-09):** Use "payment held until session completion" in demo/user-facing language instead of formal escrow wording until legal/payment-provider review is complete.

**Required to close:** legal/accounting sign-off on the escrow model, documented fund-flow architecture, Stripe account/balance configuration review, operating account separation evidence, and updated terms that accurately describe the arrangement.

## PAR-011 BR-4 — Reminder Delivery Via Email And Push

**Rationale:** Email and in-app reminder paths exist, but push delivery is not implemented. Web Push can be implemented in this Next.js app, but the current repo has no root service worker, web app manifest, VAPID keys, push subscription persistence, push send worker, opt-in/opt-out UI, or delivery telemetry. Claiming push compliance without those pieces would overstate the system.

**Founder sign-off update (2026-07-09):** Email + in-app notifications are enough for Sprint 5. Real mobile push is deferred until the mobile app.

**Required to close:** add a PWA manifest and `public/sw.js`, generate and configure VAPID keys, add a `push_subscriptions` table keyed to profiles/devices, add consent and channel preference UI, send push payloads from booking/reminder notification code, record push attempted/sent/failed states, and test Chrome/Edge/Firefox plus Safari/iOS installed-web-app behavior.

## TUT-012 BR-1/BR-4 — Tutor Booking Notifications Within 30 Seconds Across Push, Email, And In-App

**Rationale:** The booking path creates in-app notifications synchronously and attempts email immediately, so the 30-second path is defensible for those two channels. It is not defensible for all three channels because push subscription storage, permission state, provider/Web Push sender, channel preference controls, and delivery attempt telemetry do not exist.

**Founder sign-off update (2026-07-09):** Email + in-app notifications are enough for Sprint 5. Real mobile push is deferred until the mobile app.

**Required to close:** implement the same Web Push foundation described for PAR-011, add tutor channel preferences with default behavior matching the BR, fan out booking notifications to all enabled channels in the booking transaction path, and record per-channel attempt timestamps so the 30-second SLA can be audited.

## TUT-013 Revised No-Response Flow

**Rationale:** The current app implements the original configurable response-window rule: pending tutor responses auto-expire after `TUTOR_RESPONSE_WINDOW_HOURS` (default 24 hours from booking creation). Founder sign-off on 2026-07-09 approved a more precise pre-session flow: remind the tutor 20h and 16h before the scheduled session, auto-cancel/refund 12h before the scheduled session if still pending, and recommend replacement tutors available in the same booked timeline.

**Required to close:** add pre-session pending-response reminder windows, idempotent reminder notifications/emails to tutors, 12h-before-session cancellation/refund criteria, replacement tutor matching by subject/grade/time availability, parent replacement-selection UI, and tests for sessions booked less than 20h before start.

## PAY-011 BR-4 — PIPEDA/CRA Retention Compliance

**Rationale:** The app has append-only financial/audit records, but retention compliance is a legal and accounting policy decision. The current code does not define authoritative retention periods, archival rules, deletion/anonymization boundaries, legal holds, export procedures, or operational evidence for PIPEDA/CRA compliance.

**Required to close:** legal/accounting retention schedule, data classification, archival/deletion jobs, legal hold process, audit evidence for job execution, documented administrator procedures, and terms/privacy policy updates that match the implemented retention behavior.

## High-Frequency Scheduled Workers

**Rationale:** The authenticated session-reminder and payout worker endpoints are implemented, but Vercel Hobby only permits daily cron schedules. Including the required 15-minute and hourly schedules in `vercel.json` prevents production deployment.

**Required to close:** configure the endpoints through Vercel Pro or an external scheduler, retain `CRON_SECRET` authentication, and monitor execution failures. The unsupported schedules remain excluded from `vercel.json` until that infrastructure exists.
