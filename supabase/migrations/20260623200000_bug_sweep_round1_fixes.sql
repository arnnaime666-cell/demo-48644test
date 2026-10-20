-- Bug sweep round 1 fixes (2026-06-23)
-- Covers: tutor dispute RLS, timezone column, dispute deadline support

-- Bug #2: Tutors can't read their own disputes (RLS gap)
-- Add RLS policy allowing tutors to SELECT disputes on sessions where they are the assigned tutor
DROP POLICY IF EXISTS "Tutors can view own disputes" ON public.session_disputes;
CREATE POLICY "Tutors can view own disputes"
  ON public.session_disputes FOR SELECT
  USING (
    tutor_id = auth.uid()
  );

-- Bug #17: Timezone not persisted
-- Store timezone alongside scheduled_at so display can convert correctly
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS timezone text;

COMMENT ON COLUMN public.sessions.timezone IS
  'IANA timezone name (e.g. America/Toronto) captured at booking time for correct local display conversion.';

-- Add index for tutor dispute lookups
CREATE INDEX IF NOT EXISTS idx_session_disputes_tutor
  ON public.session_disputes (tutor_id, created_at DESC);