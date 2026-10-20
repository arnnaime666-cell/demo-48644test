-- REV-001: Reviews table for post-session student ratings
begin;

create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references public.sessions(id) on delete cascade,
  tutor_id    uuid not null references public.tutors(id) on delete cascade,
  student_id  uuid not null references public.profiles(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);

-- One review per student per session
create unique index if not exists reviews_session_student_unique
  on public.reviews (session_id, student_id);

-- Fast lookup of all reviews for a tutor
create index if not exists reviews_tutor_id_idx on public.reviews (tutor_id);

-- Keep tutors.rating_avg in sync after each insert/update/delete on reviews
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

commit;
