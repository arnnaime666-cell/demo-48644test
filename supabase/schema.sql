-- EducateED Platform — Supabase Schema
-- Historical snapshot only. Do not use this file to bootstrap a fresh database.
-- The authoritative database definition lives in supabase/migrations/.
-- Generated from codebase analysis. Run against a fresh Supabase project.
-- Idempotent: uses IF NOT EXISTS / OR REPLACE throughout.
-- Last updated: 2026-04-30

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- profiles (extends auth.users, created automatically via trigger)
create table if not exists public.profiles (
  id          uuid references auth.users on delete cascade primary key,
  email       text        not null,
  full_name   text,
  phone       text,
  avatar_url  text,
  role        text        not null default 'student'
                check (role in ('admin', 'tutor', 'student', 'parent')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Verification status
  email_verified     boolean not null default false,
  phone_verified     boolean not null default false,
  -- TUT-001: Auth confirmation
  email_confirmed_at timestamptz,
  -- TUT-003: Terms & commission acceptance
  terms_accepted_at    timestamptz,
  terms_version       text,   -- tracks which version was accepted; null if never accepted
  commission_accepted_at timestamptz,
  commission_version   text,   -- tracks which commission structure version accepted
  -- PAR-001: Parent signup province
  province    text,
  -- Recipient-local session time display (IANA zone from the browser)
  timezone    text,
  -- AUTH-001: Parent children support
  children_info jsonb
);

-- tutors (one-to-one extension of profiles)
create table if not exists public.tutors (
  id                    uuid references public.profiles on delete cascade primary key,
  bio                   text,
  subjects              text[]      not null default '{}',
  grade_levels          text[]      not null default '{}',
  hourly_rate           integer     not null default 5000,  -- cents CAD
  session_duration      integer     not null default 60,    -- minutes
  stripe_account_id     text        unique,
  stripe_account_status text        not null default 'pending'
                          check (stripe_account_status in ('pending', 'active', 'restricted')),
  application_status    text        not null default 'pending'
                          check (application_status in ('pending', 'approved', 'rejected', 'flagged')),
  rejection_reason      text,
  rejected_at           timestamptz,
  can_reapply_at        timestamptz,
  is_active             boolean     not null default false,
  rating_avg            numeric(3,2) not null default 0,
  total_sessions        integer     not null default 0,
  -- ADM-002: Flagged tutor support
  flagged_reasons       jsonb,
  documents             jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

-- AUTH-001: Normalized children table
create table if not exists public.children (
  id          uuid        primary key default gen_random_uuid(),
  parent_id   uuid        not null references public.profiles(id) on delete cascade,
  name        text        not null,
  grade_level text        not null,
  created_at  timestamptz not null default now()
);

-- TUT-002: OTP verification codes
-- Single-use; expires after 10 minutes; max 3 verify attempts per code.
create table if not exists public.verification_codes (
  id         uuid        default uuid_generate_v4() primary key,
  code       text        not null,          -- 6-digit numeric string
  user_id    uuid        not null references public.profiles on delete cascade,
  type       text        not null check (type in ('email', 'phone')),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  attempts   integer     not null default 0, -- increment each verify attempt
  used       boolean     not null default false,
  created_at timestamptz not null default now()
);

-- index for fast lookups by user + type
create index if not exists idx_verification_codes_user_type
  on public.verification_codes (user_id, type, created_at desc);

-- tutor weekly availability
create table if not exists public.availability_slots (
  id           uuid        default uuid_generate_v4() primary key,
  tutor_id     uuid        not null references public.tutors on delete cascade,
  day_of_week  integer     not null check (day_of_week between 0 and 6),
  start_time   time        not null,
  end_time     time        not null,
  is_active    boolean     not null default true,
  created_at   timestamptz not null default now(),
  constraint   availability_slots_no_overlap
    unique (tutor_id, day_of_week, start_time)
);

-- sessions / bookings
create table if not exists public.sessions (
  id                      uuid        default uuid_generate_v4() primary key,
  tutor_id                uuid        not null references public.tutors,
  student_id              uuid        not null references public.profiles,
  subject                 text        not null,
  grade_level             text        not null,
  scheduled_at            timestamptz not null,
  duration_minutes        integer     not null default 60,
  price_cents             integer     not null,
  platform_fee_cents      integer     not null,
  tutor_payout_cents      integer     not null,
  booking_type            text        not null default 'scheduled'
                            check (booking_type in ('scheduled', 'on_demand')),
  on_demand_premium_cents integer     not null default 0
                            check (on_demand_premium_cents >= 0),
  status                  text        not null default 'pending'
                            check (status in (
                              'pending', 'confirmed', 'in_progress',
                              'completed', 'cancelled', 'disputed'
                            )),
  tutor_joined_at         timestamptz,
  student_joined_at       timestamptz,
  completed_at            timestamptz,
  daily_room_url          text,
  daily_room_name         text,
  stripe_payment_intent_id text       unique,
  stripe_transfer_id      text        unique,
  payment_provider        text
                            check (payment_provider is null or payment_provider = 'stripe'),
  payment_reference_id    text,
  payment_status          text        not null default 'pending'
                            check (payment_status in ('pending', 'paid', 'failed', 'refunded')),
  payment_receipt         jsonb,
  -- Delayed payout fields ---------------------------------------------------
  -- payout_at is set when payment is confirmed (now + PAYOUT_DELAY_HOURS).
  -- payout_status transitions: pending → scheduled → completed | failed.
  -- A cron job calls /api/sessions/process-payouts to execute due transfers.
  -- payout_retry_count tracks automatic retry attempts before permanent failure.
  payout_at               timestamptz,
  payout_status           text        not null default 'pending'
                            check (payout_status in (
                              'pending', 'scheduled', 'completed', 'failed'
                            )),
  payout_retry_count      integer     not null default 0,
  -- -------------------------------------------------------------------------
  policy_accepted_at      timestamptz,
  policy_version          text,
  tutor_feedback          jsonb,
  tutor_feedback_submitted_at timestamptz,
  tutor_feedback_updated_at timestamptz,
  notes                   text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- index to speed up the cron job query
create index if not exists idx_sessions_payout_due
  on public.sessions (payout_at)
  where payout_status = 'scheduled' and status = 'completed';

create index if not exists idx_sessions_booking_type
  on public.sessions (booking_type, scheduled_at desc);

create index if not exists idx_sessions_tutor_feedback_required
  on public.sessions (status, payout_status, tutor_feedback_submitted_at)
  where status = 'completed' and payout_status = 'pending';

create index if not exists idx_sessions_daily_room_name
  on public.sessions (daily_room_name)
  where daily_room_name is not null;

-- REV-001: Reviews table for post-session student ratings
create table if not exists public.reviews (
  id          uuid        default uuid_generate_v4() primary key,
  session_id  uuid        not null references public.sessions on delete cascade,
  tutor_id    uuid        not null references public.tutors,
  student_id  uuid        not null references public.profiles,
  rating      integer     not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);

-- One review per student per session
create unique index if not exists reviews_session_student_unique
  on public.reviews (session_id, student_id);

-- Fast lookup of all reviews for a tutor
create index if not exists reviews_tutor_id_idx on public.reviews (tutor_id);

-- admin audit log
create table if not exists public.admin_logs (
  id          uuid        default uuid_generate_v4() primary key,
  admin_id    uuid        not null references public.profiles,
  action      text        not null,
  target_type text        not null,
  target_id   uuid        not null,
  notes       text,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles         enable row level security;
alter table public.tutors           enable row level security;
alter table public.children         enable row level security;
alter table public.verification_codes enable row level security;
alter table public.availability_slots enable row level security;
alter table public.sessions         enable row level security;
alter table public.reviews          enable row level security;
alter table public.admin_logs       enable row level security;

-- profiles
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

drop policy if exists "Public can view all profiles" on public.profiles;
create policy "Public can view all profiles"
  on public.profiles for select using (true);

-- tutors
-- ADM-006 (20260619120000): warned tutors stay visible; only suspended/banned
-- are hidden. Keep this in sync with that migration -- it is authoritative.
drop policy if exists "Anyone can view approved active tutors" on public.tutors;
create policy "Anyone can view approved active tutors"
  on public.tutors for select
  using (
    application_status = 'approved'
    and is_active = true
    and quality_status not in ('suspended', 'banned')
  );

drop policy if exists "Tutors can view own record" on public.tutors;
create policy "Tutors can view own record"
  on public.tutors for select using (auth.uid() = id);

drop policy if exists "Tutors can update own record" on public.tutors;
create policy "Tutors can update own record"
  on public.tutors for update using (auth.uid() = id);

-- children (AUTH-001)
drop policy if exists "children_select" on public.children;
create policy "children_select" on public.children
  for select using (parent_id = auth.uid());

drop policy if exists "children_insert" on public.children;
create policy "children_insert" on public.children
  for insert with check (parent_id = auth.uid());

drop policy if exists "children_update" on public.children;
create policy "children_update" on public.children
  for update using (parent_id = auth.uid());

drop policy if exists "children_delete" on public.children;
create policy "children_delete" on public.children
  for delete using (parent_id = auth.uid());

-- verification_codes (20260704 hardening: service-role access only)
-- End users must never reach this table through the Data API: reading their
-- own row exposes the plaintext `code` (self-verify without mailbox/phone
-- access) and updating it can reset the 3-attempt lockout. The verify/send
-- API routes use the service-role client.
drop policy if exists "Users can insert own verification codes" on public.verification_codes;
drop policy if exists "Users can view own verification codes" on public.verification_codes;
drop policy if exists "Users can update own verification codes" on public.verification_codes;
revoke select, insert, update, delete on public.verification_codes from anon, authenticated;

-- NOTE: admin writes and webhook writes require the service role key.
-- Never grant 'service role full access' via a named policy — service role
-- bypasses RLS automatically.

-- availability slots
drop policy if exists "Anyone can view active slots" on public.availability_slots;
create policy "Anyone can view active slots"
  on public.availability_slots for select using (is_active = true);

drop policy if exists "Tutors can manage own slots" on public.availability_slots;
create policy "Tutors can manage own slots"
  on public.availability_slots for all using (auth.uid() = tutor_id);

-- sessions
drop policy if exists "Users see own sessions" on public.sessions;
create policy "Users see own sessions"
  on public.sessions for select
  using (auth.uid() = tutor_id or auth.uid() = student_id);

drop policy if exists "Students can create sessions" on public.sessions;
create policy "Students can create sessions"
  on public.sessions for insert
  with check (auth.uid() = student_id);

-- reviews (REV-001)
drop policy if exists "reviews_select_public" on public.reviews;
create policy "reviews_select_public"
  on public.reviews for select using (true);

drop policy if exists "reviews_insert_own" on public.reviews;
create policy "reviews_insert_own"
  on public.reviews for insert
  with check (student_id = auth.uid());

-- admin logs
drop policy if exists "Admins can view logs" on public.admin_logs;
create policy "Admins can view logs"
  on public.admin_logs for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );

drop policy if exists "Admins can insert logs" on public.admin_logs;
create policy "Admins can insert logs"
  on public.admin_logs for insert
  with check (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'admin'
    )
  );

-- ---------------------------------------------------------------------------
-- Functions & Triggers
-- ---------------------------------------------------------------------------

-- PAR-001: Auto-create profile on sign-up (includes province)
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- REV-001: Auto-update tutor rating and session count after review changes
-- Replaces old refresh_tutor_stats (insert-only) with insert/update/delete support.
create or replace function public.refresh_tutor_rating_avg()
returns trigger as $$
begin
  update public.tutors
  set
    rating_avg      = coalesce((select avg(rating) from public.reviews where tutor_id = coalesce(new.tutor_id, old.tutor_id)), 0),
    total_sessions  = (select count(*) from public.sessions where tutor_id = coalesce(new.tutor_id, old.tutor_id) and status = 'completed'),
    updated_at      = now()
  where id = coalesce(new.tutor_id, old.tutor_id);
  return coalesce(new, old);
end;
$$ language plpgsql security definer;

drop trigger if exists trg_refresh_tutor_rating_avg on public.reviews;
create trigger trg_refresh_tutor_rating_avg
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_tutor_rating_avg();

-- Drop old trigger name if it still exists from earlier schema versions
drop trigger if exists on_review_inserted on public.reviews;

-- AUTH-001: Sync from children_info JSONB to normalized children table
create or replace function public.sync_children_from_profile()
returns trigger language plpgsql security definer as $$
declare
  child_item jsonb;
begin
  if new.role = 'parent' and new.children_info is not null then
    delete from public.children where parent_id = new.id;
    for child_item in select * from jsonb_array_elements(new.children_info)
    loop
      insert into public.children (parent_id, name, grade_level)
      values (new.id, child_item->>'name', child_item->>'grade');
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_children_on_profile_write on public.profiles;
create trigger sync_children_on_profile_write
  after insert or update of children_info on public.profiles
  for each row execute function public.sync_children_from_profile();

-- ---------------------------------------------------------------------------
-- Data API Grants
-- ---------------------------------------------------------------------------
-- Supabase no longer implicitly exposes new public-schema tables to Data API
-- roles on new projects from 2026-05-30, then existing projects from
-- 2026-10-30. Keep privileges explicit and let RLS policies remain the
-- behavioral gate for anon/authenticated access.
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant all privileges on all tables in schema public to service_role;

grant usage, select on all sequences in schema public to anon, authenticated;
grant all privileges on all sequences in schema public to service_role;

grant execute on all functions in schema public to anon, authenticated, service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;

alter default privileges in schema public
  grant all privileges on tables to service_role;

alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated;

alter default privileges in schema public
  grant all privileges on sequences to service_role;

alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

-- Auto-bump updated_at on profiles, tutors, and sessions
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

drop trigger if exists set_tutors_updated_at on public.tutors;
create trigger set_tutors_updated_at
  before update on public.tutors
  for each row execute procedure public.set_updated_at();

drop trigger if exists set_sessions_updated_at on public.sessions;
create trigger set_sessions_updated_at
  before update on public.sessions
  for each row execute procedure public.set_updated_at();

-- 20260704 hardening: "Users can update own profile" has no column
-- restrictions, so privileged columns are guarded by a trigger instead.
-- Only service-role requests (and direct DB connections) may change them.
create or replace function public.protect_privileged_profile_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  api_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
begin
  if api_role not in ('anon', 'authenticated') then
    return new;
  end if;

  if new.role is distinct from old.role
     or new.email is distinct from old.email
     or new.account_status is distinct from old.account_status
     or new.suspension_reason is distinct from old.suspension_reason
     or new.email_verified is distinct from old.email_verified
     or new.phone_verified is distinct from old.phone_verified
     or new.email_confirmed_at is distinct from old.email_confirmed_at
     or new.subscription_tier is distinct from old.subscription_tier
     or new.subscription_status is distinct from old.subscription_status
     or new.stripe_customer_id is distinct from old.stripe_customer_id
     or new.stripe_subscription_id is distinct from old.stripe_subscription_id
     or new.terms_accepted_at is distinct from old.terms_accepted_at
     or new.terms_version is distinct from old.terms_version
     or new.commission_accepted_at is distinct from old.commission_accepted_at
     or new.commission_version is distinct from old.commission_version
  then
    raise exception 'profiles: privileged columns can only be changed by the service role'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_protect_privileged_columns on public.profiles;
create trigger profiles_protect_privileged_columns
  before update on public.profiles
  for each row execute function public.protect_privileged_profile_columns();

-- ---------------------------------------------------------------------------
-- Optional: pg_cron for automated payout processing
-- (requires pg_cron extension — available on Supabase Pro+)
-- ---------------------------------------------------------------------------
-- create extension if not exists pg_cron;
--
-- select cron.schedule(
--   'process-scheduled-payouts',
--   '0 * * * *',   -- every hour
--   $$
--     select net.http_post(
--       url := current_setting('app.base_url') || '/api/sessions/process-payouts',
--       headers := jsonb_build_object(
--         'Authorization', 'Bearer ' || current_setting('app.cron_secret'),
--         'Content-Type',  'application/json'
--       ),
--       body := '{}'::jsonb
--     );
--   $$
-- );
