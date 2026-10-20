-- Sprint 3: tutor profile maturity, discovery filters, commission tiers, quality monitoring
-- TUT-007/008/009, PAR-005/006, PAY-010, ADM-006/007/008

-- ---------------------------------------------------------------------------
-- Tutor profile setup fields
-- ---------------------------------------------------------------------------
ALTER TABLE public.tutors
  ADD COLUMN IF NOT EXISTS curriculum_tags text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS languages text[] NOT NULL DEFAULT ARRAY['English'],
  ADD COLUMN IF NOT EXISTS intro_video_url text,
  ADD COLUMN IF NOT EXISTS commission_tier text NOT NULL DEFAULT 'starter',
  ADD COLUMN IF NOT EXISTS quality_status text NOT NULL DEFAULT 'good',
  ADD COLUMN IF NOT EXISTS quality_flagged_at timestamptz,
  ADD COLUMN IF NOT EXISTS quality_review_notes text;

ALTER TABLE public.tutors
  DROP CONSTRAINT IF EXISTS tutors_commission_tier_check;

ALTER TABLE public.tutors
  ADD CONSTRAINT tutors_commission_tier_check
  CHECK (commission_tier IN ('starter', 'standard', 'premium'));

ALTER TABLE public.tutors
  DROP CONSTRAINT IF EXISTS tutors_quality_status_check;

ALTER TABLE public.tutors
  ADD CONSTRAINT tutors_quality_status_check
  CHECK (quality_status IN ('good', 'flagged', 'warned', 'suspended', 'banned'));

ALTER TABLE public.tutors
  DROP CONSTRAINT IF EXISTS tutors_languages_check;

ALTER TABLE public.tutors
  ADD CONSTRAINT tutors_languages_check
  CHECK (languages <@ ARRAY['English', 'French']::text[]);

CREATE INDEX IF NOT EXISTS idx_tutors_subjects_gin
  ON public.tutors USING gin (subjects);

CREATE INDEX IF NOT EXISTS idx_tutors_grade_levels_gin
  ON public.tutors USING gin (grade_levels);

CREATE INDEX IF NOT EXISTS idx_tutors_languages_gin
  ON public.tutors USING gin (languages);

CREATE INDEX IF NOT EXISTS idx_tutors_curriculum_tags_gin
  ON public.tutors USING gin (curriculum_tags);

CREATE INDEX IF NOT EXISTS idx_tutors_quality_status
  ON public.tutors (quality_status);

-- ---------------------------------------------------------------------------
-- PAR-007: families can bookmark tutors for comparison.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tutor_favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tutor_id uuid NOT NULL REFERENCES public.tutors(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (student_id, tutor_id)
);

CREATE INDEX IF NOT EXISTS idx_tutor_favorites_student
  ON public.tutor_favorites (student_id, created_at DESC);

ALTER TABLE public.tutor_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Families can manage own favorite tutors" ON public.tutor_favorites;
CREATE POLICY "Families can manage own favorite tutors"
  ON public.tutor_favorites FOR ALL
  USING (student_id = auth.uid())
  WITH CHECK (student_id = auth.uid());

-- ---------------------------------------------------------------------------
-- ADM-009/010: parent disputes, review decision, and audit trail.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.session_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tutor_id uuid NOT NULL REFERENCES public.tutors(id) ON DELETE CASCADE,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'approved', 'partially_approved', 'rejected')),
  requested_refund_cents integer,
  approved_refund_cents integer,
  admin_id uuid REFERENCES public.profiles(id),
  admin_notes text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (session_id)
);

CREATE INDEX IF NOT EXISTS idx_session_disputes_status
  ON public.session_disputes (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_session_disputes_student
  ON public.session_disputes (student_id, created_at DESC);

ALTER TABLE public.session_disputes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Families can view own disputes" ON public.session_disputes;
CREATE POLICY "Families can view own disputes"
  ON public.session_disputes FOR SELECT
  USING (student_id = auth.uid());

DROP POLICY IF EXISTS "Families can open own disputes" ON public.session_disputes;
CREATE POLICY "Families can open own disputes"
  ON public.session_disputes FOR INSERT
  WITH CHECK (student_id = auth.uid());

DROP POLICY IF EXISTS "Admins can view disputes" ON public.session_disputes;
CREATE POLICY "Admins can view disputes"
  ON public.session_disputes FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins can update disputes" ON public.session_disputes;
CREATE POLICY "Admins can update disputes"
  ON public.session_disputes FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- ADM-006: automatically flag tutors whose average rating drops below 3.5.
-- Keep the tutor approved for marketplace history, but remove active discovery
-- visibility until admin investigates and resolves the quality status.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_tutor_rating_avg()
RETURNS trigger AS $$
DECLARE
  target_tutor_id uuid;
  next_rating numeric;
  next_completed_sessions integer;
BEGIN
  target_tutor_id := COALESCE(NEW.tutor_id, OLD.tutor_id);

  SELECT COALESCE(AVG(rating), 0)
    INTO next_rating
    FROM public.reviews
   WHERE tutor_id = target_tutor_id;

  SELECT COUNT(*)
    INTO next_completed_sessions
    FROM public.sessions
   WHERE tutor_id = target_tutor_id
     AND status = 'completed';

  UPDATE public.tutors
     SET rating_avg = next_rating,
         total_sessions = next_completed_sessions,
         quality_status = CASE
           WHEN next_completed_sessions > 0
            AND next_rating > 0
            AND next_rating < 3.5
            AND quality_status NOT IN ('suspended', 'banned')
           THEN 'flagged'
           ELSE quality_status
         END,
         quality_flagged_at = CASE
           WHEN next_completed_sessions > 0
            AND next_rating > 0
            AND next_rating < 3.5
            AND quality_status NOT IN ('suspended', 'banned')
            AND quality_flagged_at IS NULL
           THEN NOW()
           ELSE quality_flagged_at
         END,
         is_active = CASE
           WHEN next_completed_sessions > 0
            AND next_rating > 0
            AND next_rating < 3.5
            AND quality_status NOT IN ('suspended', 'banned')
           THEN FALSE
           ELSE is_active
         END,
         updated_at = NOW()
   WHERE id = target_tutor_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
