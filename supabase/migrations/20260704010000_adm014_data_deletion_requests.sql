-- ADM-014 · Handle PIPEDA data export & deletion requests.
-- Parents and tutors file a deletion request; admins process it from
-- /admin/privacy. Accounts WITHOUT booking/financial history are hard-deleted
-- (existing account-deletion rules); accounts WITH history are suspended and
-- retained (CRA/PIPEDA financial-record retention), with the outcome recorded
-- on the request and in the immutable admin audit trail.
--
-- NOTE: validate in a disposable Supabase environment before production —
-- authored offline, consistent with 20260703000000_par011_learning_goals.sql.

CREATE TABLE IF NOT EXISTS public.data_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text CHECK (reason IS NULL OR char_length(reason) <= 2000),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed_deleted', 'completed_retained', 'cancelled')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  processed_by uuid REFERENCES public.profiles(id),
  resolution_notes text CHECK (resolution_notes IS NULL OR char_length(resolution_notes) <= 2000)
);

-- At most one open request per account.
CREATE UNIQUE INDEX IF NOT EXISTS data_deletion_requests_one_pending
  ON public.data_deletion_requests (user_id)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_data_deletion_requests_status
  ON public.data_deletion_requests (status, requested_at);

ALTER TABLE public.data_deletion_requests ENABLE ROW LEVEL SECURITY;

-- Requesters see their own requests; admins operate through the service role.
DROP POLICY IF EXISTS "Users can view own deletion requests" ON public.data_deletion_requests;
CREATE POLICY "Users can view own deletion requests"
  ON public.data_deletion_requests FOR SELECT
  USING (user_id = auth.uid());

-- Users may open a request only for themselves and only in the pending state;
-- processing columns are server-managed.
DROP POLICY IF EXISTS "Users can file own deletion requests" ON public.data_deletion_requests;
CREATE POLICY "Users can file own deletion requests"
  ON public.data_deletion_requests FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND processed_at IS NULL
    AND processed_by IS NULL
    AND resolution_notes IS NULL
  );

-- No user UPDATE/DELETE: requests are processed (or cancelled) server-side so
-- every outcome is audit-logged.

GRANT SELECT, INSERT ON public.data_deletion_requests TO authenticated;
GRANT ALL PRIVILEGES ON public.data_deletion_requests TO service_role;
