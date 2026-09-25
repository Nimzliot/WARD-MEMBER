-- =====================================================================
-- Migration 003: map locations for wards and proposals / ideas
-- Run once in Supabase → SQL Editor. schema.sql already contains this.
-- Sample wards are placed in Chennai; admins can move any pin in the app.
-- =====================================================================

alter table public.wards
  add column if not exists center_lat double precision,
  add column if not exists center_lng double precision;

alter table public.proposals
  add column if not exists lat           double precision,
  add column if not exists lng           double precision,
  add column if not exists location_name text;

alter table public.proposals drop constraint if exists proposals_location_check;
alter table public.proposals add constraint proposals_location_check
  check ((lat is null and lng is null)
      or (lat between -90 and 90 and lng between -180 and 180));

-- Ward centres (map opens here)
update public.wards set center_lat = 13.0067, center_lng = 80.2570 where id = 1 and center_lat is null; -- Gandhi Nagar, Adyar
update public.wards set center_lat = 12.9791, center_lng = 80.2185 where id = 2 and center_lat is null; -- Velachery lake
update public.wards set center_lat = 13.0905, center_lng = 80.2870 where id = 3 and center_lat is null; -- George Town market

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

select w.name, w.center_lat, w.center_lng,
       count(p.id) filter (where p.lat is not null) as pinned,
       count(p.id) as proposals
from public.wards w left join public.proposals p on p.ward_id = w.id
group by w.id order by w.id;
