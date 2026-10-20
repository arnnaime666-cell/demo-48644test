-- Sprint 3-5 BR hardening: add IP address column to admin_logs
-- ADM-012 BR-2: Each audit record must include admin user ID, action type, affected entity, timestamp, and IP address
-- ADM-011 BR-2: Each account action must be logged with admin ID, timestamp, and IP address

ALTER TABLE public.admin_logs
  ADD COLUMN IF NOT EXISTS ip_address text;

-- Set default for new rows; existing rows will have NULL which is acceptable
-- (append-only trigger prevents UPDATE, so we use ALTER DEFAULT instead)
ALTER TABLE public.admin_logs
  ALTER COLUMN ip_address SET DEFAULT 'unknown';

-- Add index for querying financial transactions by date/type/user (PAY-011 BR-3)
CREATE INDEX IF NOT EXISTS idx_financial_transactions_date_type
  ON public.financial_transactions (occurred_at, event_type);

CREATE INDEX IF NOT EXISTS idx_financial_transactions_user
  ON public.financial_transactions (payer_id, payee_id);

-- Add index for admin_logs queryable by date/action (ADM-012)
CREATE INDEX IF NOT EXISTS idx_admin_logs_date_action
  ON public.admin_logs (created_at, action);

-- Add suspension reason column to profiles for ADM-011 BR-5
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS suspension_reason text;

-- TUT-008 BR-4: Tutor blocked dates (holidays, unavailability)
CREATE TABLE IF NOT EXISTS public.tutor_blocked_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tutor_id uuid NOT NULL REFERENCES public.tutors(id) ON DELETE CASCADE,
  blocked_date date NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tutor_id, blocked_date)
);

ALTER TABLE public.tutor_blocked_dates ENABLE ROW LEVEL SECURITY;

CREATE POLICY tutor_blocked_dates_owner_select ON public.tutor_blocked_dates
  FOR SELECT TO authenticated USING (tutor_id = auth.uid());
CREATE POLICY tutor_blocked_dates_owner_insert ON public.tutor_blocked_dates
  FOR INSERT TO authenticated WITH CHECK (tutor_id = auth.uid());
CREATE POLICY tutor_blocked_dates_owner_delete ON public.tutor_blocked_dates
  FOR DELETE TO authenticated USING (tutor_id = auth.uid());

-- Service role can do everything
CREATE POLICY tutor_blocked_dates_service_all ON public.tutor_blocked_dates
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ADM-008 BR-4: Temporary suspension must have a defined end date with auto-reinstate
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS suspended_until timestamptz;

-- ADM-009 BR-2: Add tutor statement field to disputes
ALTER TABLE public.session_disputes
  ADD COLUMN IF NOT EXISTS tutor_statement text;

-- TUT-010 BR-4: Media moderation status (bio, photo, video must undergo admin moderation before publish)
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS bio_moderation_status text NOT NULL DEFAULT 'approved';
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS photo_moderation_status text NOT NULL DEFAULT 'approved';
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS video_moderation_status text NOT NULL DEFAULT 'approved';

ALTER TABLE public.tutors DROP CONSTRAINT IF EXISTS tutors_media_moderation_check;
ALTER TABLE public.tutors
  ADD CONSTRAINT tutors_media_moderation_check CHECK (
    bio_moderation_status IN ('pending', 'approved', 'rejected') AND
    photo_moderation_status IN ('pending', 'approved', 'rejected') AND
    video_moderation_status IN ('pending', 'approved', 'rejected')
  );

-- ADM-006 BR-3: Add a trigger to create in-platform notification when auto-flagging
-- The refresh_tutor_rating_avg function already auto-flags; we add a post-update trigger
-- to insert a notification row when quality_status transitions to 'flagged'.
CREATE OR REPLACE FUNCTION public.notify_admin_low_rating_flag()
RETURNS trigger AS $$
BEGIN
  -- Only fire when quality_status changed TO 'flagged' (not from suspended/banned)
  IF NEW.quality_status = 'flagged'
     AND OLD.quality_status <> 'flagged'
     AND NEW.quality_flagged_at IS NOT NULL
  THEN
    INSERT INTO public.notifications (recipient_id, kind, title, body, dedupe_key)
    SELECT
      p.id,
      'admin_low_rating_flag',
      'Tutor auto-flagged: rating below 3.5',
      'Tutor ' || NEW.id || ' has an average rating of ' || ROUND(NEW.rating_avg, 2) || ' and has been auto-flagged for admin review.',
      'auto_flag:' || NEW.id || ':' || DATE(NOW())
    FROM public.profiles p
    WHERE p.role = 'admin' AND p.account_status = 'active'
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_admin_low_rating ON public.tutors;
CREATE TRIGGER trg_notify_admin_low_rating
  AFTER UPDATE ON public.tutors
  FOR EACH ROW EXECUTE FUNCTION public.notify_admin_low_rating_flag();

-- ADM-006 BR-3: Index for admin notifications
-- Extend notification kinds for admin low-rating flag and booking expired
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
    'booking_expired'
  ));
