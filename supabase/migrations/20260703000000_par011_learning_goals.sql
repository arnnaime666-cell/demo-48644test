-- PAR-011 (Sprint 6 backlog) / Trello PAR-015: student progress tracking.
-- Families set per-subject learning goals; progress itself is derived from
-- completed sessions and tutor feedback (TUT-016 data already captured on
-- sessions.tutor_feedback), so no session-side schema change is needed.
--
-- NOTE: validate in a disposable Supabase environment before production —
-- Docker was unavailable locally when this migration was authored.

CREATE TABLE IF NOT EXISTS public.learning_goals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  subject text NOT NULL,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
  description text CHECK (description IS NULL OR char_length(description) <= 2000),
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'achieved', 'archived')),
  target_date date,
  achieved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_learning_goals_family
  ON public.learning_goals (family_id, status, created_at DESC);

ALTER TABLE public.learning_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Families can view own learning goals" ON public.learning_goals;
CREATE POLICY "Families can view own learning goals"
  ON public.learning_goals FOR SELECT
  USING (family_id = auth.uid());

DROP POLICY IF EXISTS "Families can create own learning goals" ON public.learning_goals;
CREATE POLICY "Families can create own learning goals"
  ON public.learning_goals FOR INSERT
  WITH CHECK (family_id = auth.uid());

DROP POLICY IF EXISTS "Families can update own learning goals" ON public.learning_goals;
CREATE POLICY "Families can update own learning goals"
  ON public.learning_goals FOR UPDATE
  USING (family_id = auth.uid())
  WITH CHECK (family_id = auth.uid());

DROP POLICY IF EXISTS "Families can delete own learning goals" ON public.learning_goals;
CREATE POLICY "Families can delete own learning goals"
  ON public.learning_goals FOR DELETE
  USING (family_id = auth.uid());

-- Explicit Data API grants (see 20260513000000_explicit_data_api_grants.sql);
-- default privileges already cover new tables, restated here for clarity.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.learning_goals TO authenticated;
GRANT ALL PRIVILEGES ON public.learning_goals TO service_role;
