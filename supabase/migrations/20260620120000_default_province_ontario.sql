-- Default province to Ontario for all new auth-created profiles.
-- The app only services Ontario (SERVICE_PROVINCE in src/types/index.ts).
-- Without this, profiles created without explicit province metadata
-- get NULL and are invisible in tutor discovery (which filters province = 'Ontario').

BEGIN;

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, phone, role, province)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    nullif(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    -- App currently services Ontario only (SERVICE_PROVINCE in src/types/index.ts).
    -- Default to Ontario so profiles are always visible in tutor discovery.
    coalesce(new.raw_user_meta_data->>'province', 'Ontario')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- Backfill existing NULL provinces to Ontario (app only services Ontario).
-- Safe: every NULL-province user was invisible in discovery anyway.
UPDATE public.profiles
SET province = 'Ontario', updated_at = now()
WHERE province IS NULL;

COMMIT;