-- Sprint 5: Daily.co video room metadata for confirmed tutoring sessions.
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS daily_room_url text,
  ADD COLUMN IF NOT EXISTS daily_room_name text;

CREATE INDEX IF NOT EXISTS idx_sessions_daily_room_name
  ON public.sessions (daily_room_name)
  WHERE daily_room_name IS NOT NULL;

COMMENT ON COLUMN public.sessions.daily_room_url IS
  'Daily.co room URL. RLS on sessions restricts reads to the session tutor and booked student/parent.';

COMMENT ON COLUMN public.sessions.daily_room_name IS
  'Daily.co room name used for server-generated meeting tokens.';

DROP POLICY IF EXISTS "Users see own sessions" ON public.sessions;
CREATE POLICY "Users see own sessions"
  ON public.sessions FOR SELECT
  USING (auth.uid() = tutor_id OR auth.uid() = student_id);
