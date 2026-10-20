# EducateED — Full Platform Demo Script

Date: 2026-07-25 · Covers Sprints 0–8 (complete board)
Supersedes `demo-script-sprint-3-4.md` and `demo-guide-sprints-3-4-5.md`.

## Accounts

| Role | Account |
|---|---|
| Admin | `admin@educateed.ca` |
| Parent | Current founder-demo parent account (private credential handoff) |
| Tutor | Current founder-demo tutor account (private credential handoff) |

Production has 5 approved + active tutors, so discovery is populated.

## Before you start (2 min)

- Open two browsers (or one normal + one private): parent in A, tutor in B.
  The video session and whiteboard need both sides.
- Have the admin login ready in a third tab.

---

## 1. The front door (1 min)

Open `educateed.ca`.

- Ontario K–12 tutoring positioning, plans, and the **AVID Foundation**
  community spotlight on the home screen (PAR-018 BR-6).

## 2. Parent finds and books a tutor (4 min) — PAR-005, PAR-012, PAY-003

Parent account → **Find Tutors**.

- Filter by subject, grade, price, language; sort by price.
  Discovery is server-filtered: suspended/banned tutors never appear.
- Open a tutor profile → **Book a Session**.
- Pick a slot. Point out the price breakdown: session fee, and that the
  platform commission comes out of the tutor's side, not added on top.
- Complete the booking.

> Say: "Payment is captured into **escrow** immediately — the tutor doesn't get
> paid until the session is delivered and the dispute window closes." (PAY-003 BR-1/2)

Booking lands as **awaiting tutor acceptance** — the copy is deliberately honest
that it is not confirmed until the tutor accepts.

## 3. Tutor accepts (1 min) — TUT-013

Tutor browser → dashboard → accept the request. Parent side flips to confirmed.

## 4. Live session: video + screen share + whiteboard (5 min) — TUT-014, PAR-012

Both sides join the session room (join opens 5 minutes before start).

- **Video and audio** run entirely in-browser, no install (PAR-012 BR-2).
- **Session timer** visible to both participants (TUT-014 BR-3).
- **Screen share** from the tutor side.
- **Whiteboard**: open the Whiteboard integration in the call — an internal
  **Excalidraw** board, shared and collaborative both ways. Draw from each side
  to show live sync (TUT-014 BR-2).

> Say: "The whiteboard is ours — authenticated per session, not a third-party
> embed, and access is restricted to the booked tutor and student."

## 5. Completion and session notes (3 min) — TUT-015, TUT-016

Tutor marks the session complete.

- Completion is gated: at least 80% of the scheduled duration must have elapsed,
  and the student must actually have joined (no-show protection). (TUT-015 BR-1/BR-4)
- Structured notes are required: **Progress Summary, Homework Assigned, Next
  Steps** (TUT-016 BR-1). Tutors can edit for 24 hours, then notes lock.

Parent side → **Progress**: notes appear for the parent (PAR-014), alongside
per-subject stats, learning goals per child, and the six-month milestone chart
(PAR-015).

## 6. The money story (4 min) — PAY-004/005/006, TUT-018

Parent's completed session now shows a **48-hour dispute countdown** (PAY-004 BR-2).

> Say: "Funds stay in escrow for the full 48-hour dispute window. Escrow release
> is clamped to the dispute window in code — money cannot leave early even by
> misconfiguration."

Tutor → **Earnings**: gross, commission, net per session; date-range filter;
running cumulative total; **PDF statement** download (TUT-018).

Tutor → **Analytics**: rating trend, session counts, subject breakdown,
rebook rate (TUT-019).

## 7. Admin control room (4 min) — ADM-013/014/015, PAY-003 BR-3

Admin account.

- **Analytics**: KPI strip with 7/30/90-day windows — active families,
  completion rate, CSAT from verified reviews, revenue, MRR (ADM-015).
- **Sessions**: note the **Escrow** column (held / released / refunded / failed)
  next to payout status — real-time visibility of where money sits (PAY-003 BR-3).
  Open issue reports from in-session problems also surface here (PAR-013).
- **Financial reports**: CSV/PDF by custom date range — gross revenue, platform
  commission, net tutor payouts, per-tutor breakdown (ADM-013).
- **Privacy**: PIPEDA queue — data export as a ZIP bundle and deletion requests
  with the 72-hour SLA clock. Accounts with financial history are anonymized and
  retained per CRA rules rather than erased (ADM-014).

## 8. Disputes (2 min) — PAR-019, PAY-008/009

Parent raises a dispute within the 48h window; a reason category is required.

- Escrow release pauses immediately; both parties are notified (PAR-019 BR-4/5).
- Admin resolves: approve → refund reverses escrow to the parent (PAY-008);
  reject → escrow releases to the tutor and the case closes (PAY-009).

---

## If asked: what is deliberately not in the MVP

- **Session recording** — approved PIPEDA policy is *no platform recording at
  launch*. It is hard-gated in code, and no recording environment variables
  exist in production. A future release requires separate consent, access,
  deletion, and retention approval. (`docs/recording-pipeda-launch-policy.md`)
- **E-transfer payouts** — Stripe is the payout rail. PAY-007 BR-1 permits the
  integrated payment provider, so this is a closed decision, not a gap.
- **Token/credit packages** — never a board item; out of scope.

## Known board inconsistency (cosmetic)

Sprint 6 card PAY-004 still reads "24-hour dispute window"; Sprint 8 PAR-019
says 48 hours. **48 hours is the decision** and what the product enforces. The
card text needs updating.
