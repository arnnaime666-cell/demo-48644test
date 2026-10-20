-- High-priority production hardening from the 2026-06-17 bug sweep:
-- - expiring pending checkout holds
-- - payout row claiming
-- - atomic dispute opening + payout hold
-- - Stripe webhook event idempotency

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS hold_expires_at timestamptz;

DROP INDEX IF EXISTS sessions_active_tutor_slot_unique;
DROP INDEX IF EXISTS idx_sessions_tutor_active_schedule;

CREATE UNIQUE INDEX IF NOT EXISTS sessions_active_tutor_slot_unique
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'confirmed', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_active_schedule
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'confirmed', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_sessions_pending_hold_expiry
  ON public.sessions (hold_expires_at)
  WHERE status = 'pending' AND payment_status = 'pending';

COMMENT ON COLUMN public.sessions.hold_expires_at IS
  'UTC expiry for unpaid pending checkout holds. Expired holds are cancelled before availability/conflict checks.';

CREATE OR REPLACE FUNCTION public.cleanup_expired_session_holds(p_tutor_id uuid DEFAULT NULL, p_scheduled_at timestamptz DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  affected_count integer;
BEGIN
  UPDATE public.sessions
     SET status = 'cancelled',
         payment_status = 'failed',
         hold_expires_at = NULL,
         updated_at = now()
   WHERE status = 'pending'
     AND payment_status = 'pending'
     AND hold_expires_at IS NOT NULL
     AND hold_expires_at <= now()
     AND (p_tutor_id IS NULL OR tutor_id = p_tutor_id)
     AND (p_scheduled_at IS NULL OR scheduled_at = p_scheduled_at);

  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RETURN affected_count;
END;
$$;

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_payout_status_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_payout_status_check
  CHECK (payout_status IN ('pending', 'scheduled', 'processing', 'completed', 'failed'));

CREATE OR REPLACE FUNCTION public.claim_session_payout(p_session_id uuid)
RETURNS SETOF public.sessions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.sessions
     SET payout_status = 'processing',
         updated_at = now()
   WHERE id = p_session_id
     AND status = 'completed'
     AND payout_status = 'scheduled'
     AND tutor_feedback_submitted_at IS NOT NULL
     AND payout_at <= now()
  RETURNING *;
$$;

CREATE OR REPLACE FUNCTION public.open_session_dispute(
  p_session_id uuid,
  p_student_id uuid,
  p_reason text,
  p_requested_refund_cents integer
)
RETURNS TABLE(dispute_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  locked_session public.sessions%ROWTYPE;
  inserted_id uuid;
BEGIN
  UPDATE public.sessions
     SET status = 'disputed',
         payout_status = 'pending',
         payout_at = NULL,
         updated_at = now()
   WHERE id = p_session_id
     AND student_id = p_student_id
     AND status = 'completed'
     AND payout_status = 'scheduled'
  RETURNING * INTO locked_session;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.session_disputes (
    session_id,
    student_id,
    tutor_id,
    reason,
    requested_refund_cents
  )
  VALUES (
    locked_session.id,
    locked_session.student_id,
    locked_session.tutor_id,
    p_reason,
    p_requested_refund_cents
  )
  RETURNING id INTO inserted_id;

  dispute_id := inserted_id;
  RETURN NEXT;
END;
$$;

CREATE TABLE IF NOT EXISTS public.stripe_events (
  id text PRIMARY KEY,
  type text NOT NULL,
  status text NOT NULL DEFAULT 'processing'
    CHECK (status IN ('processing', 'processed', 'failed')),
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stripe_events_status
  ON public.stripe_events (status, updated_at DESC);

ALTER TABLE public.stripe_events ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.stripe_events IS
  'Stripe webhook event ledger. Event IDs are claimed before side effects so duplicate deliveries are skipped.';
