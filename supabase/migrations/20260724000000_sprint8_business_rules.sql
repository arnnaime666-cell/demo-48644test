-- Sprint 8 business-rule enforcement:
-- - PAR-018 account-scoped Premium upsell frequency and dismissal state
-- - PAR-019 required dispute categories and dispute-open notifications

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS premium_upsell_last_shown_at timestamptz,
  ADD COLUMN IF NOT EXISTS premium_upsell_dismissed_at timestamptz;

COMMENT ON COLUMN public.profiles.premium_upsell_last_shown_at IS
  'Most recent time the post-first-session Premium prompt was displayed. Used for the 30-day frequency cap.';
COMMENT ON COLUMN public.profiles.premium_upsell_dismissed_at IS
  'Permanent account-level dismissal of the post-first-session Premium prompt.';

ALTER TABLE public.session_disputes
  ADD COLUMN IF NOT EXISTS reason_category text NOT NULL DEFAULT 'other';

ALTER TABLE public.session_disputes
  DROP CONSTRAINT IF EXISTS session_disputes_reason_category_check;
ALTER TABLE public.session_disputes
  ADD CONSTRAINT session_disputes_reason_category_check CHECK (
    reason_category IN (
      'session_quality',
      'tutor_no_show',
      'technical_issue',
      'billing_issue',
      'safety_concern',
      'other'
    )
  );

COMMENT ON COLUMN public.session_disputes.reason_category IS
  'Parent-selected dispute category required by PAR-019 before intake.';

-- Keep the existing four-argument function as a backward-compatible path for
-- in-flight releases. New Sprint 8 clients call this categorized overload.
CREATE OR REPLACE FUNCTION public.open_session_dispute(
  p_session_id uuid,
  p_student_id uuid,
  p_reason text,
  p_requested_refund_cents integer,
  p_reason_category text
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
  IF p_reason_category NOT IN (
    'session_quality',
    'tutor_no_show',
    'technical_issue',
    'billing_issue',
    'safety_concern',
    'other'
  ) THEN
    RAISE EXCEPTION 'Invalid dispute reason category'
      USING ERRCODE = '23514';
  END IF;

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
    reason_category,
    requested_refund_cents
  )
  VALUES (
    locked_session.id,
    locked_session.student_id,
    locked_session.tutor_id,
    p_reason,
    p_reason_category,
    p_requested_refund_cents
  )
  RETURNING id INTO inserted_id;

  dispute_id := inserted_id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.open_session_dispute(uuid, uuid, text, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_session_dispute(uuid, uuid, text, integer, text) TO service_role;

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
    'payout_completed',
    'pipeda_request_completed',
    'dispute_opened'
  ));

COMMIT;
