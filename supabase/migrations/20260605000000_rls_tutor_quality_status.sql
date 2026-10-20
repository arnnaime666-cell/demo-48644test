-- Fix: RLS policy "Anyone can view approved active tutors" must also require quality_status = 'good'
-- to ensure warned/suspended/banned tutors are not visible via direct Data API access.

DROP POLICY IF EXISTS "Anyone can view approved active tutors" ON public.tutors;
CREATE POLICY "Anyone can view approved active tutors"
  ON public.tutors FOR SELECT
  USING (application_status = 'approved' AND is_active = true AND quality_status = 'good');
