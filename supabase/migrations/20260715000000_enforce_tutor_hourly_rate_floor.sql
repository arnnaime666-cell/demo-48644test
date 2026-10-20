-- TUT-009 BR-1: reject tutor hourly rates below $20 CAD.
-- NOT VALID preserves any legacy rows for an explicit remediation pass while
-- still enforcing the floor for every new insert and update.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'tutors_hourly_rate_minimum'
      and conrelid = 'public.tutors'::regclass
  ) then
    alter table public.tutors
      add constraint tutors_hourly_rate_minimum
      check (hourly_rate >= 2000) not valid;
  end if;
end
$$;

comment on constraint tutors_hourly_rate_minimum on public.tutors is
  'TUT-009 BR-1: tutor hourly rates must be at least $20 CAD (2000 cents).';
