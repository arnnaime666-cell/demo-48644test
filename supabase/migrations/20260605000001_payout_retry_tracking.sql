-- Add payout retry tracking to sessions table
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS payout_retry_count integer NOT NULL DEFAULT 0;

-- Index for querying failed payouts that may need manual review
CREATE INDEX IF NOT EXISTS idx_sessions_payout_failed
  ON public.sessions (payout_status, payout_retry_count)
  WHERE payout_status = 'failed';
