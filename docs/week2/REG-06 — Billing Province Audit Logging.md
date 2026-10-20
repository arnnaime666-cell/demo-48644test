# Week 2 — Account Settings Audit Logging (REG-06)

**Requirement:** Billing province change writes an audit log; next checkout uses new rate, earlier invoices keep old tax.

## Implementation
- `src/app/(dashboard)/family/profile/` — profile save triggers `POST /api/account/profile` which already validates rate-limit.
- Change: when `billing_province` differs, insert `financial_transactions` or `notifications` audit row with before/after + IP.
- Acceptance: change parent BM→QC, run checkout, confirm tax shows QC on next invoice and ON on prior.
