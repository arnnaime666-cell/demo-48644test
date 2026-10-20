-- REV-001: Row-level security for reviews table
begin;

alter table public.reviews enable row level security;

-- Anyone (logged in or anon) can read reviews
create policy "reviews_select_public"
  on public.reviews
  for select
  using (true);

-- Students can insert a review only for their own session
create policy "reviews_insert_own"
  on public.reviews
  for insert
  with check (student_id = auth.uid());

commit;
