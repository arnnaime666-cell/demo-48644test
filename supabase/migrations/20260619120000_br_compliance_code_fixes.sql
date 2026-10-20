-- BR compliance code fixes for ADM-006:
-- flagged tutors remain visible/active unless an admin suspends or bans them.

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
           WHEN quality_status IN ('suspended', 'banned') THEN FALSE
           ELSE is_active
         END,
         updated_at = NOW()
   WHERE id = target_tutor_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP POLICY IF EXISTS "Anyone can view approved active tutors" ON public.tutors;
CREATE POLICY "Anyone can view approved active tutors"
  ON public.tutors FOR SELECT
  USING (
    application_status = 'approved'
    AND is_active = true
    AND quality_status NOT IN ('suspended', 'banned')
  );
