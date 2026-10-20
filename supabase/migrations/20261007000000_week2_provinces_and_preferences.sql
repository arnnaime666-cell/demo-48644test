-- Week 2: Provinces, billing, preferences, child provinces, tutor curricula
-- Expands from Ontario-only to 13 jurisdictions; zero data loss.

-- 1. Profiles: add billing_province, language preference, normalize province usage
alter table public.profiles add column if not exists billing_province text;
alter table public.profiles add column if not exists language_pref text check (language_pref in ('en','fr'));
alter table public.profiles add column if not exists preferred_language text check (preferred_language in ('English','French'));

-- Ensure existing rows get a sensible default without overwriting
update public.profiles set billing_province = province where billing_province is null and province is not null;
update public.profiles set language_pref = 'en' where language_pref is null;

-- Remove Ontario default from handle_new_user — keep fallback only when metadata missing
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, phone, role, province, billing_province)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    nullif(new.raw_user_meta_data->>'phone', ''),
    coalesce(new.raw_user_meta_data->>'role', 'student'),
    new.raw_user_meta_data->>'province',
    coalesce(new.raw_user_meta_data->>'billing_province', new.raw_user_meta_data->>'province')
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- 2. Children: add curriculum_province and programme columns
alter table public.children add column if not exists curriculum_province text;
alter table public.children add column if not exists programme_type text check (programme_type in ('Regular','French Immersion','Francophone','IB','AP'));
alter table public.children add column if not exists learning_goals_note text;

-- Backfill children's curriculum_province from parent province where missing
update public.children set curriculum_province = (select province from public.profiles where id = children.parent_id) where curriculum_province is null;

-- 3. Tutors: add residence_province alias (keep province col for compat), curricula, languages, credentials
alter table public.tutors add column if not exists curricula text[] default '{}';
alter table public.tutors add column if not exists teaching_languages text[] default '{}';
alter table public.tutors add column if not exists credentials jsonb default '[]'::jsonb;

-- 4. Tutor provenance for search: ensure provinces column is usable
create index if not exists idx_profiles_province on public.profiles (province);
create index if not exists idx_children_curriculum_province on public.children (curriculum_province);

-- 5. RLS: ensure new columns are readable under existing policies (no new policy needed — same table)
-- RLS already covers profiles/children; new columns inherit.

