-- =====================================================================
-- Migration 005: verified email AND mobile for every resident, and emailed
-- payment receipts. Run once in Supabase → SQL Editor (after 004).
-- schema.sql already contains this.
-- =====================================================================

-- One-time codes for adding the second contact (email or mobile) to an
-- account. Only SHA-256 hashes are stored. Written only by the Node server.
create table if not exists public.contact_otps (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  channel    text not null check (channel in ('email', 'phone')),
  target     text not null,              -- the email address or 10-digit mobile being verified
  otp_hash   text not null,
  expires_at timestamptz not null,
  attempts   int  not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists contact_otps_user_idx on public.contact_otps (user_id, channel, created_at desc);
alter table public.contact_otps enable row level security;
revoke all on public.contact_otps from anon, authenticated;

-- Payment receipts are emailed once per contribution.
alter table public.contributions
  add column if not exists receipt_sent_at timestamptz,
  add column if not exists receipt_email   text;

select 'ok' as migration_005;
