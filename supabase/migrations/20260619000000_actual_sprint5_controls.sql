-- Actual Trello Sprint 5 remediation:
-- PAR-010/PAY-003/PAR-011/TUT-012/TUT-013/ADM-011/ADM-012/PAY-011
--
-- Stripe remains the supported payment rail. A successful platform charge is
-- held in escrow until the tutor accepts and the session completes; payout is
-- still executed separately through Stripe Connect.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_account_status_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_account_status_check
  CHECK (account_status IN ('active', 'suspended'));

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_status_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_status_check
  CHECK (status IN (
    'pending', 'awaiting_tutor', 'confirmed', 'in_progress',
    'completed', 'cancelled', 'disputed', 'decline_processing'
  ));

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS tutor_response_status text NOT NULL DEFAULT 'not_required',
  ADD COLUMN IF NOT EXISTS tutor_responded_at timestamptz,
  ADD COLUMN IF NOT EXISTS tutor_decline_reason text,
  ADD COLUMN IF NOT EXISTS escrow_status text NOT NULL DEFAULT 'pending';

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_tutor_response_status_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_tutor_response_status_check
  CHECK (tutor_response_status IN ('not_required', 'pending', 'accepted', 'declining', 'declined'));

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_escrow_status_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_escrow_status_check
  CHECK (escrow_status IN ('pending', 'held', 'released', 'refunded', 'failed'));

DROP INDEX IF EXISTS sessions_active_tutor_slot_unique;
DROP INDEX IF EXISTS idx_sessions_tutor_active_schedule;

CREATE UNIQUE INDEX IF NOT EXISTS sessions_active_tutor_slot_unique
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'awaiting_tutor', 'confirmed', 'in_progress', 'decline_processing');

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_active_schedule
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'awaiting_tutor', 'confirmed', 'in_progress', 'decline_processing');

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_response
  ON public.sessions (tutor_id, tutor_response_status, scheduled_at)
  WHERE tutor_response_status IN ('pending', 'declining');

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id uuid REFERENCES public.sessions(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN (
    'booking_payment_received',
    'booking_request',
    'booking_confirmed',
    'booking_declined',
    'session_reminder_24h',
    'session_reminder_1h'
  )),
  title text NOT NULL,
  body text NOT NULL,
  dedupe_key text NOT NULL UNIQUE,
  email_status text NOT NULL DEFAULT 'not_attempted'
    CHECK (email_status IN ('not_attempted', 'sent', 'failed')),
  email_attempted_at timestamptz,
  email_error text,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread
  ON public.notifications (recipient_id, created_at DESC)
  WHERE read_at IS NULL;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications"
  ON public.notifications FOR SELECT
  USING (recipient_id = auth.uid());

DROP POLICY IF EXISTS "Users can mark own notifications read" ON public.notifications;
CREATE POLICY "Users can mark own notifications read"
  ON public.notifications FOR UPDATE
  USING (recipient_id = auth.uid())
  WITH CHECK (recipient_id = auth.uid());

REVOKE UPDATE ON public.notifications FROM authenticated;
GRANT UPDATE (read_at) ON public.notifications TO authenticated;

CREATE TABLE IF NOT EXISTS public.financial_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key text NOT NULL UNIQUE,
  event_type text NOT NULL CHECK (event_type IN (
    'payment_intent_created',
    'payment_succeeded',
    'payment_failed',
    'escrow_held',
    'refund_created',
    'refund_succeeded',
    'payout_scheduled',
    'payout_processing',
    'payout_succeeded',
    'payout_failed',
    'dispute_hold',
    'subscription_payment_succeeded',
    'subscription_payment_failed'
  )),
  session_id uuid REFERENCES public.sessions(id),
  payer_id uuid REFERENCES public.profiles(id),
  payee_id uuid REFERENCES public.profiles(id),
  amount_cents integer NOT NULL CHECK (amount_cents >= 0),
  currency text NOT NULL DEFAULT 'cad' CHECK (currency = 'cad'),
  provider text CHECK (provider IS NULL OR provider = 'stripe'),
  provider_reference text,
  status text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  previous_hash text,
  entry_hash text NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_session
  ON public.financial_transactions (session_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_provider_reference
  ON public.financial_transactions (provider, provider_reference)
  WHERE provider_reference IS NOT NULL;

ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view financial ledger" ON public.financial_transactions;
CREATE POLICY "Admins can view financial ledger"
  ON public.financial_transactions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin' AND account_status = 'active'
    )
  );

ALTER TABLE public.admin_logs
  ADD COLUMN IF NOT EXISTS request_id text,
  ADD COLUMN IF NOT EXISTS before_state jsonb,
  ADD COLUMN IF NOT EXISTS after_state jsonb,
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS previous_hash text,
  ADD COLUMN IF NOT EXISTS entry_hash text NOT NULL DEFAULT '';

CREATE OR REPLACE FUNCTION public.seal_append_only_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  prior_hash text;
  payload text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME));

  EXECUTE format(
    'SELECT entry_hash FROM %I.%I ORDER BY created_at DESC, id DESC LIMIT 1',
    TG_TABLE_SCHEMA,
    TG_TABLE_NAME
  ) INTO prior_hash;

  NEW.previous_hash := prior_hash;
  payload := (to_jsonb(NEW) - 'entry_hash' - 'previous_hash')::text;
  NEW.entry_hash := encode(
    digest(coalesce(prior_hash, '') || payload, 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.seal_financial_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  prior_hash text;
  payload text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('public.financial_transactions'));

  SELECT entry_hash
    INTO prior_hash
    FROM public.financial_transactions
   ORDER BY recorded_at DESC, id DESC
   LIMIT 1;

  NEW.previous_hash := prior_hash;
  payload := (to_jsonb(NEW) - 'entry_hash' - 'previous_hash')::text;
  NEW.entry_hash := encode(
    digest(coalesce(prior_hash, '') || payload, 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS admin_logs_seal_insert ON public.admin_logs;
CREATE TRIGGER admin_logs_seal_insert
  BEFORE INSERT ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.seal_append_only_row();

DROP TRIGGER IF EXISTS admin_logs_reject_update ON public.admin_logs;
CREATE TRIGGER admin_logs_reject_update
  BEFORE UPDATE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

DROP TRIGGER IF EXISTS admin_logs_reject_delete ON public.admin_logs;
CREATE TRIGGER admin_logs_reject_delete
  BEFORE DELETE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

DROP TRIGGER IF EXISTS financial_transactions_seal_insert ON public.financial_transactions;
CREATE TRIGGER financial_transactions_seal_insert
  BEFORE INSERT ON public.financial_transactions
  FOR EACH ROW EXECUTE FUNCTION public.seal_financial_transaction();

DROP TRIGGER IF EXISTS financial_transactions_reject_update ON public.financial_transactions;
CREATE TRIGGER financial_transactions_reject_update
  BEFORE UPDATE ON public.financial_transactions
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

DROP TRIGGER IF EXISTS financial_transactions_reject_delete ON public.financial_transactions;
CREATE TRIGGER financial_transactions_reject_delete
  BEFORE DELETE ON public.financial_transactions
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_logs FROM anon, authenticated;
REVOKE UPDATE, DELETE, TRUNCATE ON public.financial_transactions FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_session_financial_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  key_suffix text;
BEGIN
  key_suffix := coalesce(NEW.payment_reference_id, NEW.stripe_transfer_id, NEW.id::text);

  IF TG_OP = 'UPDATE'
     AND OLD.payment_reference_id IS DISTINCT FROM NEW.payment_reference_id
     AND NEW.payment_reference_id IS NOT NULL THEN
    INSERT INTO public.financial_transactions (
      idempotency_key, event_type, session_id, payer_id, payee_id,
      amount_cents, provider, provider_reference, status
    ) VALUES (
      NEW.id || ':payment_intent_created:' || NEW.payment_reference_id,
      'payment_intent_created', NEW.id, NEW.student_id, NEW.tutor_id,
      NEW.price_cents, NEW.payment_provider, NEW.payment_reference_id, NEW.payment_status
    ) ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.payment_status IS DISTINCT FROM NEW.payment_status THEN
    IF NEW.payment_status = 'paid' THEN
      INSERT INTO public.financial_transactions (
        idempotency_key, event_type, session_id, payer_id, payee_id,
        amount_cents, provider, provider_reference, status
      ) VALUES (
        NEW.id || ':payment_succeeded:' || key_suffix,
        'payment_succeeded', NEW.id, NEW.student_id, NEW.tutor_id,
        NEW.price_cents, NEW.payment_provider, NEW.payment_reference_id, 'succeeded'
      ) ON CONFLICT (idempotency_key) DO NOTHING;

    ELSIF NEW.payment_status = 'failed' THEN
      INSERT INTO public.financial_transactions (
        idempotency_key, event_type, session_id, payer_id, payee_id,
        amount_cents, provider, provider_reference, status
      ) VALUES (
        NEW.id || ':payment_failed:' || key_suffix,
        'payment_failed', NEW.id, NEW.student_id, NEW.tutor_id,
        NEW.price_cents, NEW.payment_provider, NEW.payment_reference_id, 'failed'
      ) ON CONFLICT (idempotency_key) DO NOTHING;
    ELSIF NEW.payment_status = 'refunded' THEN
      INSERT INTO public.financial_transactions (
        idempotency_key, event_type, session_id, payer_id, payee_id,
        amount_cents, provider, provider_reference, status
      ) VALUES (
        NEW.id || ':refund_succeeded:' || key_suffix,
        'refund_succeeded', NEW.id, NEW.student_id, NEW.tutor_id,
        NEW.price_cents, NEW.payment_provider, NEW.payment_reference_id, 'succeeded'
      ) ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.escrow_status IS DISTINCT FROM NEW.escrow_status
     AND NEW.escrow_status = 'held' THEN
    INSERT INTO public.financial_transactions (
      idempotency_key, event_type, session_id, payer_id, payee_id,
      amount_cents, provider, provider_reference, status
    ) VALUES (
      NEW.id || ':escrow_held:' || key_suffix,
      'escrow_held', NEW.id, NEW.student_id, NEW.tutor_id,
      NEW.tutor_payout_cents, NEW.payment_provider, NEW.payment_reference_id, 'held'
    ) ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.payout_status IS DISTINCT FROM NEW.payout_status
     AND NEW.payout_status IN ('scheduled', 'processing', 'completed', 'failed') THEN
    INSERT INTO public.financial_transactions (
      idempotency_key, event_type, session_id, payer_id, payee_id,
      amount_cents, provider, provider_reference, status,
      metadata
    ) VALUES (
      NEW.id || ':payout:' || NEW.payout_status || ':' ||
        coalesce(NEW.stripe_transfer_id, NEW.payout_at::text, NEW.payout_retry_count::text),
      CASE NEW.payout_status
        WHEN 'scheduled' THEN 'payout_scheduled'
        WHEN 'processing' THEN 'payout_processing'
        WHEN 'completed' THEN 'payout_succeeded'
        ELSE 'payout_failed'
      END,
      NEW.id, NEW.student_id, NEW.tutor_id, NEW.tutor_payout_cents,
      'stripe', NEW.stripe_transfer_id, NEW.payout_status,
      jsonb_build_object('retry_count', NEW.payout_retry_count)
    ) ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.status = 'disputed' THEN
    INSERT INTO public.financial_transactions (
      idempotency_key, event_type, session_id, payer_id, payee_id,
      amount_cents, provider, provider_reference, status
    ) VALUES (
      NEW.id || ':dispute_hold',
      'dispute_hold', NEW.id, NEW.student_id, NEW.tutor_id,
      NEW.tutor_payout_cents, NEW.payment_provider, NEW.payment_reference_id, 'held'
    ) ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sessions_financial_transition ON public.sessions;
CREATE TRIGGER sessions_financial_transition
  AFTER UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.record_session_financial_transition();

CREATE OR REPLACE FUNCTION public.accept_booking_request(
  p_session_id uuid,
  p_tutor_id uuid
)
RETURNS SETOF public.sessions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.sessions
     SET status = 'confirmed',
         tutor_response_status = 'accepted',
         tutor_responded_at = now(),
         updated_at = now()
   WHERE id = p_session_id
     AND tutor_id = p_tutor_id
     AND status = 'awaiting_tutor'
     AND tutor_response_status = 'pending'
     AND payment_status = 'paid'
     AND escrow_status = 'held'
     AND scheduled_at > now()
  RETURNING *;
$$;

CREATE OR REPLACE FUNCTION public.claim_booking_decline(
  p_session_id uuid,
  p_tutor_id uuid,
  p_reason text
)
RETURNS SETOF public.sessions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.sessions
     SET status = 'decline_processing',
         tutor_response_status = 'declining',
         tutor_responded_at = now(),
         tutor_decline_reason = nullif(trim(p_reason), ''),
         updated_at = now()
   WHERE id = p_session_id
     AND tutor_id = p_tutor_id
     AND status = 'awaiting_tutor'
     AND tutor_response_status = 'pending'
     AND payment_status = 'paid'
     AND escrow_status = 'held'
  RETURNING *;
$$;

CREATE OR REPLACE FUNCTION public.finalize_booking_decline(
  p_session_id uuid,
  p_tutor_id uuid
)
RETURNS SETOF public.sessions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.sessions
     SET status = 'cancelled',
         tutor_response_status = 'declined',
         payment_status = 'refunded',
         escrow_status = 'refunded',
         payout_status = 'pending',
         payout_at = NULL,
         updated_at = now()
   WHERE id = p_session_id
     AND tutor_id = p_tutor_id
     AND status = 'decline_processing'
     AND tutor_response_status = 'declining'
  RETURNING *;
$$;

REVOKE ALL ON FUNCTION public.accept_booking_request(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_booking_decline(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_booking_decline(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_booking_request(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_booking_decline(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.finalize_booking_decline(uuid, uuid) TO service_role;

COMMENT ON TABLE public.financial_transactions IS
  'Append-only, hash-chained CAD financial ledger. Provider-side Stripe records remain the settlement source of truth.';

COMMENT ON TABLE public.admin_logs IS
  'Append-only, hash-chained admin mutation audit trail. Application code must include before/after state for privileged changes.';

COMMENT ON TABLE public.notifications IS
  'Idempotent in-app/email delivery record. Push delivery is intentionally not claimed without a configured push provider.';
