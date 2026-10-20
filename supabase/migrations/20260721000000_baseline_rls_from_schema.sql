-- Baseline RLS parity: bring a migrations-only database up to production.
--
-- supabase/schema.sql is the historical source of truth for the base tables
-- (profiles, tutors, verification_codes, availability_slots, sessions,
-- admin_logs) and for their RLS enables and policies. `supabase db push`
-- never applies schema.sql -- it only runs migrations/ -- so any database
-- provisioned purely by db push (the E2E dev project) is missing all of it.
--
-- Two consequences, both observed:
--   1. Missing "Public can view all profiles" / "Anyone can view approved
--      active tutors" broke the client-side read in the booking flow, which
--      renders "Tutor not available" instead of the booking form and has kept
--      the E2E gate red since 2026-07-17.
--   2. More seriously, the `enable row level security` statements also live
--      only in schema.sql. 20260513000000_explicit_data_api_grants.sql grants
--      full CRUD on every public table to anon/authenticated and relies on RLS
--      as the behavioural gate -- so a migrations-only database exposes these
--      tables through the Data API with RLS switched off entirely.
--
-- Every statement below is idempotent (enable-RLS is a no-op when already on;
-- policies are drop-if-exists + create), so this replays safely against
-- production, which already matches this state.
--
-- DELIBERATELY OMITTED: policies that a later migration already owns. Those
-- migrations are authoritative and schema.sql has since drifted from them --
-- re-creating schema.sql's copy here would roll them back. Specifically:
--   * "Anyone can view approved active tutors" -> 20260619120000. schema.sql
--     still carries the older `quality_status = 'good'` predicate; the live
--     rule is `quality_status NOT IN ('suspended','banned')`, which keeps
--     warned-but-not-suspended tutors visible (ADM-006). Do not re-add it.
--   * "Users see own sessions"                 -> 20260617000000
--   * children_{select,insert,update,delete}   -> 20260425000002
--   * reviews_{select_public,insert_own}       -> 20260425000004

-- ---------------------------------------------------------------------------
-- Row Level Security enables
-- ---------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.tutors             enable row level security;
alter table public.children           enable row level security;
alter table public.verification_codes enable row level security;
alter table public.availability_slots enable row level security;
alter table public.sessions           enable row level security;
alter table public.reviews            enable row level security;
alter table public.admin_logs         enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- Tutor discovery joins profiles from the browser under the caller's JWT, so
-- profile rows must stay publicly selectable. Column-level protection for the
-- privileged fields is enforced by the profiles_protect_privileged_columns
-- trigger from 20260704000000, not by this policy.
drop policy if exists "Public can view all profiles" on public.profiles;
create policy "Public can view all profiles"
  on public.profiles for select using (true);

-- ---------------------------------------------------------------------------
-- tutors  (see OMITTED note above re: the public discovery policy)
-- ---------------------------------------------------------------------------
drop policy if exists "Tutors can view own record" on public.tutors;
create policy "Tutors can view own record"
  on public.tutors for select using (auth.uid() = id);

drop policy if exists "Tutors can update own record" on public.tutors;
create policy "Tutors can update own record"
  on public.tutors for update using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- verification_codes: service-role only (mirrors 20260704000000)
--
-- End users must never reach this table through the Data API: reading their
-- own row exposes the plaintext `code` and updating it can reset the
-- 3-attempt lockout. Re-asserted here because the enable-RLS above is what
-- makes the absence of policies actually deny.
-- ---------------------------------------------------------------------------
drop policy if exists "Users can insert own verification codes" on public.verification_codes;
drop policy if exists "Users can view own verification codes" on public.verification_codes;
drop policy if exists "Users can update own verification codes" on public.verification_codes;
revoke select, insert, update, delete on public.verification_codes from anon, authenticated;

-- ---------------------------------------------------------------------------
-- availability_slots
-- ---------------------------------------------------------------------------
drop policy if exists "Anyone can view active slots" on public.availability_slots;
create policy "Anyone can view active slots"
  on public.availability_slots for select using (is_active = true);

drop policy if exists "Tutors can manage own slots" on public.availability_slots;
create policy "Tutors can manage own slots"
  on public.availability_slots for all using (auth.uid() = tutor_id);

-- ---------------------------------------------------------------------------
-- sessions  (see OMITTED note above re: "Users see own sessions")
-- ---------------------------------------------------------------------------
drop policy if exists "Students can create sessions" on public.sessions;
create policy "Students can create sessions"
  on public.sessions for insert
  with check (auth.uid() = student_id);

-- ---------------------------------------------------------------------------
-- admin_logs
-- ---------------------------------------------------------------------------
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
