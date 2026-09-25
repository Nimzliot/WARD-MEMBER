-- =====================================================================
-- Migration 006: strict Ward Admin rules at the database level.
--   * one Ward Admin per ward      (already: a single wards.admin_user_id column)
--   * one ward per Ward Admin      (unique index below)
--   * a Ward Admin can't move their own profile to another ward
-- The Node server enforces the same rules; this makes them impossible to bypass.
-- Run once in Supabase → SQL Editor.
-- =====================================================================

create unique index if not exists wards_one_ward_per_admin
  on public.wards (admin_user_id) where admin_user_id is not null;

create or replace function public.lock_ward_admin_ward()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.ward_id is distinct from new.ward_id
     and exists (select 1 from public.wards where admin_user_id = old.id and id is distinct from new.ward_id) then
    raise exception 'A Ward Admin cannot change ward. The super admin must remove them as Ward Admin first.';
  end if;
  return new;
end $$;

drop trigger if exists profiles_lock_ward_admin on public.profiles;
create trigger profiles_lock_ward_admin
  before update of ward_id on public.profiles
  for each row execute function public.lock_ward_admin_ward();

select 'ok' as migration_006;
