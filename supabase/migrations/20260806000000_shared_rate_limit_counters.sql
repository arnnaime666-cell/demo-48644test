-- Shared rate-limit counters.
--
-- The limiter was a per-process Map. On serverless each instance keeps its own
-- copy and they reset on cold start, so limits were far weaker than they read:
-- traffic spread across instances largely evaded them. Counters now live in the
-- database, so every instance consults the same state.
--
-- consume_rate_limit does the check and the increment in ONE statement so two
-- concurrent requests cannot both read "under the limit" and both proceed.

BEGIN;

CREATE TABLE IF NOT EXISTS public.rate_limit_counters (
  key text PRIMARY KEY,
  count integer NOT NULL DEFAULT 0,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS on with no policies: only the service role (and SECURITY DEFINER) reads
-- or writes this. Clients have no business seeing who is being throttled.
ALTER TABLE public.rate_limit_counters ENABLE ROW LEVEL SECURITY;

-- Supports the opportunistic sweep below.
CREATE INDEX IF NOT EXISTS idx_rate_limit_counters_updated_at
  ON public.rate_limit_counters (updated_at);

CREATE OR REPLACE FUNCTION public.consume_rate_limit(
  p_key text,
  p_window_ms integer,
  p_max_requests integer
)
RETURNS TABLE (allowed boolean, remaining integer, reset_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window interval := make_interval(secs => GREATEST(p_window_ms, 1) / 1000.0);
  v_count integer;
  v_window_start timestamptz;
BEGIN
  -- Single atomic statement: insert a fresh counter, or roll the window over
  -- if it has expired, or increment within the current window.
  INSERT INTO public.rate_limit_counters AS r (key, count, window_started_at, updated_at)
  VALUES (p_key, 1, now(), now())
  ON CONFLICT (key) DO UPDATE
  SET
    count = CASE
      WHEN r.window_started_at < now() - v_window THEN 1
      ELSE r.count + 1
    END,
    window_started_at = CASE
      WHEN r.window_started_at < now() - v_window THEN now()
      ELSE r.window_started_at
    END,
    updated_at = now()
  RETURNING r.count, r.window_started_at INTO v_count, v_window_start;

  -- Sweep abandoned keys occasionally rather than running a dedicated cron.
  -- Anything untouched for an hour is well past any window we use.
  IF random() < 0.005 THEN
    DELETE FROM public.rate_limit_counters
    WHERE updated_at < now() - interval '1 hour';
  END IF;

  RETURN QUERY SELECT
    v_count <= p_max_requests,
    GREATEST(p_max_requests - v_count, 0),
    v_window_start + v_window;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.consume_rate_limit(text, integer, integer) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION public.consume_rate_limit(text, integer, integer) TO service_role;

COMMIT;
