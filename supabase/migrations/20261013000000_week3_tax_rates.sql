-- Week 3 — S3.1/S3.2: Tax engine (PAY-01..04, TST-01)
-- Stores Section 7.3 reference rates as data; removes hardcoded 13% from code.
-- Zero data loss; idempotent.

-- Tax rates as configurable data (Proposal Section 7.3 + Table 14)
create table if not exists public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  province text not null check (province in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT')),
  component text not null check (component in ('GST','HST','PST','QST')),
  rate numeric(6,5) not null check (rate >= 0 and rate < 1),
  applies_to text not null check (applies_to in ('session','subscription','commission')),
  effective_from date not null default '2026-01-01',
  effective_to date,
  created_at timestamptz not null default now()
);

create index if not exists idx_tax_rates_province_lookup
  on public.tax_rates (province, applies_to, effective_from);
create index if not exists idx_tax_rates_effective
  on public.tax_rates (effective_from, effective_to);

-- Sessions: add tax snapshot columns (Proposal Section 7.2 Table 12)
alter table public.sessions add column if not exists tax_province text check (tax_province in ('AB','BC','MB','NB','NL','NS','NT','NU','ON','PE','QC','SK','YT'));
alter table public.sessions add column if not exists tax_total_cents integer not null default 0 check (tax_total_cents >= 0);
alter table public.sessions add column if not exists total_cents integer;
alter table public.sessions add column if not exists gst_hst_amount_cents integer;
alter table public.sessions add column if not exists invoice_number text;
alter table public.sessions add column if not exists invoice_url text;

-- Backfill total_cents from existing price_cents where missing
update public.sessions set total_cents = price_cents where total_cents is null;

-- Seed Section 7.3 reference rates (all provinces, session + subscription where applicable)
-- Each component is a separate row so multi-component provinces (BC, MB, QC, SK) are exact.
-- RST (MB) maps to PST per spec. QST is 9.975% = 0.09975.
-- Effective from 2026-01-01; no expiry. Re-running is safe via ON CONFLICT-free insert guarded by exists.

do $$
begin
  if not exists (select 1 from public.tax_rates where province='AB' and component='GST' and applies_to='session') then
    insert into public.tax_rates (province, component, rate, applies_to, effective_from) values
      ('AB','GST',0.05000,'session','2026-01-01'),
      ('AB','GST',0.05000,'subscription','2026-01-01'),
      ('BC','GST',0.05000,'session','2026-01-01'),
      ('BC','PST',0.07000,'session','2026-01-01'),
      ('BC','GST',0.05000,'subscription','2026-01-01'),
      ('BC','PST',0.07000,'subscription','2026-01-01'),
      ('MB','GST',0.05000,'session','2026-01-01'),
      ('MB','PST',0.07000,'session','2026-01-01'),
      ('MB','GST',0.05000,'subscription','2026-01-01'),
      ('MB','PST',0.07000,'subscription','2026-01-01'),
      ('NB','HST',0.15000,'session','2026-01-01'),
      ('NB','HST',0.15000,'subscription','2026-01-01'),
      ('NL','HST',0.15000,'session','2026-01-01'),
      ('NL','HST',0.15000,'subscription','2026-01-01'),
      ('NS','HST',0.14000,'session','2026-01-01'),
      ('NS','HST',0.14000,'subscription','2026-01-01'),
      ('NT','GST',0.05000,'session','2026-01-01'),
      ('NT','GST',0.05000,'subscription','2026-01-01'),
      ('NU','GST',0.05000,'session','2026-01-01'),
      ('NU','GST',0.05000,'subscription','2026-01-01'),
      ('ON','HST',0.13000,'session','2026-01-01'),
      ('ON','HST',0.13000,'subscription','2026-01-01'),
      ('PE','HST',0.15000,'session','2026-01-01'),
      ('PE','HST',0.15000,'subscription','2026-01-01'),
      ('QC','GST',0.05000,'session','2026-01-01'),
      ('QC','QST',0.09975,'session','2026-01-01'),
      ('QC','GST',0.05000,'subscription','2026-01-01'),
      ('QC','QST',0.09975,'subscription','2026-01-01'),
      ('SK','GST',0.05000,'session','2026-01-01'),
      ('SK','PST',0.06000,'session','2026-01-01'),
      ('SK','GST',0.05000,'subscription','2026-01-01'),
      ('SK','PST',0.06000,'subscription','2026-01-01'),
      ('YT','GST',0.05000,'session','2026-01-01'),
      ('YT','GST',0.05000,'subscription','2026-01-01');
  end if;
end $$;

-- RLS: tax_rates is reference data — readable by authenticated users, writable by service role only
alter table public.tax_rates enable row level security;
drop policy if exists "Anyone can view tax rates" on public.tax_rates;
create policy "Anyone can view tax rates" on public.tax_rates for select using (true);
revoke insert, update, delete on public.tax_rates from anon, authenticated;

grant usage on schema public to anon, authenticated, service_role;
grant select on public.tax_rates to anon, authenticated;
grant all privileges on public.tax_rates to service_role;
