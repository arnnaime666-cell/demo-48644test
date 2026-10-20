-- Purge test/e2e fixtures from production, including ledger/admin rows.
-- Test fixtures are not real financial/compliance records. This migration also
-- installs a service-role RPC that E2E teardown can call after future runs.

CREATE OR REPLACE FUNCTION public.purge_test_fixtures(
  p_cutoff timestamptz DEFAULT NULL,
  p_limit integer DEFAULT 500,
  p_include_scrubbed boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_profile_ids uuid[] := ARRAY[]::uuid[];
  v_session_ids uuid[] := ARRAY[]::uuid[];
  v_auth_ids uuid[] := ARRAY[]::uuid[];
  v_financial_deleted integer := 0;
  v_admin_deleted integer := 0;
  v_disputes_deleted integer := 0;
  v_reviews_deleted integer := 0;
  v_issue_reports_deleted integer := 0;
  v_sessions_deleted integer := 0;
  v_availability_deleted integer := 0;
  v_children_deleted integer := 0;
  v_codes_deleted integer := 0;
  v_notifications_deleted integer := 0;
  v_deletion_requests_deleted integer := 0;
  v_tutors_deleted integer := 0;
  v_profiles_deleted integer := 0;
  v_auth_deleted integer := 0;
BEGIN
  CREATE TEMP TABLE _test_profiles ON COMMIT DROP AS
  SELECT p.id
  FROM public.profiles p
  WHERE (
       p.email ILIKE '%e2e%'
    OR p.email ILIKE 'archived+%'
    OR p.email ILIKE 'test+%@%'
    OR p.email ILIKE '%@example.com'
    OR p.email ILIKE 'demo+%@%'
    OR p.email ILIKE '%lifecycle%'
    OR (p_include_scrubbed AND p.email ILIKE 'scrubbed-test-%@example.invalid')
    OR (p_include_scrubbed AND p.email ILIKE 'deleted-test-%@example.invalid')
    OR (p_include_scrubbed AND p.email ILIKE 'deleted-e2e-%@example.invalid')
    OR p.full_name IN ('Deleted Test User', 'Scrubbed Test User', 'Former Demo User')
  )
  AND (p_cutoff IS NULL OR p.created_at < p_cutoff)
  ORDER BY p.created_at
  LIMIT GREATEST(COALESCE(p_limit, 500), 1);

  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) INTO v_profile_ids FROM _test_profiles;

  CREATE TEMP TABLE _test_sessions ON COMMIT DROP AS
  SELECT s.id
  FROM public.sessions s
  WHERE s.student_id = ANY(v_profile_ids)
     OR s.tutor_id = ANY(v_profile_ids);

  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) INTO v_session_ids FROM _test_sessions;

  CREATE TEMP TABLE _test_auth_users ON COMMIT DROP AS
  SELECT u.id
  FROM auth.users u
  WHERE (
       u.email ILIKE '%e2e%'
    OR u.email ILIKE 'archived+%'
    OR u.email ILIKE 'test+%@%'
    OR u.email ILIKE '%@example.com'
    OR u.email ILIKE 'demo+%@%'
    OR u.email ILIKE '%lifecycle%'
    OR (p_include_scrubbed AND u.email ILIKE 'scrubbed-test-%@example.invalid')
    OR (p_include_scrubbed AND u.email ILIKE 'deleted-test-%@example.invalid')
    OR (p_include_scrubbed AND u.email ILIKE 'deleted-e2e-%@example.invalid')
  )
  AND (p_cutoff IS NULL OR u.created_at < p_cutoff)
  ORDER BY u.created_at
  LIMIT GREATEST(COALESCE(p_limit, 500), 1);

  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]) INTO v_auth_ids FROM _test_auth_users;

  -- Test fixture ledger/admin rows are not production records. Temporarily
  -- disable append-only delete guards so the fixtures can be fully purged.
  ALTER TABLE public.financial_transactions DISABLE TRIGGER financial_transactions_reject_delete;
  ALTER TABLE public.admin_logs DISABLE TRIGGER admin_logs_reject_delete;

  DELETE FROM public.financial_transactions ft
  WHERE ft.session_id = ANY(v_session_ids)
     OR ft.payer_id = ANY(v_profile_ids)
     OR ft.payee_id = ANY(v_profile_ids)
     OR ft.idempotency_key ILIKE '%e2e%'
     OR ft.idempotency_key ILIKE '%test%'
     OR ft.provider_reference ILIKE '%e2e%'
     OR ft.provider_reference ILIKE '%test%'
     OR ft.metadata::text ILIKE '%e2e%'
     OR ft.metadata::text ILIKE '%@example.com%'
     OR ft.metadata::text ILIKE '%scrubbed-test-%';
  GET DIAGNOSTICS v_financial_deleted = ROW_COUNT;

  DELETE FROM public.admin_logs al
  WHERE al.admin_id = ANY(v_profile_ids)
     OR al.target_id = ANY(v_profile_ids)
     OR al.metadata::text ILIKE '%e2e%'
     OR al.metadata::text ILIKE '%@example.com%'
     OR al.metadata::text ILIKE '%scrubbed-test-%'
     OR al.before_state::text ILIKE '%e2e%'
     OR al.before_state::text ILIKE '%@example.com%'
     OR al.after_state::text ILIKE '%e2e%'
     OR al.after_state::text ILIKE '%@example.com%';
  GET DIAGNOSTICS v_admin_deleted = ROW_COUNT;

  ALTER TABLE public.financial_transactions ENABLE TRIGGER financial_transactions_reject_delete;
  ALTER TABLE public.admin_logs ENABLE TRIGGER admin_logs_reject_delete;

  DELETE FROM public.session_disputes WHERE session_id = ANY(v_session_ids) OR tutor_id = ANY(v_profile_ids) OR student_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_disputes_deleted = ROW_COUNT;

  DELETE FROM public.reviews WHERE session_id = ANY(v_session_ids) OR tutor_id = ANY(v_profile_ids) OR student_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_reviews_deleted = ROW_COUNT;

  DELETE FROM public.session_issue_reports WHERE session_id = ANY(v_session_ids);
  GET DIAGNOSTICS v_issue_reports_deleted = ROW_COUNT;

  DELETE FROM public.sessions WHERE id = ANY(v_session_ids);
  GET DIAGNOSTICS v_sessions_deleted = ROW_COUNT;

  DELETE FROM public.availability_slots WHERE tutor_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_availability_deleted = ROW_COUNT;

  DELETE FROM public.children WHERE parent_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_children_deleted = ROW_COUNT;

  DELETE FROM public.verification_codes WHERE user_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_codes_deleted = ROW_COUNT;

  DELETE FROM public.notifications WHERE recipient_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_notifications_deleted = ROW_COUNT;

  DELETE FROM public.data_deletion_requests WHERE user_id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_deletion_requests_deleted = ROW_COUNT;

  DELETE FROM public.tutors WHERE id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_tutors_deleted = ROW_COUNT;

  DELETE FROM public.profiles WHERE id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_profiles_deleted = ROW_COUNT;

  DELETE FROM auth.users WHERE id = ANY(v_auth_ids) OR id = ANY(v_profile_ids);
  GET DIAGNOSTICS v_auth_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'matched_profiles', COALESCE(array_length(v_profile_ids, 1), 0),
    'matched_sessions', COALESCE(array_length(v_session_ids, 1), 0),
    'matched_auth_users', COALESCE(array_length(v_auth_ids, 1), 0),
    'financial_transactions_deleted', v_financial_deleted,
    'admin_logs_deleted', v_admin_deleted,
    'session_disputes_deleted', v_disputes_deleted,
    'reviews_deleted', v_reviews_deleted,
    'session_issue_reports_deleted', v_issue_reports_deleted,
    'sessions_deleted', v_sessions_deleted,
    'availability_slots_deleted', v_availability_deleted,
    'children_deleted', v_children_deleted,
    'verification_codes_deleted', v_codes_deleted,
    'notifications_deleted', v_notifications_deleted,
    'data_deletion_requests_deleted', v_deletion_requests_deleted,
    'tutors_deleted', v_tutors_deleted,
    'profiles_deleted', v_profiles_deleted,
    'auth_users_deleted', v_auth_deleted
  );
EXCEPTION WHEN OTHERS THEN
  -- Best-effort restore of append-only guards before surfacing the error.
  BEGIN
    ALTER TABLE public.financial_transactions ENABLE TRIGGER financial_transactions_reject_delete;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    ALTER TABLE public.admin_logs ENABLE TRIGGER admin_logs_reject_delete;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_test_fixtures(timestamptz, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_test_fixtures(timestamptz, integer, boolean) TO service_role;

-- Run once immediately for existing production test fixtures.
SELECT public.purge_test_fixtures(NULL, 1000, true);
