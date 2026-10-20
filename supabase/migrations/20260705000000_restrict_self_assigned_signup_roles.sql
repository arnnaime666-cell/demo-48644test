-- handle_new_user copied `role` verbatim from signup metadata. Supabase's
-- public signup API lets any client set arbitrary user_metadata with the anon
-- key, so a direct POST to /auth/v1/signup with {"data":{"role":"admin"}}
-- minted a full admin account — bypassing the app's signup forms entirely.
-- The 20260704000000 lockdown only guards UPDATEs; this closed the INSERT path.
--
-- Only parent / tutor / student may be self-assigned at signup. Anything else
-- (including 'admin') falls back to 'student'. Admin accounts must be promoted
-- by an existing admin through the service-role tooling.

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
    -- Self-assignable roles only; never trust 'admin' from client metadata.
    case
      when new.raw_user_meta_data->>'role' in ('parent', 'tutor', 'student')
        then new.raw_user_meta_data->>'role'
      else 'student'
    end,
    -- App currently services Ontario only (SERVICE_PROVINCE in src/types/index.ts).
    -- Default to Ontario so profiles are always visible in tutor discovery.
    coalesce(new.raw_user_meta_data->>'province', 'Ontario')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

COMMIT;
