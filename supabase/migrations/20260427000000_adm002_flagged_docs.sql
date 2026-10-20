-- ADM-002: Add flagged_reasons and documents columns to tutors table
-- Also add 'flagged' as a valid application_status

-- Add flagged_reasons column (JSONB array of strings)
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS flagged_reasons JSONB DEFAULT NULL;

-- Add documents column (JSONB with government_id, teaching_certificate, degree, background_check)
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS documents JSONB DEFAULT NULL;

-- Add check constraint for application_status including 'flagged'
-- Drop existing constraint if it exists, then add new one
ALTER TABLE tutors DROP CONSTRAINT IF EXISTS tutors_application_status_check;
ALTER TABLE tutors ADD CONSTRAINT tutors_application_status_check
  CHECK (application_status IN ('pending', 'approved', 'rejected', 'flagged'));

-- Add province column to profiles for parent signup (PAR-001)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS province TEXT DEFAULT NULL;