-- Sprint 2: Rejection tracking, per-document review, subscription tiers
-- ADM-003/004/005: Rejection reason codes, cumulative rejection count, 30-day reapplication
-- TUT-004/005/006: Per-document admin review (status + notes per doc)
-- PAR-004: Parent subscription tier
-- PAY-001/002: Invoice tracking

-- ---------------------------------------------------------------------------
-- 1. Add rejection_count column to tutors (ADM-005 BR-2/BR-3)
-- ---------------------------------------------------------------------------
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS rejection_count integer NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 2. Add rejection_reason_code column (ADM-004: structured reason codes)
-- ---------------------------------------------------------------------------
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS rejection_reason_code text;

-- ---------------------------------------------------------------------------
-- 3. Change reapplication window from 90 to 30 days (ADM-005 BR-1)
-- Update existing rejected tutors with can_reapply_at set to 30 days
-- ---------------------------------------------------------------------------
-- NOTE: The application code will now use 30 days instead of 90.
-- We don't alter existing data since the business rule applies going forward.

-- ---------------------------------------------------------------------------
-- 4. Add subscription tier to profiles for parents (PAR-004)
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_tier text
  CHECK (subscription_tier IS NULL OR subscription_tier IN ('basic', 'premium'));

-- Update the default for new parents
ALTER TABLE profiles ALTER COLUMN subscription_tier SET DEFAULT 'basic';

-- ---------------------------------------------------------------------------
-- 5. Add stripe_customer_id for parent payment tracking (PAY-001)
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS stripe_customer_id text UNIQUE;

-- ---------------------------------------------------------------------------
-- 6. Add stripe_subscription_id for recurring billing (PAY-001)
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS stripe_subscription_id text;

-- ---------------------------------------------------------------------------
-- 7. Add subscription_status for tracking (PAY-001)
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS subscription_status text
  DEFAULT 'inactive'
  CHECK (subscription_status IN ('inactive', 'active', 'past_due', 'canceled', 'trialing'));

-- ---------------------------------------------------------------------------
-- 8. Add invoice tracking columns for GST/HST invoices (PAY-002)
-- ---------------------------------------------------------------------------
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS invoice_number text UNIQUE;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS invoice_url text;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS gst_hst_amount_cents integer DEFAULT 0;

-- ---------------------------------------------------------------------------
-- 9. Add per-document admin review fields (ADM-003)
-- The `documents` JSONB column already exists on tutors.
-- We're enhancing the schema to include per-document review notes.
-- Structure: { gov_id: { url, status, admin_notes, reviewed_by, reviewed_at }, ... }
-- This is handled in application code; no schema change needed since it's JSONB.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 10. Add senior_admin_id for escalated reapplications (ADM-005 BR-3)
-- ---------------------------------------------------------------------------
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS senior_admin_id uuid REFERENCES public.profiles(id);

-- ---------------------------------------------------------------------------
-- 12. Add reapply_notified_at for ADM-005 BR-4 (track reapplication notifications)
-- ---------------------------------------------------------------------------
ALTER TABLE tutors ADD COLUMN IF NOT EXISTS reapply_notified_at timestamptz;

-- ---------------------------------------------------------------------------
-- 11. Index for faster rejection tracking queries
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_tutors_rejection_count
  ON public.tutors (rejection_count) WHERE rejection_count >= 3;
