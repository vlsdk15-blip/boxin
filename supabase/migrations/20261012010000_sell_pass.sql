-- 박스인(BoxIn) v0.5 — on-site pass sale
-- Coach/admin issues a pass and records the on-site payment in one step, so
-- a pass never exists without its payment row (or the other way round).
-- Dates and counts are derived from the product, not sent by the client.

create function public.sell_pass(
  p_center_id uuid,
  p_profile_id uuid,
  p_product_id uuid,
  p_start_date date default null,
  p_amount integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product public.pass_products%rowtype;
  v_start date;
  v_pass_id uuid;
begin
  if not private.is_center_staff(p_center_id) then
    raise exception 'not allowed';
  end if;

  select * into v_product from public.pass_products
  where id = p_product_id and center_id = p_center_id and is_active;
  if not found then
    raise exception 'product not found';
  end if;

  select coalesce(p_start_date, (now() at time zone c.timezone)::date) into v_start
  from public.centers c where c.id = p_center_id;

  insert into public.passes (center_id, profile_id, product_id, start_date, end_date, remaining_count)
  values (
    p_center_id,
    p_profile_id,
    p_product_id,
    v_start,
    -- The start day counts as day 1.
    v_start + coalesce(v_product.duration_days, v_product.usage_expiry_days) - 1,
    v_product.count
  )
  returning id into v_pass_id;

  insert into public.payments
    (center_id, profile_id, product_id, pass_id, amount, method, status, paid_at, recorded_by)
  values
    (p_center_id, p_profile_id, p_product_id, v_pass_id, coalesce(p_amount, v_product.price),
     'on_site', 'paid', now(), private.current_profile_id());

  return v_pass_id;
end;
$$;

revoke execute on function public.sell_pass(uuid, uuid, uuid, date, integer) from public, anon;
grant execute on function public.sell_pass(uuid, uuid, uuid, date, integer) to authenticated;
