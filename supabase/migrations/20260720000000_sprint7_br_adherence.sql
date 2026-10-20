-- Sprint 7 BR adherence (board refresh 2026-07-20).
--
-- TUT-017 BR-4 / PAY-007 BR-3: tutors are notified when a payout transfer
-- succeeds — 'payout_completed' joins the notifications kind whitelist.
--
-- PAR-015 BR-1: learning goals are set per subject AND per student profile.
-- Goals gain an optional link to the family's child; NULL keeps existing rows
-- valid as family-wide goals.

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_kind_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_kind_check CHECK (kind IN (
    'booking_payment_received',
    'booking_request',
    'booking_confirmed',
    'booking_declined',
    'session_reminder_24h',
    'session_reminder_1h',
    'admin_low_rating_flag',
    'booking_expired',
    'payout_completed'
  ));

ALTER TABLE public.learning_goals
  ADD COLUMN IF NOT EXISTS child_id uuid REFERENCES public.children(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_learning_goals_child
  ON public.learning_goals (child_id)
  WHERE child_id IS NOT NULL;
