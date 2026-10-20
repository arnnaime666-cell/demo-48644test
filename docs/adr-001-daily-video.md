# ADR-001: Daily.co Video Rooms

## Status

Accepted

## Context

Sprint 5 starts the live session experience. The founder report lists these likely cards:

- PAR-008 extension: live session video room using Daily.co.
- PAR-010: opt-in recordings with 90-day retention.
- TUT-012: tutor earnings dashboard with payout history.
- ADM-011: admin analytics for tutor performance, bookings, and disputes.
- ENH-001: password reset functionality.

`docs/sprint-data.json` currently only contains Sprint 1 and Sprint 2 Trello cards, so the Sprint 5 scope is taken from `docs/sprint-3-4-founder-report.md`.

Daily's REST API supports server-created rooms via `POST /rooms`, with room privacy and properties such as `nbf`, `exp`, and `max_participants` configured at creation time. Daily rooms are public by default, meaning anyone with the URL can enter unless privacy is changed. Daily's meeting tokens are intended to control room access for non-public rooms and should be passed to `daily-js` when joining. The `daily-js` `join()` method accepts a room URL and token.

Sources:

- https://docs.daily.co/reference/rest-api/rooms
- https://docs.daily.co/reference/rest-api/rooms/create-room
- https://docs.daily.co/reference/rest-api/meeting-tokens
- https://docs.daily.co/reference/rest-api/meeting-tokens/config
- https://docs.daily.co/reference/daily-js/instance-methods/join

## Decision

Use a hybrid integration:

1. Create Daily rooms on the server for paid, confirmed sessions, using the existing Stripe confirmation lifecycle.
2. Keep a server fallback endpoint, `/api/daily/room`, that creates the room if payment confirmation could not reach Daily.
3. Store only `daily_room_url` and `daily_room_name` on `sessions`.
4. Make rooms `private` and issue short-lived per-user Daily meeting tokens at join time.
5. Let the browser use `@daily-co/daily-js` only after EducateED has verified the authenticated user is the session tutor or booked student/parent.

This is more secure than client-only `daily-js` because the Daily API key never reaches the browser and private rooms are gated by EducateED auth plus Daily meeting tokens. It is less complex than a full video backend because EducateED does not proxy media, track participants in real time, or manage recordings yet.

## Consequences

- A confirmed session can still be joined if Daily room creation failed during payment confirmation; `/api/daily/room` repairs the missing room.
- The room opens 5 minutes before the scheduled start and expires 60 minutes after the planned end.
- Tutors can mark the session `in_progress` from the room and finish it through the existing completion/payout-feedback flow.
- Future recording work should extend this ADR with consent, recording-owner token rules, retention deletion, and access audit logging before enabling Daily recording properties.
