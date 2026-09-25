-- =====================================================================
-- Migration 002: voting window, resident ideas, split (multi-project) ballots
-- Run once in Supabase → SQL Editor. schema.sql already contains all of this.
-- Safe for existing data: current votes become one-project ballots and their
-- hashes stay valid (a one-id ballot hashes exactly like the old single vote).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Wards: voting window (null opens = already open, null closes = no deadline)
-- ---------------------------------------------------------------------
alter table public.wards
  add column if not exists voting_opens_at  timestamptz,
  add column if not exists voting_closes_at timestamptz;

update public.wards
   set voting_opens_at  = coalesce(voting_opens_at,  now() - interval '1 day'),
       voting_closes_at = coalesce(voting_closes_at, now() + interval '14 days');

alter table public.wards drop constraint if exists wards_window_check;
alter table public.wards add constraint wards_window_check
  check (voting_opens_at is null or voting_closes_at is null or voting_closes_at > voting_opens_at);

-- ---------------------------------------------------------------------
-- 2. Proposals: resident ideas go through admin review
-- ---------------------------------------------------------------------
alter table public.proposals
  add column if not exists status       text not null default 'approved',
  add column if not exists origin       text not null default 'official',
  add column if not exists submitted_by uuid references auth.users(id) on delete set null,
  add column if not exists review_note  text,
  add column if not exists reviewed_at  timestamptz;

alter table public.proposals drop constraint if exists proposals_status_check;
alter table public.proposals add constraint proposals_status_check
  check (status in ('pending', 'approved', 'rejected'));
alter table public.proposals drop constraint if exists proposals_origin_check;
alter table public.proposals add constraint proposals_origin_check
  check (origin in ('official', 'resident'));

create index if not exists proposals_status_idx on public.proposals (ward_id, status);
create index if not exists proposals_submitted_by_idx on public.proposals (submitted_by);

-- ---------------------------------------------------------------------
-- 3. Votes → ballots: one row per resident, holding every project they back
-- ---------------------------------------------------------------------
alter table public.votes add column if not exists proposal_ids uuid[];

do $$ begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'votes' and column_name = 'proposal_id') then
    update public.votes set proposal_ids = array[proposal_id] where proposal_ids is null;
    alter table public.votes drop column proposal_id;   -- also drops the old FK
  end if;
end $$;

alter table public.votes alter column proposal_ids set not null;
alter table public.votes drop constraint if exists votes_ballot_size;
alter table public.votes add constraint votes_ballot_size
  check (cardinality(proposal_ids) between 1 and 50);
create index if not exists votes_proposal_ids_idx on public.votes using gin (proposal_ids);

-- Column grants: votes.user_id stays hidden from clients.
revoke all on public.votes from anon, authenticated;
grant select (id, ward_id, proposal_ids, voter_hash, prev_hash, hash, created_at)
  on public.votes to authenticated;

-- my_vote() now returns the caller's whole ballot (null = not voted yet)
drop function if exists public.my_vote();
create function public.my_vote()
returns uuid[] language sql stable security definer set search_path = public as $$
  select proposal_ids from public.votes
   where user_id = auth.uid() and ward_id = public.my_ward_id()
$$;
revoke execute on function public.my_vote() from public, anon;
grant  execute on function public.my_vote() to authenticated;

-- ---------------------------------------------------------------------
-- 4. RLS: residents see approved proposals + their own ideas (any status)
-- ---------------------------------------------------------------------
drop policy if exists "proposals: read own ward" on public.proposals;
create policy "proposals: read own ward" on public.proposals
  for select to authenticated using (
    public.is_admin()
    or (ward_id = public.my_ward_id() and (status = 'approved' or submitted_by = auth.uid())));

drop policy if exists "budget_items: read own ward" on public.budget_items;
create policy "budget_items: read own ward" on public.budget_items
  for select to authenticated using (
    exists (select 1 from public.proposals p
             where p.id = proposal_id
               and (public.is_admin()
                    or (p.ward_id = public.my_ward_id()
                        and (p.status = 'approved' or p.submitted_by = auth.uid())))));

-- ---------------------------------------------------------------------
-- 5. Realtime: admin changes (window, approvals, edits) reach phones instantly
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.wards;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.proposals;
exception when duplicate_object then null;
end $$;

-- Check: every ward has a window, every vote is a ballot
select w.name, w.voting_opens_at, w.voting_closes_at,
       (select count(*) from public.proposals p where p.ward_id = w.id and p.status = 'approved') as on_ballot,
       (select count(*) from public.votes v where v.ward_id = w.id) as ballots
from public.wards w order by w.id;
