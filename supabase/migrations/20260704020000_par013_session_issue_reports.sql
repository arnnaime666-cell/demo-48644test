-- PAR-013 · Report technical issue or tutor no-show from session screen.
-- Participants (family or tutor) file a lightweight issue report from the
-- in-session screen; admins review them from /admin/sessions. This is NOT a
-- dispute (PAR-019 / session_disputes) — it is an operational signal that can
-- precede or accompany one.
--
-- NOTE: validate in a disposable Supabase environment before production —
-- authored offline, consistent with 20260703000000_par011_learning_goals.sql.

CREATE TABLE IF NOT EXISTS public.session_issue_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reporter_role text NOT NULL CHECK (reporter_role IN ('student', 'tutor')),
  category text NOT NULL CHECK (category IN ('technical', 'no_show', 'other')),
  description text NOT NULL CHECK (char_length(description) BETWEEN 10 AND 2000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewed')),
  reviewed_by uuid REFERENCES public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One report per participant per category per session (prevents duplicate spam
-- while still allowing e.g. one technical + one no-show report).
CREATE UNIQUE INDEX IF NOT EXISTS session_issue_reports_unique_per_reporter
  ON public.session_issue_reports (session_id, reporter_id, category);

CREATE INDEX IF NOT EXISTS idx_session_issue_reports_status
  ON public.session_issue_reports (status, created_at DESC);

ALTER TABLE public.session_issue_reports ENABLE ROW LEVEL SECURITY;

-- Reporters can see their own reports; admin access goes through the service
-- role (same pattern as session_disputes).
DROP POLICY IF EXISTS "Reporters can view own issue reports" ON public.session_issue_reports;
CREATE POLICY "Reporters can view own issue reports"
  ON public.session_issue_reports FOR SELECT
  USING (reporter_id = auth.uid());

-- Participants may insert a report only for a session they belong to, and only
-- as themselves. Status/review columns are server-managed (defaults).
DROP POLICY IF EXISTS "Participants can file issue reports" ON public.session_issue_reports;
CREATE POLICY "Participants can file issue reports"
  ON public.session_issue_reports FOR INSERT
  WITH CHECK (
    reporter_id = auth.uid()
    AND status = 'open'
    AND reviewed_by IS NULL
    AND reviewed_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.student_id = auth.uid() OR s.tutor_id = auth.uid())
    )
  );

-- No UPDATE/DELETE policies: reports are immutable for participants; admins
-- review via service role.

GRANT SELECT, INSERT ON public.session_issue_reports TO authenticated;
GRANT ALL PRIVILEGES ON public.session_issue_reports TO service_role;
