-- Round 2 Bug Sweep Migration — 2026-06-24
-- Covers: unique constraint on financial_transactions.idempotency_key,
--         unique constraint on tutors.stripe_account_id, RLS on session_disputes,
--         partial_refunded payment status, photo_moderation_status on tutors

-- H5: Unique constraint on financial_transactions.idempotency_key to prevent duplicate inserts on webhook retries
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'financial_transactions'
      AND indexname = 'idx_financial_transactions_idempotency_key_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_financial_transactions_idempotency_key_unique
      ON public.financial_transactions (idempotency_key);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping idempotency_key unique index: %', SQLERRM;
END $$;

-- H6: Unique constraint on tutors.stripe_account_id to prevent duplicate account mappings
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'tutors'
      AND indexname = 'idx_tutors_stripe_account_id_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_tutors_stripe_account_id_unique
      ON public.tutors (stripe_account_id)
      WHERE stripe_account_id IS NOT NULL;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping stripe_account_id unique index: %', SQLERRM;
END $$;

-- M4: Add 'partially_refunded' to payment_status check constraint
-- This allows tracking partial refunds separately from full refunds
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'sessions_payment_status_check'
      AND table_name = 'sessions'
      AND table_schema = 'public'
  ) THEN
    ALTER TABLE public.sessions DROP CONSTRAINT sessions_payment_status_check;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping payment_status constraint drop: %', SQLERRM;
END $$;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_payment_status_check
  CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded', 'partially_refunded', 'cancelled'));

-- M4: Add refunded_amount_cents column to track partial refund amounts
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS refunded_amount_cents integer DEFAULT 0;

COMMENT ON COLUMN public.sessions.refunded_amount_cents IS
  'Total amount refunded to the student in cents. Used to track partial refunds.';

-- L15: Add photo_moderation_status and video_moderation_status to tutors table for consistency
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS photo_moderation_status text DEFAULT 'pending'
  CHECK (photo_moderation_status IN ('pending', 'approved', 'rejected'));

ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS video_moderation_status text DEFAULT 'pending'
  CHECK (video_moderation_status IN ('pending', 'approved', 'rejected'));

-- H8: Enable RLS on session_disputes if not already enabled
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE tablename = 'session_disputes'
      AND schemaname = 'public'
      AND rowsecurity = true
  ) THEN
    ALTER TABLE public.session_disputes ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;

-- H8: RLS policies for session_disputes (ensure existing policies don't conflict)
-- Students can view their own disputes
DROP POLICY IF EXISTS "Students can view own disputes" ON public.session_disputes;
CREATE POLICY "Students can view own disputes"
  ON public.session_disputes FOR SELECT
  USING (student_id = auth.uid());

-- Admins can view all disputes
DROP POLICY IF EXISTS "Admins can view all disputes" ON public.session_disputes;
CREATE POLICY "Admins can view all disputes"
  ON public.session_disputes FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

-- C1: Add manual_review_required flag to sessions for amount mismatch escalation
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS manual_review_required boolean DEFAULT false;

COMMENT ON COLUMN public.sessions.manual_review_required IS
  'Set to true when a payment amount mismatch is detected and needs admin review.';

-- C1: Add admin_notifications table for system alerts (amount mismatches, etc.)
CREATE TABLE IF NOT EXISTS public.admin_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL,
  severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  title text NOT NULL,
  body text,
  session_id uuid REFERENCES public.sessions(id) ON DELETE CASCADE,
  resolved boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.admin_alerts
  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view all alerts" ON public.admin_alerts;
CREATE POLICY "Admins can view all alerts"
  ON public.admin_alerts FOR ALL
  USING (EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

-- M20/L40: Add admin_notes column to session_disputes for logging requested vs approved amounts
ALTER TABLE public.session_disputes
  ADD COLUMN IF NOT EXISTS admin_resolution_notes text;

COMMENT ON COLUMN public.session_disputes.admin_resolution_notes IS
  'Additional notes logged during dispute resolution, including mismatch warnings.';

-- H14: Advisory lock functions for process-payouts cron (prevent concurrent runs)
CREATE OR REPLACE FUNCTION public.try_acquire_payout_lock(p_lock_key text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  acquired boolean;
BEGIN
  SELECT pg_try_advisory_lock(hashtext(p_lock_key)) INTO acquired;
  RETURN acquired;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_payout_lock(p_lock_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM pg_advisory_unlock(hashtext(p_lock_key));
END;
$$;

COMMENT ON FUNCTION public.try_acquire_payout_lock IS 'Acquires a session-level advisory lock for payout processing. Returns true if acquired.';
COMMENT ON FUNCTION public.release_payout_lock IS 'Releases a session-level advisory lock for payout processing.';