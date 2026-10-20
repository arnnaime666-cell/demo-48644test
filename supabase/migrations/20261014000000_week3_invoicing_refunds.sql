-- INV-06: Record refunds linked to original invoice and proportional tax
-- Each refund is an audit-logged correction; report it via the province + financial report slices.

create table if not exists public.refund_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  invoice_number text not null,
  stripe_refund_id text,
  refund_subtotal_cents integer not null check (refund_subtotal_cents >= 0),
  refund_tax_cents integer not null check (refund_tax_cents >= 0),
  refund_total_cents integer not null check (refund_total_cents >= 0),
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_refund_records_session on public.refund_records (session_id);
create index if not exists idx_refund_records_invoice on public.refund_records (invoice_number);

alter table public.refund_records enable row level security;
drop policy if exists "Admins manage refunds" on public.refund_records;
create policy "Admins manage refunds" on public.refund_records for all using (
  exists (select 1 from public.profiles where id = auth.uid() and role='admin')
);
revoke all on public.refund_records from anon, authenticated;
grant select, insert, update on public.refund_records to authenticated;
grant all on public.refund_records to service_role;
