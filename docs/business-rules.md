# EducateED Business Rules

## Platform and Security

1. `educateed.ca` is the canonical production domain for EducateED.
2. HTTPS must be enforced across the platform at all times.
3. Valid SSL/TLS certificates must be maintained so the production site is always served securely.
4. Protected routes must require authentication.
5. Unauthenticated users attempting to access protected routes must be redirected to the correct login or signup experience.
6. Access to Admin, Parent/Student, Tutor, and Payment-related areas must be restricted by authenticated user role.
7. Role checks must be enforced server-side, not only hidden in the client UI.
8. Sensitive admin and payment operations should be auditable.

## Accessibility and UX

9. All user-facing UI components must meet WCAG 2.1 AA accessibility standards.
10. The website must be responsive across mobile, tablet, and desktop breakpoints.
11. Navigation menus, buttons, tabs, dialogs, and interactive controls must be keyboard accessible.
12. Visible focus states must be present for keyboard users.

## Application Behavior

13. Parent and student experiences may share the same family-facing booking flow, but access must still be limited to the correct authenticated role.
14. Tutor features must only be available to tutor users.
15. Admin features must only be available to admin users.
16. Public pages such as the homepage and FAQ must remain accessible without authentication.

## Tutor Discovery and Matching

17. Tutor discovery must only return tutors who are approved, active, and eligible for bookings.
18. Suspended or banned tutors must be excluded from discovery and blocked from new bookings server-side.
19. Tutor matching and filtering must use structured fields, including subject, grade band, Ontario curriculum, language, price, availability, tutor level, rating, and supported learner needs. Tutor discovery is scoped to Ontario.
20. The platform must not claim an automated "best match" unless it can show or audit the matching factors used.
21. Tutor levels must be based on admin-approved qualifications, not only self-reported profile content.

## Booking and Payment

22. Booking must re-check tutor availability server-side before payment is created.
23. A tutor cannot have more than one pending or confirmed session at the same scheduled time.
24. Families must see tutor details, selected date/time, session duration, price, cancellation policy, dispute window, and total due before paying.
25. Scheduled sessions are sessions booked at least 24 hours before the start time.
26. On-demand sessions are sessions booked less than 24 hours before the start time and may carry a separate premium when enabled.
27. Pricing modifiers such as on-demand premiums must be stored separately from base tutor rates.
28. Stripe session checkout remains the default payment flow until credit/token package accounting rules are approved.

## Cancellation, Disputes, and Payouts

29. Sessions cancelled at least 24 hours before the scheduled start may be rescheduled or refunded according to platform policy.
30. Sessions cancelled less than 24 hours before the scheduled start are not automatically refundable.
31. Parent disputes must be opened within 48 hours of the scheduled session start.
32. Admin dispute decisions must support approval, partial approval, and rejection with a written decision reason.
33. Dispute decisions and refunds must be auditable.
34. Tutor payouts for completed sessions must remain delayed until the configured payout delay has elapsed and any open dispute is resolved.
35. Tutors must submit brief post-session feedback before payout is marked ready.

## Recordings and Privacy

36. Session recording must remain disabled or unavailable until consent, retention, access, and deletion rules are formally approved.
37. If recordings are enabled, retention must be finite, visible to users, and enforceable by the platform.
38. Recorded session access must be limited to authorized family/student users, the assigned tutor, and authorized admins.
39. Environment configuration alone must not activate recordings; a code-reviewed policy approval gate is required.
40. Recording download, early deletion, and dispute-hold behavior must be approved and implemented before recording is marketed or enabled.

**Launch recording policy (approved July 24, 2026):** EducateED does not offer platform session recording in the MVP. This satisfies rules 36–40 for launch by keeping recording disabled, unmarketed, unreachable from the UI, absent from Daily room configuration, and impossible to activate through environment configuration alone. Any future recording feature requires a new code-reviewed policy and implementation covering consent, access, retention, early deletion, dispute/legal holds, download/streaming controls, provider storage, and deletion verification. See `docs/recording-pipeda-launch-policy.md`.

41. Whiteboard integration must remain unavailable until a commercially licensed provider is approved with private per-session access, persistence, retention, and data-location rules.
