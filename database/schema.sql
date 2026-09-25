-- =====================================================================
-- Participatory Municipal Budgeting App (SDG 11) — Supabase schema
-- Run the whole file in: Supabase Dashboard → SQL Editor → New query → Run
--
-- Re-runnable: it DROPS and recreates the app tables (auth.users is untouched,
-- existing users get their profile rows back-filled at the end).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0. Clean slate
-- ---------------------------------------------------------------------
drop trigger if exists on_auth_user_created on auth.users;
drop table if exists public.votes        cascade;
drop table if exists public.budget_items cascade;
drop table if exists public.proposals    cascade;
drop table if exists public.phone_otps   cascade;
drop table if exists public.profiles     cascade;
drop table if exists public.wards        cascade;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------
create table public.wards (
  id          int primary key,
  name        text   not null unique,
  budget_pool bigint not null check (budget_pool > 0),         -- INR (whole rupees)
  voting_opens_at  timestamptz,                               -- null = already open
  voting_closes_at timestamptz,                               -- null = no deadline
  center_lat  double precision,                               -- map centre of the ward
  center_lng  double precision,
  constraint wards_window_check
    check (voting_opens_at is null or voting_closes_at is null or voting_closes_at > voting_opens_at)
);

create table public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  full_name      text,
  email          text,
  phone          text unique check (phone ~ '^[6-9][0-9]{9}$'), -- 10-digit Indian mobile
  phone_verified boolean not null default false,
  ward_id        int references public.wards(id),
  resident_id    text unique,
  role           text not null default 'resident' check (role in ('resident', 'admin')),
  created_at     timestamptz not null default now()
);

-- Only the Node server (service role) touches this table.
create table public.phone_otps (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  phone      text not null,
  otp_hash   text not null,                                   -- SHA-256 of the OTP, never the OTP itself
  expires_at timestamptz not null,
  attempts   int  not null default 0,
  created_at timestamptz not null default now()
);
create index phone_otps_user_idx on public.phone_otps (user_id, created_at desc);

create table public.proposals (
  id          uuid primary key default gen_random_uuid(),
  ward_id     int  not null references public.wards(id) on delete cascade,
  title       text not null,
  description text not null default '',
  category    text not null,
  total_cost  bigint not null default 0,                      -- kept = sum(budget_items.amount) by trigger
  status       text not null default 'approved'
               check (status in ('pending', 'approved', 'rejected')), -- only approved ones are on the ballot
  origin       text not null default 'official'
               check (origin in ('official', 'resident')),   -- resident = submitted as an idea
  submitted_by uuid references auth.users(id) on delete set null,
  review_note  text,                                          -- admin's reason (shown to the resident)
  reviewed_at  timestamptz,
  lat           double precision,                             -- map pin (optional)
  lng           double precision,
  location_name text,                                         -- e.g. "MG Road, Gandhi Nagar"
  created_at  timestamptz not null default now(),
  constraint proposals_location_check
    check ((lat is null and lng is null) or (lat between -90 and 90 and lng between -180 and 180))
);
create index proposals_ward_idx on public.proposals (ward_id, status);
create index proposals_submitted_by_idx on public.proposals (submitted_by);

create table public.budget_items (
  id          uuid primary key default gen_random_uuid(),
  proposal_id uuid   not null references public.proposals(id) on delete cascade,
  label       text   not null,
  amount      bigint not null check (amount > 0)              -- INR
);
create index budget_items_proposal_idx on public.budget_items (proposal_id);

-- Hash-chained, tamper-visible ballot box. Written ONLY by the Node server.
-- One row = one resident's ballot: every project they back, costing <= the ward pool.
create table public.votes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete set null, -- chain survives account deletion
  ward_id      int  not null references public.wards(id),
  proposal_ids uuid[] not null
               check (cardinality(proposal_ids) between 1 and 50), -- sorted; validated by the server
  voter_hash   text not null,                                 -- SHA-256(user_id + VOTE_SALT)
  prev_hash    text not null,                                 -- hash of previous ballot in ward ('0'*64 for first)
  hash         text not null unique,                          -- SHA-256(voter_hash + ids.join(',') + timestamp + prev_hash)
  created_at   timestamptz not null default now(),
  unique (user_id, ward_id),                                  -- one ballot per user per ward
  unique (ward_id, prev_hash)                                 -- chain can never fork
);
create index votes_ward_idx on public.votes (ward_id, created_at);
create index votes_proposal_ids_idx on public.votes using gin (proposal_ids);

-- ---------------------------------------------------------------------
-- 2. Functions & triggers
-- ---------------------------------------------------------------------

-- 2a. Create a profile row whenever Supabase Auth creates a user.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2b. Keep proposals.total_cost equal to the sum of its budget items.
create or replace function public.sync_proposal_total()
returns trigger language plpgsql as $$
declare pid uuid := coalesce(new.proposal_id, old.proposal_id);
begin
  update public.proposals p
     set total_cost = coalesce((select sum(amount) from public.budget_items b where b.proposal_id = pid), 0)
   where p.id = pid;
  return null;
end $$;

create trigger budget_items_sync_total
  after insert or update or delete on public.budget_items
  for each row execute function public.sync_proposal_total();

-- 2c. A resident cannot hop wards after voting (would allow a second vote).
create or replace function public.lock_ward_after_vote()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.ward_id is distinct from new.ward_id
     and exists (select 1 from public.votes where user_id = old.id) then
    raise exception 'Ward cannot be changed after you have voted';
  end if;
  return new;
end $$;

create trigger profiles_lock_ward
  before update of ward_id on public.profiles
  for each row execute function public.lock_ward_after_vote();

-- 2d. RLS helpers (security definer so policies don't recurse into profiles RLS).
create or replace function public.my_ward_id()
returns int language sql stable security definer set search_path = public as $$
  select ward_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;

-- 2e. Client RPCs (votes.user_id is hidden from clients, so these answer the two
--     questions the app needs without exposing who voted for what).

-- Which proposals are on *my* ballot in my ward? (null = not voted yet)
create or replace function public.my_vote()
returns uuid[] language sql stable security definer set search_path = public as $
  select proposal_ids from public.votes
   where user_id = auth.uid() and ward_id = public.my_ward_id()
$$;

-- Turnout for a ward: eligible (verified residents with a completed profile) vs. votes cast.
-- Users verify with ONE method (email or SMS code), and completing the profile
-- requires a session, so a completed profile means a verified resident.
create or replace function public.ward_turnout(p_ward_id int)
returns table (eligible bigint, voted bigint)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from public.profiles
      where ward_id = p_ward_id
        and full_name is not null and resident_id is not null),
    (select count(*) from public.votes where ward_id = p_ward_id)
  where p_ward_id = public.my_ward_id() or public.is_admin()
$$;

revoke execute on function public.my_vote()         from public, anon;
revoke execute on function public.ward_turnout(int) from public, anon;
grant  execute on function public.my_vote()         to authenticated;
grant  execute on function public.ward_turnout(int) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Row Level Security
--    The Node server uses the service role key, which bypasses RLS.
-- ---------------------------------------------------------------------
alter table public.wards        enable row level security;
alter table public.profiles     enable row level security;
alter table public.phone_otps   enable row level security;
alter table public.proposals    enable row level security;
alter table public.budget_items enable row level security;
alter table public.votes        enable row level security;

-- wards: any signed-in user (needed for the ward picker in profile setup)
create policy "wards: read" on public.wards
  for select to authenticated using (true);

-- profiles: read + update your own row only …
create policy "profiles: read own" on public.profiles
  for select to authenticated using (id = auth.uid());
create policy "profiles: update own" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
-- … and only these columns. phone / phone_verified / role / email are server-controlled.
revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (full_name, ward_id, resident_id) on public.profiles to authenticated;

-- phone_otps: no policies + no grants = invisible to clients.
revoke all on public.phone_otps from anon, authenticated;

-- proposals & budget items: approved ones in your ward + your own ideas (any
-- status); admins see everything. Writes go through Node.
create policy "proposals: read own ward" on public.proposals
  for select to authenticated using (
    public.is_admin()
    or (ward_id = public.my_ward_id() and (status = 'approved' or submitted_by = auth.uid())));
create policy "budget_items: read own ward" on public.budget_items
  for select to authenticated using (
    exists (select 1 from public.proposals p
             where p.id = proposal_id
               and (public.is_admin()
                    or (p.ward_id = public.my_ward_id()
                        and (p.status = 'approved' or p.submitted_by = auth.uid())))));
revoke insert, update, delete on public.proposals, public.budget_items from anon, authenticated;

-- votes: read your ward's votes, but NOT the user_id column (anonymity).
-- Clients must select explicit columns, e.g. .select('id, proposal_ids, created_at').
create policy "votes: read own ward" on public.votes
  for select to authenticated using (ward_id = public.my_ward_id() or public.is_admin());
revoke all on public.votes from anon, authenticated;
grant select (id, ward_id, proposal_ids, voter_hash, prev_hash, hash, created_at)
  on public.votes to authenticated;

-- ---------------------------------------------------------------------
-- 4. Realtime: votes (Live Results), wards + proposals (admin changes)
-- ---------------------------------------------------------------------
do $ begin
  alter publication supabase_realtime add table public.votes;
exception when duplicate_object then null;
end $;
do $ begin
  alter publication supabase_realtime add table public.wards;
exception when duplicate_object then null;
end $;
do $ begin
  alter publication supabase_realtime add table public.proposals;
exception when duplicate_object then null;
end $;

-- ---------------------------------------------------------------------
-- 5. Seed data (amounts in INR)
-- ---------------------------------------------------------------------
-- Voting opened yesterday and closes in 14 days (admins can change this in the app).
-- Sample wards are placed in Chennai (map centres).
insert into public.wards (id, name, budget_pool, voting_opens_at, voting_closes_at, center_lat, center_lng) values
  (1, 'Ward 1 – Gandhi Nagar', 7500000, now() - interval '1 day', now() + interval '14 days', 13.0067, 80.2570),  -- ₹75,00,000
  (2, 'Ward 2 – Lake View',    6000000, now() - interval '1 day', now() + interval '14 days', 12.9791, 80.2185),  -- ₹60,00,000
  (3, 'Ward 3 – Old Market',   5000000, now() - interval '1 day', now() + interval '14 days', 13.0905, 80.2870);  -- ₹50,00,000

-- helper: items are [["label", amount], ...]; total_cost is filled by the trigger
create or replace function pg_temp.add_proposal(p_ward int, p_title text, p_category text,
                                                p_desc text, p_items jsonb)
returns void language plpgsql as $$
declare pid uuid;
begin
  insert into public.proposals (ward_id, title, category, description)
  values (p_ward, p_title, p_category, p_desc) returning id into pid;

  insert into public.budget_items (proposal_id, label, amount)
  select pid, i->>0, (i->>1)::bigint from jsonb_array_elements(p_items) i;
end $$;

-- Ward 1 – Gandhi Nagar
select pg_temp.add_proposal(1, 'Resurface MG Road & Lanes 4–7', 'Roads & Transport',
  'Potholed 1.4 km stretch used by 3 schools and the weekly market. Includes side drains to stop monsoon waterlogging.',
  '[["Bituminous resurfacing (1.4 km)", 1960000], ["Storm-water side drains", 840000],
    ["Road markings & signage", 180000], ["Speed tables near school zones", 120000],
    ["Contingency (5%)", 155000]]');

select pg_temp.add_proposal(1, 'Solar LED Street Lights', 'Street Lighting',
  '120 solar LED lights on dark lanes flagged by residents as unsafe after 8 pm. Zero electricity bill.',
  '[["120 × 40W solar LED fixtures", 1740000], ["Poles & foundations", 600000],
    ["Installation & wiring", 240000], ["3-year maintenance contract", 270000]]');

select pg_temp.add_proposal(1, 'Gandhi Maidan Park Revamp', 'Parks & Environment',
  'Walking track, open-air gym and a safe play area for children, plus 300 native trees.',
  '[["Walking track (600 m, paver blocks)", 900000], ["Children''s play equipment", 650000],
    ["Open-air gym (10 stations)", 450000], ["Benches & lighting", 350000],
    ["Native tree plantation (300 saplings)", 150000]]');

select pg_temp.add_proposal(1, 'Ward Health Sub-centre Upgrade', 'Health',
  'Renovate the sub-centre and add basic diagnostics so residents avoid the 6 km trip to the district hospital.',
  '[["Building renovation", 800000], ["Diagnostic equipment (ECG, lab kit)", 700000],
    ["Medicines & supplies (1 year)", 400000], ["Solar power backup", 300000]]');

-- Ward 2 – Lake View
select pg_temp.add_proposal(2, 'Lake Desilting & Fencing', 'Parks & Environment',
  'Restore the lake''s storage capacity, stop garbage dumping, and repair the lakeside walkway.',
  '[["Desilting (approx. 12,000 m³)", 1500000], ["Chain-link fencing (1.1 km)", 880000],
    ["Walkway repair", 400000], ["Inlet silt traps & filters", 320000]]');

select pg_temp.add_proposal(2, 'Door-to-Door Segregated Waste Collection', 'Waste Management',
  'Electric collection vehicles, twin bins for every household and a ward composting unit.',
  '[["2 e-rickshaw collection vehicles", 700000], ["400 twin bins (wet/dry)", 600000],
    ["Ward composting unit", 450000], ["Awareness drive", 150000]]');

select pg_temp.add_proposal(2, 'Smart Classrooms – Govt. Primary School', 'Education',
  'Six smart classrooms and a tablet library for 600 students.',
  '[["6 interactive smart boards", 720000], ["40 student tablets", 480000],
    ["Electrical wiring & internet", 180000], ["Teacher training", 120000]]');

select pg_temp.add_proposal(2, 'Rainwater Harvesting Network', 'Water & Sanitation',
  'Recharge pits along main roads and rooftop harvesting on public buildings to lift groundwater levels.',
  '[["25 recharge pits", 1000000], ["Rooftop systems on 5 public buildings", 750000],
    ["Groundwater level monitoring", 100000]]');

-- Ward 3 – Old Market
select pg_temp.add_proposal(3, 'Market Drainage & Pavement', 'Water & Sanitation',
  'Covered drains and paved walkways for the vegetable market that floods every monsoon.',
  '[["Covered drains (800 m)", 1600000], ["Paver-block pavement", 900000],
    ["Heavy-duty manhole covers", 150000]]');

select pg_temp.add_proposal(3, 'Two Public Toilet Blocks', 'Water & Sanitation',
  'Clean, accessible toilets (separate women''s section) near the bus stand and the market.',
  '[["Construction (2 blocks)", 1400000], ["Water supply & septic system", 400000],
    ["2-year cleaning & maintenance", 360000]]');

select pg_temp.add_proposal(3, 'CCTV & Women Safety Points', 'Public Safety',
  'Cameras at 20 junctions, SOS call poles and a small monitoring room at the ward office.',
  '[["40 HD CCTV cameras", 800000], ["Monitoring room setup", 450000],
    ["SOS call poles", 300000], ["Networking & storage", 250000]]');

-- Sample proposal pins (only where no location has been set yet)
update public.proposals p set lat = v.lat, lng = v.lng, location_name = v.place
from (values
  ('Resurface MG Road & Lanes 4–7',           13.0089, 80.2552, 'MG Road, Gandhi Nagar'),
  ('Solar LED Street Lights',                 13.0041, 80.2601, 'Lanes 9–14, Gandhi Nagar'),
  ('Gandhi Maidan Park Revamp',               13.0072, 80.2598, 'Gandhi Maidan'),
  ('Ward Health Sub-centre Upgrade',          13.0053, 80.2533, 'Ward health sub-centre'),
  ('Lake Desilting & Fencing',                12.9812, 80.2176, 'Velachery lake'),
  ('Door-to-Door Segregated Waste Collection', 12.9776, 80.2205, 'Ward 2 office, Lake View'),
  ('Smart Classrooms – Govt. Primary School', 12.9765, 80.2161, 'Govt. Primary School, Lake View'),
  ('Rainwater Harvesting Network',            12.9803, 80.2221, 'Main road, Lake View'),
  ('Market Drainage & Pavement',              13.0912, 80.2878, 'Vegetable market, Old Market'),
  ('Two Public Toilet Blocks',                 13.0896, 80.2859, 'Bus stand & market'),
  ('CCTV & Women Safety Points',              13.0921, 80.2851, '20 junctions, Old Market')
) as v(title, lat, lng, place)
where p.title = v.title and p.lat is null;

-- ---------------------------------------------------------------------
-- 6. Back-fill profiles for users that existed before this script ran
-- ---------------------------------------------------------------------
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- Quick check (should show 3 wards with 4/4/3 proposals):
select w.name, count(p.id) as proposals, sum(p.total_cost) as total_asked, w.budget_pool
from public.wards w left join public.proposals p on p.ward_id = w.id
group by w.id order by w.id;
