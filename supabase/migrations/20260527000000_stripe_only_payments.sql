-- PAY-003 follow-up: Stripe is now the only active payment provider.
-- Existing historical migrations may mention Moneris, but current checkout,
-- refunds, subscriptions, Connect onboarding, and payouts all run through Stripe.

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_payment_provider_check;

UPDATE public.sessions
SET payment_provider = 'stripe'
WHERE payment_provider = 'moneris'
  AND stripe_payment_intent_id IS NOT NULL;

UPDATE public.sessions
SET payment_provider = NULL
WHERE payment_provider = 'moneris';

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_payment_provider_check
  CHECK (payment_provider IS NULL OR payment_provider = 'stripe');
