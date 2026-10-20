-- The June 19 controls migration created two hash-chain seal functions that
-- call digest() with search_path pinned to public. On Supabase, pgcrypto is
-- installed into the extensions schema, so digest() fails to resolve and every
-- INSERT into admin_logs (seal_append_only_row) or financial_transactions
-- (seal_financial_transaction) errors. 20260703220128 fixed only the financial
-- function, and only for the extensions-schema layout.
--
-- Recreate BOTH functions with search_path = public, extensions and an
-- unqualified digest() call, so they resolve pgcrypto whether it was installed
-- into public (plain CREATE EXTENSION default) or extensions (Supabase).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.seal_append_only_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  prior_hash text;
  payload text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext(TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME));

  EXECUTE format(
    'SELECT entry_hash FROM %I.%I ORDER BY created_at DESC, id DESC LIMIT 1',
    TG_TABLE_SCHEMA,
    TG_TABLE_NAME
  ) INTO prior_hash;

  NEW.previous_hash := prior_hash;
  payload := (to_jsonb(NEW) - 'entry_hash' - 'previous_hash')::text;
  NEW.entry_hash := encode(
    digest(coalesce(prior_hash, '') || payload, 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.seal_financial_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  prior_hash text;
  payload text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('public.financial_transactions'));

  SELECT entry_hash
    INTO prior_hash
    FROM public.financial_transactions
   ORDER BY recorded_at DESC, id DESC
   LIMIT 1;

  NEW.previous_hash := prior_hash;
  payload := (to_jsonb(NEW) - 'entry_hash' - 'previous_hash')::text;
  NEW.entry_hash := encode(
    digest(coalesce(prior_hash, '') || payload, 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;
