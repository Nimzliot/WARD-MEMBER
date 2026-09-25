-- Migration: users now verify with ONE method (email code OR SMS code).
-- Turnout must count email-only residents too, so drop the phone_verified filter.
-- Run once in Supabase → SQL Editor (schema.sql already contains this change).

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
T