-- Align parent plan rules with launch pricing:
-- Basic is included app access; Premium is the only Stripe-backed subscription.

UPDATE public.profiles
SET
  subscription_tier = 'basic',
  subscription_status = 'active',
  stripe_subscription_id = NULL
WHERE role = 'parent'
  AND (subscription_tier IS NULL OR subscription_tier = 'free');

UPDATE public.profiles
SET subscription_tier = NULL
WHERE role <> 'parent'
  AND subscription_tier = 'free';

UPDATE public.profiles
SET subscription_status = 'active'
WHERE role = 'parent'
  AND subscription_tier = 'basic'
  AND subscription_status <> 'active';

ALTER TABLE public.profiles
  ALTER COLUMN subscription_tier SET DEFAULT 'basic';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_subscription_tier_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_subscription_tier_check
  CHECK (subscription_tier IS NULL OR subscription_tier IN ('basic', 'premium'));
