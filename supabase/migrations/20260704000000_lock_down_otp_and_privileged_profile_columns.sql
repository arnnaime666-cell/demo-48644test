-- Security hardening: OTP self-read and privileged profile column lockdown.
--
-- 1. verification_codes: the user-facing SELECT/UPDATE/INSERT policies let any
--    authenticated user, armed only with their JWT and the anon key, read the
--    plaintext `code` column through PostgREST (self-verify email/phone with
--    no mailbox or phone access), reset `attempts` to defeat the 3-attempt
--    lockout, or insert a row containing a code they chose. The verify/send
--    API routes now perform all verification_codes access with the
--    service-role client, so end-user Data API access is removed entirely.
--
-- 2. profiles: "Users can update own profile" carries no column restrictions,
--    so a user could directly flip email_verified, phone_verified, role,
--    account_status, subscription_tier, Stripe billing pointers, or the
--    terms/commission acceptance audit fields via PostgREST. A BEFORE UPDATE
--    trigger now rejects changes to those columns unless the request comes
--    from the service role (or a direct DB connection such as migrations).
--    Ordinary profile edits (full_name, phone, avatar_url, province,
--    children_info, ...) are unaffected.
--
-- DEPLOY ORDER: ship the application code that moves these writes to the
-- service-role client BEFORE applying this migration. The previous route code
-- performed these reads/writes with the user-scoped client and would start
-- failing once the policies are dropped and the trigger is installed.

-- ---------------------------------------------------------------------------
-- 1. verification_codes: service-role access only
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Users can insert own verification codes" ON public.verification_codes;
DROP POLICY IF EXISTS "Users can view own verification codes" ON public.verification_codes;
DROP POLICY IF EXISTS "Users can update own verification codes" ON public.verification_codes;

-- 20260513000000_explicit_data_api_grants.sql granted CRUD on every public
-- table to anon/authenticated and relied on RLS as the behavioral gate. RLS
-- with no policies already denies access here, but revoke the underlying
-- privileges too so a future broad policy cannot silently re-expose plaintext
-- codes.
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.verification_codes FROM anon, authenticated;

COMMENT ON TABLE public.verification_codes IS
  'Single-use OTP codes. Service-role access only: plaintext codes and attempt counters must never be reachable through the Data API.';

-- ---------------------------------------------------------------------------
-- 2. profiles: reject end-user writes to privileged columns
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.protect_privileged_profile_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  api_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
BEGIN
  -- Only end-user Data API requests are restricted. Service-role requests
  -- carry role=service_role in their JWT claims; direct DB connections
  -- (migrations, seeds, psql) carry no claims at all.
  IF api_role NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.account_status IS DISTINCT FROM OLD.account_status
     OR NEW.suspension_reason IS DISTINCT FROM OLD.suspension_reason
     OR NEW.email_verified IS DISTINCT FROM OLD.email_verified
     OR NEW.phone_verified IS DISTINCT FROM OLD.phone_verified
     OR NEW.email_confirmed_at IS DISTINCT FROM OLD.email_confirmed_at
     OR NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier
     OR NEW.subscription_status IS DISTINCT FROM OLD.subscription_status
     OR NEW.stripe_customer_id IS DISTINCT FROM OLD.stripe_customer_id
     OR NEW.stripe_subscription_id IS DISTINCT FROM OLD.stripe_subscription_id
     OR NEW.terms_accepted_at IS DISTINCT FROM OLD.terms_accepted_at
     OR NEW.terms_version IS DISTINCT FROM OLD.terms_version
     OR NEW.commission_accepted_at IS DISTINCT FROM OLD.commission_accepted_at
     OR NEW.commission_version IS DISTINCT FROM OLD.commission_version
  THEN
    RAISE EXCEPTION 'profiles: privileged columns can only be changed by the service role'
      USING ERRCODE = '42501',
            HINT = 'Identity, verification, account-status, subscription, Stripe billing, and terms/commission acceptance columns are managed by API routes via the service-role client.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_protect_privileged_columns ON public.profiles;
CREATE TRIGGER profiles_protect_privileged_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_privileged_profile_columns();

COMMENT ON FUNCTION public.protect_privileged_profile_columns() IS
  'Blocks anon/authenticated Data API requests from modifying privileged profiles columns; service-role and direct connections pass through.';
