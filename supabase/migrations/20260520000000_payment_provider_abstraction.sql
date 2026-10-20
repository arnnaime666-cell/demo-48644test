-- PAY-003: Payment provider abstraction for Moneris-primary, Stripe-secondary processing.

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS payment_provider text
  CHECK (payment_provider IS NULL OR payment_provider IN ('moneris', 'stripe'));

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS payment_reference_id text;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS payment_status text
  NOT NULL DEFAULT 'pending'
  CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded'));

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS payment_receipt jsonb;

CREATE INDEX IF NOT EXISTS idx_sessions_payment_provider_reference
  ON public.sessions (payment_provider, payment_reference_id);
