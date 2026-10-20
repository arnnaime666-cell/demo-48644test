-- Sprint 4 hardening: enforce active tutor/time booking exclusivity in the DB.
-- The checkout API also checks availability, but this partial unique index closes
-- the race where two parents attempt to reserve the same tutor slot at once.

CREATE UNIQUE INDEX IF NOT EXISTS sessions_active_tutor_slot_unique
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'confirmed', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_sessions_tutor_active_schedule
  ON public.sessions (tutor_id, scheduled_at)
  WHERE status IN ('pending', 'confirmed', 'in_progress');
