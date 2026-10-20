-- AUTH-001: Parent children support — JSONB column + normalized children table + trigger
begin;

-- Step 1: Add children_info JSONB column to profiles
alter table public.profiles
  add column if not exists children_info jsonb;

-- Step 2: Update handle_new_user trigger to carry parent role
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
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

-- Step 3: Create normalized children table
create table if not exists public.children (
  id          uuid        primary key default gen_random_uuid(),
  parent_id   uuid        not null references public.profiles(id),
  name        text        not null,
  grade_level text        not null,
  created_at  timestamptz not null default now()
);

alter table public.children enable row level security;

create policy "children_select" on public.children
  for select using (parent_id = auth.uid());

create policy "children_insert" on public.children
  for insert with check (parent_id = auth.uid());

create policy "children_update" on public.children
  for update using (parent_id = auth.uid());

create policy "children_delete" on public.children
  for delete using (parent_id = auth.uid());

-- Step 4: Sync from children_info JSONB to normalized children table
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

create trigger sync_children_on_profile_write
  after insert or update of children_info on public.profiles
  for each row execute function public.sync_children_from_profile();

commit;