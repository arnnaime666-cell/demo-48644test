-- Server-authoritative signup guard (Supabase `before_user_created` Auth Hook).
--
-- WHY THIS EXISTS
-- The app validates signup email in the browser before calling Supabase Auth,
-- but signup talks to /auth/v1/signup directly, so a script can skip the UI
-- entirely. This hook runs inside Supabase before a user row is created, so it
-- cannot be bypassed — the same reason the role whitelist moved into
-- handle_new_user.
--
-- SPLIT OF RESPONSIBILITY
-- - Here: disposable-domain blocking. Pure data, no network needed.
-- - App layer: MX validation. Postgres cannot do DNS lookups, so that check
--   stays in /api/auth/validate-email.
--
-- The blocklist is a TABLE, not a hardcoded list, so domains can be added or
-- removed with a single INSERT/DELETE instead of a migration and deploy.

BEGIN;

CREATE TABLE IF NOT EXISTS public.blocked_email_domains (
  domain text PRIMARY KEY,
  reason text NOT NULL DEFAULT 'disposable',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- No RLS policies are defined on purpose: with RLS enabled and no policy, anon
-- and authenticated clients cannot read the list. The hook reaches it through
-- SECURITY DEFINER, and admins through the service role. There is no reason to
-- let a caller enumerate which domains we screen.
ALTER TABLE public.blocked_email_domains ENABLE ROW LEVEL SECURITY;

INSERT INTO public.blocked_email_domains (domain) VALUES
  ('0-mail.com'), ('10minutemail.com'), ('20minutemail.com'), ('33mail.com'),
  ('anonbox.net'), ('burnermail.io'), ('discard.email'), ('dispostable.com'),
  ('emailondeck.com'), ('emltmp.com'), ('fakeinbox.com'), ('fakemail.net'),
  ('getairmail.com'), ('getnada.com'), ('grr.la'), ('guerrillamail.com'),
  ('guerrillamail.net'), ('guerrillamail.org'), ('inboxbear.com'),
  ('inboxkitten.com'), ('jetable.org'), ('luxusmail.org'), ('mailcatch.com'),
  ('mailde.de'), ('maildrop.cc'), ('mailinator.com'), ('mailnesia.com'),
  ('mailsac.com'), ('mintemail.com'), ('moakt.com'), ('mohmal.com'),
  ('mytemp.email'), ('pokemail.net'), ('sharklasers.com'), ('spam4.me'),
  ('spambog.com'), ('spamgourmet.com'), ('temp-mail.io'), ('temp-mail.org'),
  ('tempinbox.com'), ('tempmail.net'), ('tempmailaddress.com'),
  ('throwawaymail.com'), ('tmpmail.net'), ('tmpmail.org'), ('trashmail.com'),
  ('trashmail.de'), ('trbvm.com'), ('vomoto.com'), ('wegwerfmail.de'),
  ('yopmail.com'), ('yopmail.fr'), ('yopmail.net')
ON CONFLICT (domain) DO NOTHING;

CREATE OR REPLACE FUNCTION public.before_user_created_email_guard(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate_email text;
  candidate_domain text;
  is_blocked boolean;
BEGIN
  candidate_email := lower(trim(coalesce(event -> 'user' ->> 'email', '')));

  -- No address to judge (phone signups, for example). Supabase already
  -- validates format, so anything unparseable is not this hook's business.
  IF candidate_email = '' THEN
    RETURN '{}'::jsonb;
  END IF;

  -- Everything after the LAST "@" — split_part would mishandle quoted local
  -- parts that themselves contain an "@".
  candidate_domain := substring(candidate_email from '@([^@]+)$');

  IF candidate_domain IS NULL OR candidate_domain = '' THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.blocked_email_domains b WHERE b.domain = candidate_domain
  ) INTO is_blocked;

  IF is_blocked THEN
    RETURN jsonb_build_object(
      'error',
      jsonb_build_object(
        'http_code', 400,
        'message',
        'This email provider is not supported. Please sign up with a permanent email address.'
      )
    );
  END IF;

  RETURN '{}'::jsonb;

EXCEPTION
  WHEN OTHERS THEN
    -- FAIL OPEN, deliberately. This hook sits in front of every signup on the
    -- platform; a fault here (missing table mid-migration, unexpected payload)
    -- must never stop real families and tutors from registering. Disposable
    -- addresses are a hygiene problem, and OTP plus a real payment card still
    -- gate anything that costs money.
    RETURN '{}'::jsonb;
END;
$$;

-- Only the auth service may run it; nothing else needs to.
GRANT EXECUTE ON FUNCTION public.before_user_created_email_guard(jsonb) TO supabase_auth_admin;
REVOKE EXECUTE ON FUNCTION public.before_user_created_email_guard(jsonb) FROM authenticated, anon, public;

-- Deliberately NOT logging blocked attempts from inside the hook: it runs on
-- unauthenticated traffic, so writing a row per rejection would hand anyone a
-- way to inflate our tables. Attempts made through the UI are already recorded
-- as admin alerts by /api/auth/validate-email.

COMMIT;
