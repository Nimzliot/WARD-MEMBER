-- =====================================================================
-- Migration 004: one Ward Admin per ward, fundraising (Razorpay), and
-- end-to-end encrypted resident ↔ Ward Admin chat.
-- Run once in Supabase → SQL Editor. schema.sql already contains this.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Ward Admin: exactly one person per ward (a single column = one at a time)
-- ---------------------------------------------------------------------
alter table public.wards
  add column if not exists admin_user_id uuid references auth.users(id) on delete set null;

-- Public half of each user's chat key (X25519, base64). The private half never
-- leaves the phone. Written only by the Node server.
alter table public.profiles
  add column if not exists chat_public_key text;

create or replace function public.is_ward_admin(p_ward_id int)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.wards where id = p_ward_id and admin_user_id = auth.uid())
$$;
revoke execute on function public.is_ward_admin(int) from public, anon;
grant  execute on function public.is_ward_admin(int) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Fundraising campaigns + contributions (Razorpay test mode)
-- ---------------------------------------------------------------------
create table if not exists public.campaigns (
  id          uuid primary key default gen_random_uuid(),
  ward_id     int  not null references public.wards(id) on delete cascade,
  title       text not null,
  description text not null default '',
  goal        bigint not null check (goal > 0),                  -- INR
  proposal_id uuid references public.proposals(id) on delete set null,
  closes_at   timestamptz,
  status      text not null default 'active' check (status in ('active', 'closed')),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists campaigns_ward_idx on public.campaigns (ward_id, status);

create table if not exists public.contributions (
  id                  uuid primary key default gen_random_uuid(),
  campaign_id         uuid not null references public.campaigns(id) on delete cascade,
  user_id             uuid references auth.users(id) on delete set null,
  amount              bigint not null check (amount >= 1),           -- INR
  anonymous           boolean not null default false,
  status              text not null default 'created' check (status in ('created', 'paid', 'failed', 'expired')),
  razorpay_link_id    text unique,
  razorpay_payment_id text unique,
  created_at          timestamptz not null default now(),
  paid_at             timestamptz
);
create index if not exists contributions_campaign_idx on public.contributions (campaign_id, status);

alter table public.campaigns     enable row level security;
alter table public.contributions enable row level security;

drop policy if exists "campaigns: read own ward" on public.campaigns;
create policy "campaigns: read own ward" on public.campaigns
  for select to authenticated using (ward_id = public.my_ward_id() or public.is_admin());
drop policy if exists "contributions: read own" on public.contributions;
create policy "contributions: read own" on public.contributions
  for select to authenticated using (user_id = auth.uid() or public.is_admin());
revoke insert, update, delete on public.campaigns, public.contributions from anon, authenticated;

-- ---------------------------------------------------------------------
-- 3. E2E chat: the server only ever stores ciphertext
-- ---------------------------------------------------------------------
create table if not exists public.chat_threads (
  id               uuid primary key default gen_random_uuid(),
  ward_id          int  not null references public.wards(id) on delete cascade,
  resident_id      uuid not null references auth.users(id) on delete cascade,
  last_message_at  timestamptz,
  unread_admin     int not null default 0,
  unread_resident  int not null default 0,
  created_at       timestamptz not null default now(),
  unique (ward_id, resident_id)
);

create table if not exists public.chat_messages (
  id            uuid primary key default gen_random_uuid(),
  thread_id     uuid not null references public.chat_threads(id) on delete cascade,
  sender_id     uuid references auth.users(id) on delete set null,
  ciphertext    text not null,   -- base64(AES-256-GCM ciphertext + tag)
  nonce         text not null,   -- base64, 12 bytes
  sender_key    text not null,   -- sender's X25519 public key used
  recipient_key text not null,   -- recipient's X25519 public key used
  created_at    timestamptz not null default now(),
  read_at       timestamptz
);
create index if not exists chat_messages_thread_idx on public.chat_messages (thread_id, created_at);

-- A thread belongs to its resident and to the ward's current admin.
create or replace function public.can_access_thread(p_thread_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_threads t
    left join public.wards w on w.id = t.ward_id
    where t.id = p_thread_id and (t.resident_id = auth.uid() or w.admin_user_id = auth.uid()))
$$;
revoke execute on function public.can_access_thread(uuid) from public, anon;
grant  execute on function public.can_access_thread(uuid) to authenticated;

alter table public.chat_threads  enable row level security;
alter table public.chat_messages enable row level security;

drop policy if exists "chat_threads: members" on public.chat_threads;
create policy "chat_threads: members" on public.chat_threads
  for select to authenticated using (resident_id = auth.uid() or public.is_ward_admin(ward_id));
drop policy if exists "chat_messages: members" on public.chat_messages;
create policy "chat_messages: members" on public.chat_messages
  for select to authenticated using (public.can_access_thread(thread_id));
revoke insert, update, delete on public.chat_threads, public.chat_messages from anon, authenticated;

-- Live updates
do $$ begin alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.chat_threads;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.contributions;
exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.campaigns;
exception when duplicate_object then null; end $$;

select 'ok' as migration_004,
       (select count(*) from public.wards where admin_user_id is not null) as wards_with_admin;
