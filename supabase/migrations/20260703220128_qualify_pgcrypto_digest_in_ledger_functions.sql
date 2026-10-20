-- Supabase installs pgcrypto into the extensions schema. These SECURITY DEFINER
-- trigger functions intentionally pin search_path to public, so qualify digest.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public.seal_financial_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    extensions.digest(coalesce(prior_hash, '') || payload, 'sha256'),
    'hex'
  );
  RETURN NEW;
END;
$$;
