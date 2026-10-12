-- 박스인(BoxIn) v0.4 — class booking
-- Members book through book_class() so capacity is checked in one place and
-- over-booking is impossible; a full class puts them on the waitlist, and a
-- cancellation promotes the first person waiting.

-- True when the person holds a pass that is usable on the given day.
create function private.has_usable_pass(p_center_id uuid, p_profile_id uuid, p_day date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.passes p
    where p.center_id = p_center_id
      and p.profile_id = p_profile_id
      and p.status = 'active'
      and p_day between p.start_date and p.end_date
      and (p.remaining_count is null or p.remaining_count > 0)
  )
$$;

grant execute on function private.has_usable_pass(uuid, uuid, date) to authenticated;

-- Books a class for the caller, or (coach/admin only) for p_profile_id.
-- Returns the resulting status: 'booked' or 'waitlisted'.
create function public.book_class(p_class_id uuid, p_profile_id uuid default null)
returns public.booking_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := private.current_profile_id();
  v_target uuid := coalesce(p_profile_id, v_me);
  v_class public.classes%rowtype;
  v_timezone text;
  v_is_staff boolean;
  v_status public.booking_status;
  v_booked integer;
begin
  if v_me is null then
    raise exception 'not signed in';
  end if;

  -- Lock the class row so concurrent bookings are counted one at a time.
  select * into v_class from public.classes where id = p_class_id for update;
  if not found then
    raise exception 'class not found';
  end if;

  v_is_staff := private.is_center_staff(v_class.center_id);
  if v_target <> v_me and not v_is_staff then
    raise exception 'not allowed';
  end if;
  if not exists (
    select 1 from public.memberships m
    where m.center_id = v_class.center_id and m.profile_id = v_target and m.is_active
  ) then
    raise exception 'not a member of this center';
  end if;
  if v_class.starts_at <= now() then
    raise exception 'class already started';
  end if;

  select status into v_status from public.bookings
  where class_id = p_class_id and profile_id = v_target and status <> 'cancelled';
  if found then
    return v_status;
  end if;

  -- Plain members need a pass that is valid on the class day; staff are exempt.
  if not exists (
    select 1 from public.memberships m
    where m.center_id = v_class.center_id and m.profile_id = v_target
      and m.role in ('coach', 'admin')
  ) then
    select timezone into v_timezone from public.centers where id = v_class.center_id;
    if not private.has_usable_pass(
      v_class.center_id, v_target, (v_class.starts_at at time zone v_timezone)::date
    ) then
      raise exception 'no usable pass';
    end if;
  end if;

  select count(*) into v_booked from public.bookings
  where class_id = p_class_id and status = 'booked';
  v_status := case when v_booked < v_class.capacity then 'booked' else 'waitlisted' end;

  insert into public.bookings (center_id, class_id, profile_id, status)
  values (v_class.center_id, p_class_id, v_target, v_status);

  return v_status;
end;
$$;

-- Cancels a booking (own, or any in the center for coach/admin) and promotes
-- the first waitlisted person when a seat frees up.
create function public.cancel_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings%rowtype;
  v_class public.classes%rowtype;
  v_next uuid;
begin
  select * into v_booking from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'booking not found';
  end if;
  if v_booking.profile_id is distinct from private.current_profile_id()
     and not private.is_center_staff(v_booking.center_id) then
    raise exception 'not allowed';
  end if;
  if v_booking.status = 'cancelled' then
    return;
  end if;

  select * into v_class from public.classes where id = v_booking.class_id for update;

  update public.bookings
    set status = 'cancelled', cancelled_at = now()
    where id = p_booking_id;

  if v_booking.status = 'booked' and v_class.starts_at > now() then
    select id into v_next from public.bookings
    where class_id = v_booking.class_id and status = 'waitlisted'
    order by created_at
    limit 1;
    if v_next is not null then
      update public.bookings set status = 'booked' where id = v_next;
    end if;
  end if;
end;
$$;

revoke execute on function public.book_class(uuid, uuid) from public, anon;
revoke execute on function public.cancel_booking(uuid) from public, anon;
grant execute on function public.book_class(uuid, uuid) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
