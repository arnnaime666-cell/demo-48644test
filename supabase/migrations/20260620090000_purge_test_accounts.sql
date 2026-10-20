-- Purge e2e and archived test accounts from production
-- Temporarily drops admin_logs append-only triggers, nulls FK references,
-- deletes all test data, then recreates the triggers.

BEGIN;

-- Drop append-only triggers on admin_logs
DROP TRIGGER IF EXISTS admin_logs_reject_update ON public.admin_logs;
DROP TRIGGER IF EXISTS admin_logs_reject_delete ON public.admin_logs;

-- Delete admin_logs rows that reference test accounts (admin_id is NOT NULL, can't null it)
DELETE FROM public.admin_logs 
WHERE admin_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' 
       OR email LIKE 'archived+%' 
       OR full_name = 'Former Demo User'
)
OR target_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' 
       OR email LIKE 'archived+%' 
       OR full_name = 'Former Demo User'
);

-- Delete remaining child records referencing test accounts
DELETE FROM public.notifications 
WHERE recipient_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' 
       OR email LIKE 'archived+%' 
       OR full_name = 'Former Demo User'
);

DELETE FROM public.session_disputes 
WHERE tutor_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
) OR student_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

DELETE FROM public.reviews 
WHERE tutor_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
) OR student_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

DELETE FROM public.sessions 
WHERE tutor_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
) OR student_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

DELETE FROM public.availability_slots 
WHERE tutor_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

DELETE FROM public.children 
WHERE parent_id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

DELETE FROM public.tutors 
WHERE id IN (
    SELECT id FROM public.profiles 
    WHERE email LIKE '%e2e%' OR email LIKE 'archived+%' OR full_name = 'Former Demo User'
);

-- Delete the test profiles
DELETE FROM public.profiles 
WHERE email LIKE '%e2e%' 
   OR email LIKE 'archived+%' 
   OR full_name = 'Former Demo User';

-- Delete auth.users matching test emails
DELETE FROM auth.users 
WHERE email LIKE '%e2e%@example.com%'
   OR email LIKE 'e2e-%'
   OR email LIKE 'archived+%'
   OR email LIKE '%e2e%';

-- Recreate append-only triggers on admin_logs
CREATE TRIGGER admin_logs_reject_update
  BEFORE UPDATE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

CREATE TRIGGER admin_logs_reject_delete
  BEFORE DELETE ON public.admin_logs
  FOR EACH ROW EXECUTE FUNCTION public.reject_append_only_mutation();

COMMIT;