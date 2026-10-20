# Media feature decision gates — July 17, 2026

This record captures the founder direction received for session recordings and
whiteboards. These are separate release gates: approving the MVP whiteboard does
not approve recordings.

## Session recordings — disabled for MVP launch

Approved launch policy: EducateED does **not** offer platform session recording
in the MVP. This is the PIPEDA-safe recording policy for launch and is recorded
in `docs/recording-pipeda-launch-policy.md`.

Required controls are enforced in code:

- recording remains unavailable in the UI and class-recording entitlements return unavailable for every role;
- EducateED never requests Daily recording capability when creating rooms;
- any existing Daily room with recording enabled is treated as stale and recreated;
- the recording-consent endpoint fails closed while recordings are not offered;
- environment variables cannot activate recordings without changing the code-reviewed approval gate.

A future recording release would require a new founder/legal decision covering
minor consent, disclosure versioning, access roles, retention, early deletion,
dispute/legal holds, download/streaming rules, provider storage, and deletion
verification before any recording UI, marketing, or scheduler is enabled.

## Whiteboard — approved for internal Excalidraw MVP only

Approved path: an internal authenticated EducateED route at
`/session/[sessionId]/whiteboard`, embedded into Daily Prebuilt via custom
integrations.

Approved controls for MVP:

- Excalidraw canvas package (`@excalidraw/excalidraw`) under MIT license.
- One private board per tutoring session.
- Access restricted to the booked tutor/student via EducateED auth or a
  short-lived signed Daily iframe token.
- Supabase-backed board state in `public.session_whiteboards`.
- Autosave plus polling/realtime refresh for lightweight collaboration.
- Explicit retention timestamp, initially 30 days.
- Recordings remain untouched and disabled.

Not approved without another code-reviewed decision:

- third-party whiteboard SaaS providers;
- public/shared board URLs outside an authenticated EducateED session;
- longer retention or automatic inclusion in parent-facing permanent records;
- exporting/storing board snapshots outside the session-whiteboard retention
  path.
