-- PAR-001: Update handle_new_user trigger to include province column
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
    new.raw_user_meta_data->>'province'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;