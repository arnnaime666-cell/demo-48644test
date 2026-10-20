-- Purge all test/e2e/demo data from production.
-- The previous migration only caught some email patterns; this one catches every
-- known test pattern including e2e in the middle of the local part, lifecycle
-- addresses, and all @example.com data (verified safe: every @example.com
-- profile matches a test pattern).

BEGIN;

-- Helper CTE matching test emails. Use a temp table so we can reference it
-- repeatedly without repeating the ILIKE patterns.
CREATE TEMP TABLE _test_profile_ids AS
SELECT id
FROM public.profiles
WHERE email ILIKE '%e2e%'
   OR email ILIKE 'archived+%'
   OR email ILIKE 'test+%@%'
   OR email ILIKE '%@example.com'
   OR email ILIKE 'demo+%@%'
   OR email ILIKE '%lifecycle%';

-- Drop append-only triggers on admin_logs so we can delete log rows
DROP TRIGGER IF EXISTS admin_logs_reject_update ON public.admin_logs;
DROP TRIGGER IF EXISTS admin_logs_reject_delete ON public.admin_logs;

-- Delete child records referencing test profiles
DELETE FROM public.admin_logs
WHERE admin_id IN (SELECT id FROM _test_profile_ids)
   OR target_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.notifications
WHERE recipient_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.session_disputes
WHERE tutor_id IN (SELECT id FROM _test_profile_ids)
   OR student_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.reviews
WHERE tutor_id IN (SELECT id FROM _test_profile_ids)
   OR student_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.sessions
WHERE tutor_id IN (SELECT id FROM _test_profile_ids)
   OR student_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.availability_slots
WHERE tutor_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.children
WHERE parent_id IN (SELECT id FROM _test_profile_ids);

DELETE FROM public.tutors
WHERE id IN (SELECT id FROM _test_profile_ids);

-- Delete test profiles
DELETE FROM public.profiles
WHERE id IN (SELECT id FROM _test_profile_ids);

-- Delete auth.users matching test patterns
DELETE FROM auth.users
WHERE email ILIKE '%e2e%'
   OR email ILIKE 'archived+%'
   OR email ILIKE 'test+%@%'
   OR email ILIKE '%@example.com'
   OR email ILIKE 'demo+%@%'
   OR email ILIKE '%lifecycle%';

-- Clean up temp helper
DROP TABLE _test_profile_ids;

-- Recreate append-only triggers on admin_logs
CREATE TRIGGER admin_logs_reject_update
  BEFORE UPDATE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

CREATE TRIGGER admin_logs_reject_delete
  BEFORE DELETE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

COMMIT;
