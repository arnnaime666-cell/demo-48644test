-- Supabase Data API access hardening.
-- New Supabase projects stop exposing public-schema tables to the Data API by
-- default on 2026-05-30; existing projects follow on 2026-10-30.
-- Keep table privileges explicit and let RLS policies remain the behavioral gate.

begin;

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

commit;
