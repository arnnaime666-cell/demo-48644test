-- Fix production signup failures caused by the auth.users -> public.profiles trigger
-- writing columns that do not exist yet on older deployed databases.

begin;

alter table public.profiles
  add column if not exists phone text,
  add column if not exists avatar_url text,
  add column if not exists email_verified boolean not null default false,
  add column if not exists phone_verified boolean not null default false,
  add column if not exists email_confirmed_at timestamptz,
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text,
  add column if not exists commission_accepted_at timestamptz,
  add column if not exists commission_version text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.profiles
  alter column role set default 'student';

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('admin', 'tutor', 'student', 'parent'));

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    nullif(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'role', 'student')
  );
  return new;
end;
$$ language plpgsql security definer;

commit;
