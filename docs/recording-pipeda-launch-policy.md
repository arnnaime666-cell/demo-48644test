# Session Recording PIPEDA Launch Policy

Date: 2026-07-24
Status: Approved launch policy for MVP

## Decision

EducateED will not offer platform session recording at launch.

This is the approved PIPEDA-safe MVP posture for recordings: no session-recording UI, no Daily recording capability, no recording access or download surface, no recording marketing copy, and no environment-only switch that can activate recordings.

## Scope

Applies to:

- Daily video rooms created by EducateED.
- Parent/student and tutor session experiences.
- Admin session tooling.
- Any product copy that describes platform features.

Does not prohibit:

- Non-recording video sessions.
- Screen sharing.
- In-session whiteboard collaboration under the approved whiteboard policy.
- Structured post-session notes, homework, progress summaries, dispute reports, and audit logs already covered by platform privacy controls.
- A temporary demo-only recording toggle when explicitly enabled with consent from both participants, finite retention, and a documented turn-off step.

## Required controls for MVP

1. Daily rooms must be private and must not request `enable_recording` by default.
2. Class-recording entitlements must remain unavailable for every role outside the controlled demo path.
3. The recording-consent API must fail closed while recordings are not offered and demo mode is not explicitly enabled.
4. Environment variables such as `RECORDINGS_ENABLED` and `RECORDING_RETENTION_DAYS` must not activate recordings without either a code-reviewed approval gate or the temporary demo override below.
5. Existing Daily rooms that advertise recording capability must be considered stale and recreated without recording when recording is disabled.
6. Any legacy/provider recording discovered by the retention backstop must not be surfaced to users and must only be marked expired after provider deletion is confirmed.

## Temporary demo override

For founder demos only, recordings can be enabled by setting all required server env vars:

- `RECORDINGS_ENABLED=true`
- `RECORDINGS_DEMO_ENABLED=true`
- `RECORDING_RETENTION_DAYS=30` (or `60` / `90`)

If the demo is on production, also set:

- `RECORDINGS_DEMO_ALLOW_PRODUCTION=true`

To show the consent UI in the browser, set:

- `NEXT_PUBLIC_RECORDINGS_DEMO_ENABLED=true`

Demo recording still requires both participants to consent before the Daily room is prepared. Turn the feature back off by removing/unsetting `RECORDINGS_DEMO_ENABLED`, `RECORDINGS_DEMO_ALLOW_PRODUCTION`, and `NEXT_PUBLIC_RECORDINGS_DEMO_ENABLED`, then redeploying.

## Future approval requirements

A future recording feature must not be enabled, marketed, or scheduled until all of the following are approved and implemented:

- PIPEDA consent wording for parent/guardian, student where applicable, and tutor participants.
- Consent versioning and audit trail.
- Access rules for authorized family/student users, assigned tutor, and authorized admins.
- Streaming/download decision and controls.
- Finite retention period visible to users.
- Early deletion process.
- Dispute/legal-hold exception process.
- Provider storage location and deletion-verification procedure.
- Tests proving policy-gate, consent, retention, access, deletion, and dispute-hold behavior.

## Launch-readiness conclusion

Recordings are no longer a pending launch blocker because the approved MVP policy is to not provide platform recordings. The existing code satisfies this policy by keeping recording disabled, unreachable, and impossible to enable through runtime configuration alone.
