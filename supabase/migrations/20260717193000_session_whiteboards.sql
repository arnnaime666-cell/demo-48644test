-- TUT-014 · Internal Excalidraw whiteboard state for tutoring sessions.
-- One private board per session, accessible only to the booked tutor/student.
-- Retention is explicit and can be shortened later by a cleanup cron.

CREATE TABLE IF NOT EXISTS public.session_whiteboards (
  session_id uuid PRIMARY KEY REFERENCES public.sessions(id) ON DELETE CASCADE,
  elements jsonb NOT NULL DEFAULT '[]'::jsonb,
  app_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  files jsonb NOT NULL DEFAULT '{}'::jsonb,
  version integer NOT NULL DEFAULT 0,
  retention_expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_session_whiteboards_retention
  ON public.session_whiteboards (retention_expires_at);

COMMENT ON TABLE public.session_whiteboards IS
  'Per-session Excalidraw whiteboard state. Access is limited to the session tutor/student; recordings remain separate and disabled.';

ALTER TABLE public.session_whiteboards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Participants can view own session whiteboard" ON public.session_whiteboards;
CREATE POLICY "Participants can view own session whiteboard"
  ON public.session_whiteboards FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.student_id = auth.uid() OR s.tutor_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Participants can create own session whiteboard" ON public.session_whiteboards;
CREATE POLICY "Participants can create own session whiteboard"
  ON public.session_whiteboards FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.student_id = auth.uid() OR s.tutor_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Participants can update own session whiteboard" ON public.session_whiteboards;
CREATE POLICY "Participants can update own session whiteboard"
  ON public.session_whiteboards FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.student_id = auth.uid() OR s.tutor_id = auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id
        AND (s.student_id = auth.uid() OR s.tutor_id = auth.uid())
    )
  );

CREATE OR REPLACE FUNCTION public.touch_session_whiteboard_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  NEW.version = COALESCE(OLD.version, 0) + 1;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_touch_session_whiteboard_updated_at ON public.session_whiteboards;
CREATE TRIGGER trg_touch_session_whiteboard_updated_at
  BEFORE UPDATE ON public.session_whiteboards
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_session_whiteboard_updated_at();

GRANT SELECT, INSERT, UPDATE ON public.session_whiteboards TO authenticated;
GRANT ALL PRIVILEGES ON public.session_whiteboards TO service_role;


DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.session_whiteboards;
EXCEPTION
  WHEN duplicate_object THEN NULL;
  WHEN undefined_object THEN NULL;
END;
$$;
