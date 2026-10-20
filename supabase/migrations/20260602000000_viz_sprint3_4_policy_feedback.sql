-- Viz-informed Sprint 3/4 production hardening:
-- booking classification, explicit policy acceptance, on-demand premium hooks,
-- and tutor post-session feedback before payout readiness.

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS booking_type text NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS on_demand_premium_cents integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS policy_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS policy_version text,
  ADD COLUMN IF NOT EXISTS tutor_feedback jsonb,
  ADD COLUMN IF NOT EXISTS tutor_feedback_submitted_at timestamptz;

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_booking_type_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_booking_type_check
  CHECK (booking_type IN ('scheduled', 'on_demand'));

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_on_demand_premium_nonnegative;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_on_demand_premium_nonnegative
  CHECK (on_demand_premium_cents >= 0);

CREATE INDEX IF NOT EXISTS idx_sessions_booking_type
  ON public.sessions (booking_type, scheduled_at DESC);

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_feedback_required
  ON public.sessions (status, payout_status, tutor_feedback_submitted_at)
  WHERE status = 'completed' AND payout_status = 'pending';
