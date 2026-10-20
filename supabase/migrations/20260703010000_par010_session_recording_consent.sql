-- PAR-010 (Sprint 5 backlog): session recordings — explicit opt-in consent
-- and finite 90-day retention.
--
-- Compliance posture (docs/business-rules.md #36–#37):
--   #36 Recording must remain disabled until consent/retention/access/deletion
--       rules are formally approved. The application feature flag
--       (NEXT_PUBLIC_RECORDINGS_ENABLED) therefore defaults to OFF; this
--       migration only adds the consent/retention plumbing.
--   #37 If enabled, retention must be finite, visible, and enforceable:
--       recording_retention_expires_at + the recording-retention cron enforce
--       a 90-day cap, and the consent UI displays the retention period.
--
-- NOTE: validate in a disposable Supabase environment before production —
-- Docker was unavailable locally when this migration was authored.

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS recording_parent_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS recording_tutor_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS recording_status text NOT NULL DEFAULT 'disabled',
  ADD COLUMN IF NOT EXISTS recording_retention_expires_at timestamptz;

ALTER TABLE public.sessions
  DROP CONSTRAINT IF EXISTS sessions_recording_status_check;

ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_recording_status_check
  CHECK (recording_status IN ('disabled', 'consented', 'recorded', 'expired', 'deleted'));

-- Retention sweep: find recorded sessions whose retention window has lapsed.
CREATE INDEX IF NOT EXISTS idx_sessions_recording_retention
  ON public.sessions (recording_retention_expires_at)
  WHERE recording_status = 'recorded';

-- Consent columns are written exclusively through the service-role API
-- (participant identity re-verified server-side); no participant UPDATE
-- grant is added here on purpose.
