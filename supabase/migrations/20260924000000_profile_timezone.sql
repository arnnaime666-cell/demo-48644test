-- Recipient-local session time display ("goes both ways").
--
-- Sessions already store the booker's IANA timezone (20260623200000), which
-- rendered every session email in the booker's zone — wrong for a tutor in
-- another timezone. profiles.timezone stores each user's own zone so session
-- emails render per recipient: tutors persist theirs when saving availability
-- (TUT-008 BR-3 selector), bookers refresh theirs at checkout. Rendering
-- falls back to the session's booked timezone, then America/Toronto (the
-- Ontario-only era default).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS timezone text;

COMMENT ON COLUMN public.profiles.timezone IS
  'IANA timezone name (e.g. America/Toronto) captured from the user''s browser; used to render session times in each recipient''s local timezone.';