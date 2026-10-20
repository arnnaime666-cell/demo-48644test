-- Sprint 6 session lifecycle hardening.
-- Supports TUT-014 / PAR-012 join tracking, TUT-015 completion gating, and
-- TUT-016 24-hour session note edits.

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS tutor_joined_at timestamptz,
  ADD COLUMN IF NOT EXISTS student_joined_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS tutor_feedback_updated_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_sessions_completion_guard
  ON public.sessions (status, scheduled_at, student_joined_at)
  WHERE status IN ('confirmed', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_feedback_edit_window
  ON public.sessions (tutor_feedback_submitted_at)
  WHERE status = 'completed' AND tutor_feedback_submitted_at IS NOT NULL;

COMMENT ON COLUMN public.sessions.tutor_joined_at IS
  'First timestamp at which the tutor requested a Daily room token for this session.';

COMMENT ON COLUMN public.sessions.student_joined_at IS
  'First timestamp at which the student requested a Daily room token for this session.';

COMMENT ON COLUMN public.sessions.completed_at IS
  'Timestamp at which the tutor marked the session complete.';

COMMENT ON COLUMN public.sessions.tutor_feedback_updated_at IS
  'Last timestamp at which structured tutor session notes were submitted or edited.';
