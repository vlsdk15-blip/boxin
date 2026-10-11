-- 박스인(BoxIn) v0.1 — MVP schema
-- Tables: brands, centers, profiles, memberships, pass_products, passes,
--         pass_holds, classes, bookings, attendances, kiosk_devices,
--         payments, product_transfers
-- Every center-owned table carries center_id and is isolated with RLS.
-- Member-facing writes that need server-side checks (check-in, booking,
-- kiosk check-in, payment verification, transfer acceptance) are NOT opened
-- here; they arrive as RPC / Edge Functions in later migrations.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.member_role as enum ('member', 'coach', 'admin');
create type public.pass_type as enum ('period', 'count');
create type public.pass_status as enum ('active', 'paused', 'expired', 'cancelled');
create type public.hold_status as enum ('requested', 'approved', 'rejected', 'cancelled');
create type public.class_kind as enum ('crossfit', 'hyrox');
create type public.booking_status as enum ('booked', 'waitlisted', 'cancelled');
create type public.attendance_method as enum ('app', 'location', 'kiosk', 'coach');
create type public.payment_method as enum ('in_app', 'on_site');
create type public.payment_status as enum ('pending', 'paid', 'cancelled', 'refunded');
create type public.transfer_status as enum ('pending', 'accepted', 'rejected');

-- Helpers used by RLS policies live outside the API-exposed schema.
create schema if not exists private;

-- Phones are stored in Korean domestic digits form (01012345678) so that
-- auth phones (+821012345678), coach input (010-1234-5678) and kiosk lookups
-- all compare equal.
create function private.normalize_phone(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when d = '' then null
    when d like '82%' then '0' || substr(d, 3)
    else d
  end
  from (select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') as d) s
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- A person. Not keyed by auth.users so a coach can register a member (name +
-- phone) before that member ever installs the app; user_id is linked when
-- they sign up with the same phone number.
create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users (id) on delete set null,
  name text not null default '',
  phone text check (phone ~ '^0[0-9]{8,10}$'),
  phone_last4 text generated always as (right(phone, 4)) stored,
  push_token text,
  created_at timestamptz not null default now()
);
create unique index profiles_phone_key on public.profiles (phone) where phone is not null;
create index profiles_phone_last4_idx on public.profiles (phone_last4);

-- Chain (optional). A center without brand_id is a standalone center.
create table public.brands (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.centers (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid references public.brands (id) on delete set null,
  name text not null,
  address text,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  attendance_radius_m integer not null default 100 check (attendance_radius_m > 0),
  timezone text not null default 'Asia/Seoul',
  created_at timestamptz not null default now()
);
create index centers_brand_id_idx on public.centers (brand_id);

-- Center membership; role is per center (coach at A, member at B).
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role public.member_role not null default 'member',
  member_no text,
  memo text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (center_id, profile_id),
  unique (center_id, member_no)
);
create index memberships_profile_id_idx on public.memberships (profile_id);

create table public.pass_products (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  name text not null,
  type public.pass_type not null,
  duration_days integer check (duration_days > 0),       -- period passes
  count integer check (count > 0),                       -- count passes
  usage_expiry_days integer check (usage_expiry_days > 0), -- count passes: use within N days
  price integer not null check (price >= 0),             -- KRW
  source_product_id uuid references public.pass_products (id) on delete set null, -- set when received from another branch
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, center_id),
  constraint pass_products_type_fields check (
    (type = 'period' and duration_days is not null and count is null and usage_expiry_days is null)
    or (type = 'count' and count is not null and usage_expiry_days is not null and duration_days is null)
  )
);
create index pass_products_center_id_idx on public.pass_products (center_id);

-- An issued pass. Both pass types end on end_date (period: start + duration,
-- count: start + usage expiry), so expiry notices and hold extensions work
-- the same way for both.
create table public.passes (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  profile_id uuid not null references public.profiles (id),
  product_id uuid not null,
  start_date date not null,
  end_date date not null,
  remaining_count integer check (remaining_count >= 0), -- null for period passes
  status public.pass_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (id, center_id),
  check (end_date >= start_date),
  foreign key (product_id, center_id) references public.pass_products (id, center_id),
  foreign key (center_id, profile_id) references public.memberships (center_id, profile_id)
);
create index passes_center_profile_idx on public.passes (center_id, profile_id);
create index passes_active_end_date_idx on public.passes (end_date) where status = 'active';

create table public.pass_holds (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  pass_id uuid not null,
  start_date date not null,
  end_date date not null,
  requested_by uuid not null references public.profiles (id),
  status public.hold_status not null default 'requested',
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  foreign key (pass_id, center_id) references public.passes (id, center_id) on delete cascade
);
create index pass_holds_pass_id_idx on public.pass_holds (pass_id);
create index pass_holds_center_status_idx on public.pass_holds (center_id, status);

-- One row per class session. Recurring classes are expanded into rows that
-- share a series_id. booked_count is kept by trigger so remaining seats can
-- be shown (and streamed over Realtime) without exposing other bookings.
create table public.classes (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  coach_id uuid references public.profiles (id) on delete set null,
  series_id uuid,
  title text,
  kind public.class_kind not null default 'crossfit',
  starts_at timestamptz not null,
  duration_min integer not null default 60 check (duration_min > 0),
  capacity integer not null check (capacity > 0),
  booked_count integer not null default 0,
  created_at timestamptz not null default now(),
  unique (id, center_id)
);
create index classes_center_starts_at_idx on public.classes (center_id, starts_at);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  class_id uuid not null,
  profile_id uuid not null references public.profiles (id),
  status public.booking_status not null default 'booked',
  created_at timestamptz not null default now(),
  cancelled_at timestamptz,
  foreign key (class_id, center_id) references public.classes (id, center_id) on delete cascade,
  foreign key (center_id, profile_id) references public.memberships (center_id, profile_id)
);
create unique index bookings_one_live_per_class on public.bookings (class_id, profile_id)
  where status <> 'cancelled';
create index bookings_profile_id_idx on public.bookings (profile_id);
-- waitlist order = created_at among status 'waitlisted'
create index bookings_class_status_idx on public.bookings (class_id, status, created_at);

create table public.kiosk_devices (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  name text not null,
  token_hash text not null unique, -- sha256 of the device token; the raw token is shown once at registration
  last_used_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index kiosk_devices_center_id_idx on public.kiosk_devices (center_id);

create table public.attendances (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  profile_id uuid not null references public.profiles (id),
  class_id uuid,
  pass_id uuid,
  attended_at timestamptz not null default now(),
  attended_on date not null default ((now() at time zone 'Asia/Seoul')::date), -- center-local day
  method public.attendance_method not null,
  kiosk_device_id uuid references public.kiosk_devices (id) on delete set null,
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (class_id, center_id) references public.classes (id, center_id),
  foreign key (pass_id, center_id) references public.passes (id, center_id),
  foreign key (center_id, profile_id) references public.memberships (center_id, profile_id)
);
-- No double check-in: once per class, and once per day for open-gym check-ins.
create unique index attendances_one_per_class on public.attendances (class_id, profile_id)
  where class_id is not null;
create unique index attendances_one_per_day on public.attendances (center_id, profile_id, attended_on)
  where class_id is null;
create index attendances_center_day_idx on public.attendances (center_id, attended_on);
create index attendances_profile_idx on public.attendances (profile_id, attended_at desc);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references public.centers (id) on delete cascade,
  profile_id uuid not null references public.profiles (id),
  product_id uuid,
  pass_id uuid, -- filled once the pass is issued (after PG verification for in-app payments)
  amount integer not null check (amount >= 0), -- KRW
  method public.payment_method not null,
  pg_provider text,           -- e.g. 'portone'
  pg_tx_id text unique,       -- PG transaction id
  status public.payment_status not null default 'pending',
  paid_at timestamptz,
  recorded_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (product_id, center_id) references public.pass_products (id, center_id),
  foreign key (pass_id, center_id) references public.passes (id, center_id),
  foreign key (center_id, profile_id) references public.memberships (center_id, profile_id)
);
create index payments_center_paid_at_idx on public.payments (center_id, paid_at);
create index payments_profile_id_idx on public.payments (profile_id);

-- A head coach sends a pass product to another branch of the same brand; on
-- acceptance it is copied there (created_product_id) and priced independently.
create table public.product_transfers (
  id uuid primary key default gen_random_uuid(),
  from_center_id uuid not null references public.centers (id) on delete cascade,
  to_center_id uuid not null references public.centers (id) on delete cascade,
  product_id uuid not null,
  status public.transfer_status not null default 'pending',
  created_product_id uuid references public.pass_products (id) on delete set null,
  requested_by uuid references public.profiles (id) on delete set null,
  decided_by uuid references public.profiles (id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  check (from_center_id <> to_center_id),
  foreign key (product_id, from_center_id) references public.pass_products (id, center_id) on delete cascade
);
create index product_transfers_to_center_idx on public.product_transfers (to_center_id, status);
create index product_transfers_from_center_idx on public.product_transfers (from_center_id);

-- ---------------------------------------------------------------------------
-- RLS helper functions (security definer so policies do not recurse)
-- ---------------------------------------------------------------------------
create function private.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from public.profiles where user_id = (select auth.uid())
$$;

create function private.has_center_role(p_center_id uuid, p_roles public.member_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.profiles p on p.id = m.profile_id
    where m.center_id = p_center_id
      and p.user_id = (select auth.uid())
      and m.is_active
      and m.role = any (p_roles)
  )
$$;

create function private.is_center_member(p_center_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.has_center_role(p_center_id, array['member', 'coach', 'admin']::public.member_role[])
$$;

create function private.is_center_staff(p_center_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.has_center_role(p_center_id, array['coach', 'admin']::public.member_role[])
$$;

create function private.is_center_admin(p_center_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select private.has_center_role(p_center_id, array['admin']::public.member_role[])
$$;

-- True when the caller is coach/admin at any center the given person belongs to.
create function private.is_staff_of_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships target
    join public.memberships mine on mine.center_id = target.center_id
    join public.profiles me on me.id = mine.profile_id
    where target.profile_id = p_profile_id
      and me.user_id = (select auth.uid())
      and mine.is_active
      and mine.role in ('coach', 'admin')
  )
$$;

create function private.same_brand(p_center_a uuid, p_center_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.centers a
    join public.centers b on b.brand_id = a.brand_id
    where a.id = p_center_a and b.id = p_center_b and a.brand_id is not null
  )
$$;

grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Link or create a profile when an auth user appears. Phone sign-ups are
-- linked only once the phone is verified, so nobody can claim a
-- coach-registered profile by merely requesting an OTP for that number.
create function private.handle_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone(new.phone);
begin
  if exists (select 1 from public.profiles where user_id = new.id) then
    return new;
  end if;

  if v_phone is not null then
    if new.phone_confirmed_at is null then
      return new;
    end if;
    update public.profiles set user_id = new.id
      where phone = v_phone and user_id is null;
    if found then
      return new;
    end if;
  end if;

  insert into public.profiles (user_id, name, phone)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''), v_phone);
  return new;
end;
$$;

create trigger on_auth_user_changed
  after insert or update of phone, phone_confirmed_at on auth.users
  for each row execute function private.handle_auth_user();

-- Keep classes.booked_count equal to the number of 'booked' bookings.
create function private.sync_class_booked_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update public.classes c
      set booked_count = (select count(*) from public.bookings b
                          where b.class_id = c.id and b.status = 'booked')
      where c.id = old.class_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update public.classes c
      set booked_count = (select count(*) from public.bookings b
                          where b.class_id = c.id and b.status = 'booked')
      where c.id = new.class_id;
  end if;
  return null;
end;
$$;

create trigger bookings_sync_booked_count
  after insert or update of status, class_id or delete on public.bookings
  for each row execute function private.sync_class_booked_count();

-- Only the brand owner may attach a center to a brand (signed-in callers;
-- service role / SQL editor are not restricted).
create function private.guard_center_brand()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.brand_id is not null
     and (tg_op = 'INSERT' or new.brand_id is distinct from old.brand_id)
     and (select auth.uid()) is not null
     and not exists (
       select 1 from public.brands b
       where b.id = new.brand_id and b.owner_id = private.current_profile_id()
     )
  then
    raise exception 'only the brand owner can attach a center to a brand';
  end if;
  return new;
end;
$$;

create trigger centers_guard_brand
  before insert or update of brand_id on public.centers
  for each row execute function private.guard_center_brand();

-- ---------------------------------------------------------------------------
-- RPCs needed to bootstrap a center
-- ---------------------------------------------------------------------------

-- Creates a center and makes the caller its admin.
create function public.create_center(
  p_name text,
  p_address text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_attendance_radius_m integer default 100
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := private.current_profile_id();
  v_center_id uuid;
begin
  if v_profile_id is null then
    raise exception 'not signed in';
  end if;

  insert into public.centers (name, address, latitude, longitude, attendance_radius_m)
  values (p_name, p_address, p_latitude, p_longitude, p_attendance_radius_m)
  returning id into v_center_id;

  insert into public.memberships (center_id, profile_id, role)
  values (v_center_id, v_profile_id, 'admin');

  return v_center_id;
end;
$$;

-- Coach/admin registers a member by name + phone. Reuses the existing profile
-- when that phone is already known (e.g. a member of another center).
create function public.register_member(
  p_center_id uuid,
  p_name text,
  p_phone text,
  p_member_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_phone(p_phone);
  v_profile_id uuid;
  v_membership_id uuid;
begin
  if not private.is_center_staff(p_center_id) then
    raise exception 'not allowed';
  end if;
  if v_phone is null then
    raise exception 'phone is required';
  end if;

  select id into v_profile_id from public.profiles where phone = v_phone;
  if v_profile_id is null then
    insert into public.profiles (name, phone) values (p_name, v_phone)
    returning id into v_profile_id;
  end if;

  insert into public.memberships (center_id, profile_id, role, member_no)
  values (p_center_id, v_profile_id, 'member', p_member_no)
  on conflict (center_id, profile_id) do nothing
  returning id into v_membership_id;

  if v_membership_id is null then
    select id into v_membership_id from public.memberships
    where center_id = p_center_id and profile_id = v_profile_id;
  end if;

  return v_membership_id;
end;
$$;

revoke execute on function public.create_center(text, text, double precision, double precision, integer) from public, anon;
revoke execute on function public.register_member(uuid, text, text, text) from public, anon;
grant execute on function public.create_center(text, text, double precision, double precision, integer) to authenticated;
grant execute on function public.register_member(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Privileges + Row Level Security
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- A signed-in user may only edit their own display name and push token;
-- phone / user_id change through server-side flows.
revoke insert, update, delete on public.profiles from authenticated;
grant update (name, push_token) on public.profiles to authenticated;
-- Kiosk token hashes are never readable from the client.
revoke select on public.kiosk_devices from authenticated;
grant select (id, center_id, name, last_used_at, revoked_at, created_by, created_at)
  on public.kiosk_devices to authenticated;

alter table public.profiles enable row level security;
alter table public.brands enable row level security;
alter table public.centers enable row level security;
alter table public.memberships enable row level security;
alter table public.pass_products enable row level security;
alter table public.passes enable row level security;
alter table public.pass_holds enable row level security;
alter table public.classes enable row level security;
alter table public.bookings enable row level security;
alter table public.attendances enable row level security;
alter table public.kiosk_devices enable row level security;
alter table public.payments enable row level security;
alter table public.product_transfers enable row level security;

-- profiles: yourself, or people in a center where you are coach/admin
create policy profiles_select on public.profiles for select to authenticated
  using (user_id = (select auth.uid()) or private.is_staff_of_profile(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- brands: readable by any signed-in user; managed by the owner
create policy brands_select on public.brands for select to authenticated
  using (true);
create policy brands_insert on public.brands for insert to authenticated
  with check (owner_id = private.current_profile_id());
create policy brands_update on public.brands for update to authenticated
  using (owner_id = private.current_profile_id())
  with check (owner_id = private.current_profile_id());
create policy brands_delete on public.brands for delete to authenticated
  using (owner_id = private.current_profile_id());

-- centers: listed to any signed-in user (center picker); edited by its admin.
-- Creation goes through create_center().
create policy centers_select on public.centers for select to authenticated
  using (true);
create policy centers_update on public.centers for update to authenticated
  using (private.is_center_admin(id))
  with check (private.is_center_admin(id));

-- memberships: your own rows, or all rows of a center you staff.
-- Coaches manage plain members; only admins grant coach/admin or remove people.
create policy memberships_select on public.memberships for select to authenticated
  using (profile_id = private.current_profile_id() or private.is_center_staff(center_id));
create policy memberships_insert on public.memberships for insert to authenticated
  with check (
    private.is_center_admin(center_id)
    or (role = 'member' and private.is_center_staff(center_id))
  );
create policy memberships_update on public.memberships for update to authenticated
  using (
    private.is_center_admin(center_id)
    or (role = 'member' and private.is_center_staff(center_id))
  )
  with check (
    private.is_center_admin(center_id)
    or (role = 'member' and private.is_center_staff(center_id))
  );
create policy memberships_delete on public.memberships for delete to authenticated
  using (private.is_center_admin(center_id));

-- pass_products: visible to the center's people; managed by admin
create policy pass_products_select on public.pass_products for select to authenticated
  using (private.is_center_member(center_id));
create policy pass_products_insert on public.pass_products for insert to authenticated
  with check (private.is_center_admin(center_id));
create policy pass_products_update on public.pass_products for update to authenticated
  using (private.is_center_admin(center_id))
  with check (private.is_center_admin(center_id));
create policy pass_products_delete on public.pass_products for delete to authenticated
  using (private.is_center_admin(center_id));

-- passes: your own, or your center's as coach/admin; sold/extended by staff
create policy passes_select on public.passes for select to authenticated
  using (profile_id = private.current_profile_id() or private.is_center_staff(center_id));
create policy passes_insert on public.passes for insert to authenticated
  with check (private.is_center_staff(center_id));
create policy passes_update on public.passes for update to authenticated
  using (private.is_center_staff(center_id))
  with check (private.is_center_staff(center_id));
create policy passes_delete on public.passes for delete to authenticated
  using (private.is_center_admin(center_id));

-- pass_holds: member requests for own pass; staff approve or set directly
create policy pass_holds_select on public.pass_holds for select to authenticated
  using (
    requested_by = private.current_profile_id()
    or private.is_center_staff(center_id)
    or exists (select 1 from public.passes p
               where p.id = pass_id and p.profile_id = private.current_profile_id())
  );
create policy pass_holds_insert on public.pass_holds for insert to authenticated
  with check (
    private.is_center_staff(center_id)
    or (
      status = 'requested'
      and requested_by = private.current_profile_id()
      and decided_by is null
      and exists (select 1 from public.passes p
                  where p.id = pass_id and p.profile_id = private.current_profile_id())
    )
  );
create policy pass_holds_update_staff on public.pass_holds for update to authenticated
  using (private.is_center_staff(center_id))
  with check (private.is_center_staff(center_id));
create policy pass_holds_cancel_own on public.pass_holds for update to authenticated
  using (requested_by = private.current_profile_id() and status = 'requested')
  with check (requested_by = private.current_profile_id() and status = 'cancelled' and decided_by is null);
create policy pass_holds_delete on public.pass_holds for delete to authenticated
  using (private.is_center_staff(center_id));

-- classes: visible to the center's people; managed by staff
create policy classes_select on public.classes for select to authenticated
  using (private.is_center_member(center_id));
create policy classes_insert on public.classes for insert to authenticated
  with check (private.is_center_staff(center_id));
create policy classes_update on public.classes for update to authenticated
  using (private.is_center_staff(center_id))
  with check (private.is_center_staff(center_id));
create policy classes_delete on public.classes for delete to authenticated
  using (private.is_center_staff(center_id));

-- bookings: your own, or your center's as staff. Staff may book on behalf;
-- member self-booking goes through a capacity-checking RPC (next migration).
create policy bookings_select on public.bookings for select to authenticated
  using (profile_id = private.current_profile_id() or private.is_center_staff(center_id));
create policy bookings_insert on public.bookings for insert to authenticated
  with check (private.is_center_staff(center_id));
create policy bookings_update on public.bookings for update to authenticated
  using (private.is_center_staff(center_id))
  with check (private.is_center_staff(center_id));
create policy bookings_delete on public.bookings for delete to authenticated
  using (private.is_center_staff(center_id));

-- attendances: your own, or your center's as staff. Staff may record directly;
-- app / location / kiosk check-ins go through the single check-in function.
create policy attendances_select on public.attendances for select to authenticated
  using (profile_id = private.current_profile_id() or private.is_center_staff(center_id));
create policy attendances_insert on public.attendances for insert to authenticated
  with check (private.is_center_staff(center_id) and method = 'coach');
create policy attendances_update on public.attendances for update to authenticated
  using (private.is_center_staff(center_id))
  with check (private.is_center_staff(center_id));
create policy attendances_delete on public.attendances for delete to authenticated
  using (private.is_center_staff(center_id));

-- kiosk_devices: admin only (registration itself is done server-side)
create policy kiosk_devices_select on public.kiosk_devices for select to authenticated
  using (private.is_center_admin(center_id));
create policy kiosk_devices_update on public.kiosk_devices for update to authenticated
  using (private.is_center_admin(center_id))
  with check (private.is_center_admin(center_id));
create policy kiosk_devices_delete on public.kiosk_devices for delete to authenticated
  using (private.is_center_admin(center_id));

-- payments: your own, or everything as admin. Staff may record on-site sales;
-- in-app payments are written by the server after PG verification.
create policy payments_select on public.payments for select to authenticated
  using (profile_id = private.current_profile_id() or private.is_center_admin(center_id));
create policy payments_insert on public.payments for insert to authenticated
  with check (private.is_center_staff(center_id) and method = 'on_site');
create policy payments_update on public.payments for update to authenticated
  using (private.is_center_admin(center_id))
  with check (private.is_center_admin(center_id));
create policy payments_delete on public.payments for delete to authenticated
  using (private.is_center_admin(center_id) and method = 'on_site');

-- product_transfers: admins of either branch can see; sender admin creates a
-- pending transfer within the same brand; receiver admin decides.
create policy product_transfers_select on public.product_transfers for select to authenticated
  using (private.is_center_admin(from_center_id) or private.is_center_admin(to_center_id));
create policy product_transfers_insert on public.product_transfers for insert to authenticated
  with check (
    private.is_center_admin(from_center_id)
    and private.same_brand(from_center_id, to_center_id)
    and status = 'pending'
    and created_product_id is null
  );
create policy product_transfers_update on public.product_transfers for update to authenticated
  using (private.is_center_admin(to_center_id) and status = 'pending')
  with check (private.is_center_admin(to_center_id));
create policy product_transfers_delete on public.product_transfers for delete to authenticated
  using (private.is_center_admin(from_center_id) and status = 'pending');

-- ---------------------------------------------------------------------------
-- Realtime: remaining seats
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.classes;
  end if;
end;
$$;
