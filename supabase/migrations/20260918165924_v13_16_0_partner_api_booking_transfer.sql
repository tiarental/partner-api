-- TIARENTAL v13.16.0
-- Partner API v1, unified availability metadata, atomic partner bookings,
-- signed-webhook delivery queue, idempotency storage, and admin transfers.
--
-- This migration is intentionally forward-only. It reuses vehicles, bookings,
-- locations, pricing_rules, availability_blocks, and audit_log. It does not
-- delete or rewrite production bookings, prices, payments, or customer PII.

begin;

set local search_path = public, private, auth, pg_catalog;

create extension if not exists btree_gist;

-- Keep the existing password-verified supplier session registry sliding while
-- the underlying Supabase session_id is still valid. This does not bypass
-- logout, password revocation, or Supabase Auth's own session policy.
create or replace function public.renew_supplier_verified_session(
  p_user_id uuid,
  p_session_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update private.supplier_verified_sessions
     set expires_at = now() + interval '179 days 23 hours',
         verified_at = now()
   where user_id = p_user_id
     and session_id = p_session_id
     and expires_at > now()
     and expires_at < now() + interval '150 days';
  return exists (
    select 1 from private.supplier_verified_sessions
     where user_id = p_user_id
       and session_id = p_session_id
       and expires_at > now()
  );
end
$function$;

revoke all on function public.renew_supplier_verified_session(uuid, text)
  from public, anon, authenticated;
grant execute on function public.renew_supplier_verified_session(uuid, text)
  to service_role;

-- -------------------------------------------------------------------------
-- Partner applications and API credentials
-- -------------------------------------------------------------------------

create table if not exists public.partner_apps (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  platform text not null default 'wordpress'
    check (platform in ('wordpress')),
  environment text not null default 'live'
    check (environment in ('test', 'live')),
  status text not null default 'active'
    check (status in ('active', 'disabled', 'disconnected')),
  last_sync_at timestamptz,
  last_webhook_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vendor_id, name, platform, environment)
);

create table if not exists public.partner_api_keys (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.companies(id) on delete cascade,
  partner_app_id uuid not null references public.partner_apps(id) on delete cascade,
  key_prefix text not null,
  key_hash text not null unique,
  status text not null default 'active'
    check (status in ('active', 'revoked', 'expired')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  check (expires_at is null or expires_at > created_at)
);

create index if not exists partner_apps_vendor_status_idx
  on public.partner_apps(vendor_id, status, platform);
create index if not exists partner_api_keys_lookup_idx
  on public.partner_api_keys(key_prefix, status);
create index if not exists partner_api_keys_vendor_app_idx
  on public.partner_api_keys(vendor_id, partner_app_id, created_at desc);

-- -------------------------------------------------------------------------
-- Reuse and extend the existing availability and booking records
-- -------------------------------------------------------------------------

alter table public.availability_blocks
  add column if not exists block_type text not null default 'manual_block',
  add column if not exists source text not null default 'admin',
  add column if not exists status text not null default 'active',
  add column if not exists booking_id uuid references public.bookings(id) on delete set null,
  add column if not exists partner_app_id uuid references public.partner_apps(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.availability_blocks'::regclass
       and conname = 'availability_blocks_block_type_check'
  ) then
    alter table public.availability_blocks
      add constraint availability_blocks_block_type_check
      check (block_type in ('manual_block', 'external_booking', 'hold'));
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.availability_blocks'::regclass
       and conname = 'availability_blocks_source_check'
  ) then
    alter table public.availability_blocks
      add constraint availability_blocks_source_check
      check (source in ('tiarental', 'wordpress', 'admin', 'external'));
  end if;
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.availability_blocks'::regclass
       and conname = 'availability_blocks_status_check'
  ) then
    alter table public.availability_blocks
      add constraint availability_blocks_status_check
      check (status in ('active', 'released'));
  end if;
end
$migration$;

update public.availability_blocks
   set block_type = case reason
         when 'external' then 'external_booking'
         else 'manual_block'
       end,
       source = case reason
         when 'external' then 'external'
         else 'admin'
       end,
       updated_at = coalesce(updated_at, created_at)
 where block_type = 'manual_block'
   and source = 'admin';

alter table public.bookings
  add column if not exists booking_source text not null default 'tiarental',
  add column if not exists partner_app_id uuid references public.partner_apps(id) on delete set null,
  add column if not exists external_reference text;

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.bookings'::regclass
       and conname = 'bookings_booking_source_check'
  ) then
    alter table public.bookings
      add constraint bookings_booking_source_check
      check (booking_source in ('tiarental', 'wordpress', 'admin', 'external'));
  end if;
end
$migration$;

create unique index if not exists bookings_partner_external_reference_uidx
  on public.bookings(partner_app_id, external_reference)
  where partner_app_id is not null and external_reference is not null;
create index if not exists bookings_partner_app_created_idx
  on public.bookings(partner_app_id, created_at desc)
  where partner_app_id is not null;
create index if not exists availability_blocks_partner_app_idx
  on public.availability_blocks(partner_app_id, created_at desc)
  where partner_app_id is not null;
create index if not exists availability_blocks_vehicle_active_range_idx
  on public.availability_blocks(vehicle_id, starts_at, ends_at)
  where status = 'active';

-- Existing production data can contain intentional overlapping legacy blocks.
-- The trigger below immediately protects all new writes. Where legacy data is
-- already clean, also install a GiST exclusion constraint for defense in depth.
create or replace function private.reject_overlapping_availability_block()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if new.status <> 'active' then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'tiarental:vehicle-inventory:' || new.vehicle_id::text,
      0
    )
  );

  if exists (
    select 1
      from public.availability_blocks ab
     where ab.vehicle_id = new.vehicle_id
       and ab.status = 'active'
       and ab.id is distinct from new.id
       and pg_catalog.tstzrange(ab.starts_at, ab.ends_at, '[)')
           && pg_catalog.tstzrange(new.starts_at, new.ends_at, '[)')
  ) then
    raise exception 'availability_block_conflict' using errcode = '23P01';
  end if;

  return new;
end
$function$;

revoke all on function private.reject_overlapping_availability_block()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_availability_blocks_no_overlap
  on public.availability_blocks;
create trigger trg_availability_blocks_no_overlap
before insert or update of vehicle_id, starts_at, ends_at, status
on public.availability_blocks
for each row execute function private.reject_overlapping_availability_block();

do $migration$
begin
  if not exists (
    select 1
      from public.availability_blocks a
      join public.availability_blocks b
        on a.vehicle_id = b.vehicle_id
       and a.id < b.id
       and a.status = 'active'
       and b.status = 'active'
       and tstzrange(a.starts_at, a.ends_at, '[)')
           && tstzrange(b.starts_at, b.ends_at, '[)')
  ) and not exists (
    select 1 from pg_constraint
     where conrelid = 'public.availability_blocks'::regclass
       and conname = 'availability_blocks_no_active_overlap'
  ) then
    alter table public.availability_blocks
      add constraint availability_blocks_no_active_overlap
      exclude using gist (
        vehicle_id with =,
        tstzrange(starts_at, ends_at, '[)') with &&
      ) where (status = 'active');
  end if;
end
$migration$;

-- One read model for all availability-consuming integrations. Bookings remain
-- in the canonical bookings table; manual/external windows stay in the
-- canonical availability_blocks table.
create or replace view public.partner_availability_windows
with (security_invoker = true)
as
select
  b.id,
  b.company_id as vendor_id,
  b.vehicle_id as car_id,
  b.pickup_at as start_at,
  b.dropoff_at as end_at,
  'booking'::text as type,
  b.booking_source as source,
  b.status::text as status,
  b.id as booking_id,
  b.partner_app_id,
  b.external_reference,
  b.updated_at
from public.bookings b
where b.status in (
  'held', 'awaiting_supplier', 'confirmed', 'payment_pending', 'paid',
  'vehicle_collected'
)
  and (
    b.status not in ('held', 'payment_pending')
    or b.hold_expires_at is null
    or b.hold_expires_at >= now()
  )
union all
select
  ab.id,
  v.company_id as vendor_id,
  ab.vehicle_id as car_id,
  ab.starts_at as start_at,
  ab.ends_at as end_at,
  ab.block_type as type,
  ab.source,
  ab.status,
  ab.booking_id,
  ab.partner_app_id,
  ab.external_reference,
  ab.updated_at
from public.availability_blocks ab
join public.vehicles v on v.id = ab.vehicle_id
where ab.status = 'active';

revoke all on public.partner_availability_windows
  from public, anon, authenticated;
grant select on public.partner_availability_windows to service_role;

-- -------------------------------------------------------------------------
-- Transfer history. Financial values are snapshots only; the transfer RPC
-- never recalculates or overwrites the customer's agreed booking price.
-- -------------------------------------------------------------------------

create table if not exists public.booking_transfers (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  from_vendor_id uuid not null references public.companies(id),
  from_car_id uuid not null references public.vehicles(id),
  to_vendor_id uuid not null references public.companies(id),
  to_car_id uuid not null references public.vehicles(id),
  booking_total numeric(10,2) not null,
  currency text not null,
  reason text,
  transferred_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (from_vendor_id <> to_vendor_id or from_car_id <> to_car_id)
);

create index if not exists booking_transfers_booking_created_idx
  on public.booking_transfers(booking_id, created_at desc);
create index if not exists booking_transfers_destination_created_idx
  on public.booking_transfers(to_vendor_id, created_at desc);

create or replace function public.admin_transfer_booking_secure(
  p_booking_id uuid,
  p_car_id uuid,
  p_actor_id uuid,
  p_reason text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking public.bookings%rowtype;
  v_car public.vehicles%rowtype;
  v_result public.bookings%rowtype;
  v_first text;
  v_second text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_booking_id is null or p_car_id is null or p_actor_id is null then
    raise exception 'invalid_transfer';
  end if;

  select * into v_booking
    from public.bookings
   where id = p_booking_id
   for update;
  if not found then raise exception 'booking_not_found'; end if;
  if v_booking.status in ('cancelled', 'no_show', 'completed', 'vehicle_collected') then
    raise exception 'booking_not_transferable';
  end if;

  select v.* into v_car
    from public.vehicles v
    join public.companies c on c.id = v.company_id
   where v.id = p_car_id
     and v.status = 'active'
     and v.moderation_status = 'approved'
     and c.status::text in ('pending', 'active', 'verified')
     and coalesce(c.public_listing_enabled, false)
   for share;
  if not found then raise exception 'car_not_available'; end if;
  if v_car.id = v_booking.vehicle_id then raise exception 'same_car'; end if;

  v_first := least(v_booking.vehicle_id::text, v_car.id::text);
  v_second := greatest(v_booking.vehicle_id::text, v_car.id::text);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('tiarental:vehicle-inventory:' || v_first, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('tiarental:vehicle-inventory:' || v_second, 0)
  );

  update public.bookings
     set company_id = v_car.company_id,
         vehicle_id = v_car.id,
         vehicle_snapshot = jsonb_build_object(
           'brand', v_car.brand,
           'model', v_car.model,
           'year', v_car.year,
           'deposit_amount', v_booking.deposit_amount,
           'transferred_from_vehicle_id', v_booking.vehicle_id,
           'transferred_at', now()
         ),
         updated_at = now()
   where id = v_booking.id
   returning * into v_result;

  insert into public.booking_transfers(
    booking_id, from_vendor_id, from_car_id, to_vendor_id, to_car_id,
    booking_total, currency, reason, transferred_by
  ) values (
    v_booking.id, v_booking.company_id, v_booking.vehicle_id,
    v_car.company_id, v_car.id, v_booking.total_price, v_booking.currency,
    nullif(left(trim(coalesce(p_reason, '')), 500), ''), p_actor_id
  );

  insert into public.audit_log(
    actor_id, company_id, entity_type, entity_id, action,
    before_data, after_data
  ) values (
    p_actor_id, v_car.company_id, 'booking', v_booking.id,
    'admin_booking_transferred',
    jsonb_build_object(
      'company_id', v_booking.company_id,
      'vehicle_id', v_booking.vehicle_id,
      'total_price', v_booking.total_price,
      'currency', v_booking.currency
    ),
    jsonb_build_object(
      'company_id', v_car.company_id,
      'vehicle_id', v_car.id,
      'total_price', v_result.total_price,
      'currency', v_result.currency,
      'price_preserved', true,
      'reason', nullif(left(trim(coalesce(p_reason, '')), 500), '')
    )
  );

  return v_result;
exception when exclusion_violation then
  raise exception 'car_not_available' using errcode = '23P01';
end
$function$;

revoke all on function public.admin_transfer_booking_secure(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_transfer_booking_secure(uuid, uuid, uuid, text)
  to service_role;

create or replace function public.admin_update_booking_secure(
  p_booking_id uuid,
  p_pickup_at timestamptz,
  p_dropoff_at timestamptz,
  p_status public.booking_status,
  p_customer_phone text
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking public.bookings%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_pickup_at is null or p_dropoff_at is null or p_dropoff_at <= p_pickup_at
     or length(trim(coalesce(p_customer_phone, ''))) < 7 then
    raise exception 'invalid_booking_data';
  end if;
  select * into v_booking
    from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'booking_not_found'; end if;
  if p_status = 'cancelled' and exists (
    select 1 from public.payments p
     where p.booking_id = p_booking_id
       and p.status in ('paid', 'partially_refunded', 'authorized')
  ) then raise exception 'paid_booking_requires_refund'; end if;

  update public.bookings
     set pickup_at = p_pickup_at,
         dropoff_at = p_dropoff_at,
         status = p_status,
         hold_expires_at = case
           when p_status in ('held', 'payment_pending') then hold_expires_at
           else null
         end,
         updated_at = now()
   where id = p_booking_id
   returning * into v_booking;
  update public.booking_driver_private
     set phone = left(trim(p_customer_phone), 40)
   where booking_id = p_booking_id;
  if not found then raise exception 'booking_driver_not_found'; end if;
  return v_booking;
exception when exclusion_violation then
  raise exception 'car_not_available' using errcode = '23P01';
end
$function$;

revoke all on function public.admin_update_booking_secure(
  uuid, timestamptz, timestamptz, public.booking_status, text
) from public, anon, authenticated;
grant execute on function public.admin_update_booking_secure(
  uuid, timestamptz, timestamptz, public.booking_status, text
) to service_role;

-- -------------------------------------------------------------------------
-- Partner booking RPC. This is the transaction boundary used by WordPress
-- and future partner channels. Database constraints and inventory locks make
-- simultaneous requests safe even when application checks race.
-- -------------------------------------------------------------------------

create or replace function public.partner_create_booking_secure(
  p_vendor_id uuid,
  p_partner_app_id uuid,
  p_car_id uuid,
  p_pickup_location_id uuid,
  p_dropoff_location_id uuid,
  p_pickup_at timestamptz,
  p_dropoff_at timestamptz,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_phone text,
  p_driver_age integer default null,
  p_driving_years integer default null,
  p_country text default null,
  p_notes text default null,
  p_cross_border_countries text[] default '{}'::text[],
  p_booking_mode text default 'request',
  p_external_reference text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_vehicle public.vehicles%rowtype;
  v_quote jsonb;
  v_booking public.bookings%rowtype;
  v_status public.booking_status;
  v_number text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_vendor_id is null or p_partner_app_id is null or p_car_id is null
     or p_pickup_at is null or p_dropoff_at is null
     or p_dropoff_at <= p_pickup_at or p_pickup_at < now()
     or p_dropoff_at - p_pickup_at > interval '366 days'
  then
    raise exception 'invalid_dates';
  end if;
  if p_booking_mode not in ('request', 'instant') then
    raise exception 'invalid_booking_mode';
  end if;
  if length(trim(coalesce(p_first_name, ''))) < 1
     or length(trim(coalesce(p_last_name, ''))) < 1
     or position('@' in coalesce(p_email, '')) < 2
     or length(trim(coalesce(p_phone, ''))) < 7
  then
    raise exception 'invalid_customer';
  end if;
  if not exists (
    select 1 from public.partner_apps pa
     where pa.id = p_partner_app_id
       and pa.vendor_id = p_vendor_id
       and pa.status = 'active'
  ) then
    raise exception 'partner_app_not_found';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'tiarental:vehicle-inventory:' || p_car_id::text,
      0
    )
  );

  select v.* into v_vehicle
    from public.vehicles v
    join public.companies c on c.id = v.company_id
   where v.id = p_car_id
     and v.company_id = p_vendor_id
     and v.status = 'active'
     and v.moderation_status = 'approved'
     and c.status::text in ('pending', 'active', 'verified')
     and coalesce(c.public_listing_enabled, false)
   for share;
  if not found then raise exception 'car_not_found'; end if;

  if p_driver_age is not null and p_driver_age < v_vehicle.minimum_driver_age then
    raise exception 'driver_age_requirement';
  end if;
  if p_driving_years is not null
     and p_driving_years < v_vehicle.minimum_driving_years then
    raise exception 'driving_experience_requirement';
  end if;

  v_quote := public.vehicle_quote(
    p_car_id,
    p_pickup_location_id,
    p_dropoff_location_id,
    p_pickup_at,
    p_dropoff_at,
    coalesce(p_cross_border_countries, '{}'::text[])
  );
  v_status := case
    when p_booking_mode = 'instant' and v_vehicle.instant_confirmation
      then 'confirmed'::public.booking_status
    else 'awaiting_supplier'::public.booking_status
  end;
  v_number := 'TIA-' || to_char(now(), 'YYMMDD') || '-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.bookings(
    booking_number, customer_id, company_id, vehicle_id, status,
    pickup_location_id, dropoff_location_id, pickup_at, dropoff_at,
    currency, rental_subtotal, extras_total, total_price, commission_rate,
    platform_prepayment, supplier_balance, deposit_amount, hold_expires_at,
    cross_border_countries, cancellation_policy_snapshot, vehicle_snapshot,
    price_snapshot, booking_source, partner_app_id, external_reference
  ) values (
    v_number, null, p_vendor_id, p_car_id, v_status,
    p_pickup_location_id, p_dropoff_location_id, p_pickup_at, p_dropoff_at,
    coalesce(v_quote->>'currency', 'EUR'),
    (v_quote->>'rental_subtotal')::numeric,
    greatest(0, (v_quote->>'total')::numeric - (v_quote->>'rental_subtotal')::numeric),
    (v_quote->>'total')::numeric,
    (v_quote->>'prepayment_rate')::numeric,
    (v_quote->>'platform_prepayment')::numeric,
    (v_quote->>'supplier_balance')::numeric,
    (v_quote->>'deposit_amount')::numeric,
    null,
    coalesce(p_cross_border_countries, '{}'::text[]),
    jsonb_build_object('free_cancellation_hours', v_vehicle.free_cancellation_hours),
    jsonb_build_object(
      'brand', v_vehicle.brand,
      'model', v_vehicle.model,
      'year', v_vehicle.year,
      'deposit_amount', v_vehicle.deposit_amount
    ),
    v_quote || jsonb_build_object(
      'channel', 'partner_api',
      'booking_mode', p_booking_mode
    ),
    case
      when exists (
        select 1 from public.partner_apps pa
         where pa.id = p_partner_app_id and pa.platform = 'wordpress'
      ) then 'wordpress'
      else 'external'
    end,
    p_partner_app_id,
    nullif(left(trim(coalesce(p_external_reference, '')), 200), '')
  ) returning * into v_booking;

  insert into public.booking_driver_private(
    booking_id, first_name, last_name, email, phone, age, country,
    customer_notes
  ) values (
    v_booking.id,
    left(trim(p_first_name), 100),
    left(trim(p_last_name), 100),
    left(lower(trim(p_email)), 320),
    left(trim(p_phone), 40),
    p_driver_age,
    nullif(left(trim(coalesce(p_country, '')), 100), ''),
    nullif(left(trim(coalesce(p_notes, '')), 2000), '')
  );

  return v_booking;
exception
  when unique_violation then
    raise exception 'duplicate_external_reference' using errcode = '23505';
  when exclusion_violation then
    raise exception 'car_not_available' using errcode = '23P01';
end
$function$;

revoke all on function public.partner_create_booking_secure(
  uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz,
  text, text, text, text, integer, integer, text, text, text[], text, text
) from public, anon, authenticated;
grant execute on function public.partner_create_booking_secure(
  uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz,
  text, text, text, text, integer, integer, text, text, text[], text, text
) to service_role;

create or replace function public.partner_modify_booking_secure(
  p_vendor_id uuid,
  p_partner_app_id uuid,
  p_booking_id uuid,
  p_pickup_location_id uuid,
  p_dropoff_location_id uuid,
  p_pickup_at timestamptz,
  p_dropoff_at timestamptz,
  p_first_name text default null,
  p_last_name text default null,
  p_email text default null,
  p_phone text default null,
  p_notes text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking public.bookings%rowtype;
  v_result public.bookings%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_pickup_at is null or p_dropoff_at is null
     or p_dropoff_at <= p_pickup_at
     or p_pickup_at < now()
     or p_dropoff_at - p_pickup_at > interval '366 days' then
    raise exception 'invalid_dates';
  end if;
  select * into v_booking
    from public.bookings
   where id = p_booking_id
     and company_id = p_vendor_id
     and partner_app_id = p_partner_app_id
   for update;
  if not found then raise exception 'booking_not_found'; end if;
  if v_booking.status in ('cancelled', 'no_show', 'vehicle_collected', 'completed') then
    raise exception 'booking_not_modifiable';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'tiarental:vehicle-inventory:' || v_booking.vehicle_id::text,
      0
    )
  );
  if p_pickup_location_id is not null and not exists (
    select 1 from public.vehicle_pickup_locations
     where vehicle_id = v_booking.vehicle_id
       and location_id = p_pickup_location_id
  ) then raise exception 'pickup_not_allowed'; end if;
  if p_dropoff_location_id is not null and not exists (
    select 1 from public.vehicle_pickup_locations
     where vehicle_id = v_booking.vehicle_id
       and location_id = p_dropoff_location_id
  ) then raise exception 'dropoff_not_allowed'; end if;

  update public.bookings
     set pickup_location_id = p_pickup_location_id,
         dropoff_location_id = p_dropoff_location_id,
         pickup_at = p_pickup_at,
         dropoff_at = p_dropoff_at,
         price_snapshot = price_snapshot || jsonb_build_object(
           'partner_modified_at', now(),
           'partner_modify_price_preserved', true
         ),
         updated_at = now()
   where id = v_booking.id
   returning * into v_result;

  update public.booking_driver_private
     set first_name = case when nullif(trim(coalesce(p_first_name, '')), '') is null
           then first_name else left(trim(p_first_name), 100) end,
         last_name = case when nullif(trim(coalesce(p_last_name, '')), '') is null
           then last_name else left(trim(p_last_name), 100) end,
         email = case when nullif(trim(coalesce(p_email, '')), '') is null
           then email else left(lower(trim(p_email)), 320) end,
         phone = case when nullif(trim(coalesce(p_phone, '')), '') is null
           then phone else left(trim(p_phone), 40) end,
         customer_notes = case when p_notes is null
           then customer_notes else nullif(left(trim(p_notes), 2000), '') end
   where booking_id = v_booking.id;

  return v_result;
exception when exclusion_violation then
  raise exception 'car_not_available' using errcode = '23P01';
end
$function$;

create or replace function public.partner_cancel_booking_secure(
  p_vendor_id uuid,
  p_partner_app_id uuid,
  p_booking_id uuid,
  p_reason text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_booking public.bookings%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into v_booking
    from public.bookings
   where id = p_booking_id
     and company_id = p_vendor_id
     and partner_app_id = p_partner_app_id
   for update;
  if not found then raise exception 'booking_not_found'; end if;
  if v_booking.status = 'cancelled' then return v_booking; end if;
  if v_booking.status in ('vehicle_collected', 'completed') then
    raise exception 'booking_not_cancellable';
  end if;
  if exists (
    select 1 from public.payments p
     where p.booking_id = v_booking.id
       and p.status in ('authorized', 'paid', 'partially_refunded')
  ) then raise exception 'booking_has_platform_payment'; end if;

  update public.bookings
     set status = 'cancelled', hold_expires_at = null, updated_at = now()
   where id = v_booking.id
   returning * into v_booking;
  insert into public.audit_log(
    actor_id, company_id, entity_type, entity_id, action, after_data
  ) values (
    null, p_vendor_id, 'booking', p_booking_id,
    'partner_api_booking_cancelled',
    jsonb_build_object(
      'partner_app_id', p_partner_app_id,
      'reason', nullif(left(trim(coalesce(p_reason, '')), 500), '')
    )
  );
  return v_booking;
end
$function$;

revoke all on function public.partner_modify_booking_secure(
  uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz,
  text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.partner_modify_booking_secure(
  uuid, uuid, uuid, uuid, uuid, timestamptz, timestamptz,
  text, text, text, text, text
) to service_role;
revoke all on function public.partner_cancel_booking_secure(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.partner_cancel_booking_secure(uuid, uuid, uuid, text)
  to service_role;

-- -------------------------------------------------------------------------
-- Webhook registrations, immutable events, retryable deliveries
-- -------------------------------------------------------------------------

create table if not exists public.partner_webhooks (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.companies(id) on delete cascade,
  partner_app_id uuid not null references public.partner_apps(id) on delete cascade,
  url text not null,
  event_types text[] not null default '{}'::text[],
  secret_prefix text not null,
  secret_ciphertext text not null,
  secret_iv text not null,
  secret_tag text not null,
  status text not null default 'active'
    check (status in ('active', 'disabled', 'deleted')),
  last_success_at timestamptz,
  last_failure_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (partner_app_id, url)
);

create table if not exists public.partner_webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  vendor_id uuid not null references public.companies(id) on delete cascade,
  event_type text not null,
  resource_type text not null,
  resource_id uuid,
  payload jsonb not null,
  occurred_at timestamptz not null default now()
);

create table if not exists public.webhook_deliveries (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.partner_webhook_events(id) on delete cascade,
  webhook_id uuid not null references public.partner_webhooks(id) on delete cascade,
  attempt integer not null default 0 check (attempt >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'delivered', 'failed', 'dead')),
  response_code integer,
  response_body text,
  last_error text,
  next_retry_at timestamptz not null default now(),
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, webhook_id)
);

create index if not exists webhook_deliveries_due_idx
  on public.webhook_deliveries(status, next_retry_at, created_at)
  where status in ('pending', 'failed', 'processing');
create index if not exists partner_webhooks_vendor_status_idx
  on public.partner_webhooks(vendor_id, status, created_at desc);
create index if not exists partner_webhook_events_vendor_time_idx
  on public.partner_webhook_events(vendor_id, occurred_at desc);

create table if not exists public.api_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.companies(id) on delete cascade,
  partner_app_id uuid not null references public.partner_apps(id) on delete cascade,
  idempotency_key text not null,
  request_method text not null,
  request_path text not null,
  request_hash text not null,
  state text not null default 'processing'
    check (state in ('processing', 'completed', 'failed')),
  response_status integer,
  response_body jsonb,
  resource_type text,
  resource_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  unique (partner_app_id, idempotency_key)
);

create index if not exists api_idempotency_keys_expiry_idx
  on public.api_idempotency_keys(expires_at);

create or replace function private.enqueue_partner_webhook_event(
  p_event_key text,
  p_vendor_id uuid,
  p_event_type text,
  p_resource_type text,
  p_resource_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_id uuid;
begin
  insert into public.partner_webhook_events(
    event_key, vendor_id, event_type, resource_type, resource_id, payload
  ) values (
    p_event_key, p_vendor_id, p_event_type, p_resource_type, p_resource_id,
    jsonb_build_object(
      'id', 'evt_' || replace(gen_random_uuid()::text, '-', ''),
      'type', p_event_type,
      'created_at', now(),
      'data', coalesce(p_payload, '{}'::jsonb)
    )
  ) on conflict(event_key) do nothing
  returning id into v_event_id;

  if v_event_id is null then return null; end if;

  insert into public.webhook_deliveries(event_id, webhook_id)
  select v_event_id, w.id
    from public.partner_webhooks w
   where w.vendor_id = p_vendor_id
     and w.status = 'active'
     and (
       cardinality(w.event_types) = 0
       or p_event_type = any(w.event_types)
     )
  on conflict(event_id, webhook_id) do nothing;

  return v_event_id;
end
$function$;

revoke all on function private.enqueue_partner_webhook_event(
  text, uuid, text, text, uuid, jsonb
) from public, anon, authenticated, service_role;

create or replace function private.queue_partner_booking_webhooks()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event text;
  v_stamp text;
  v_payload jsonb;
begin
  v_stamp := replace(coalesce(new.updated_at, now())::text, ' ', 'T');
  v_payload := jsonb_build_object(
    'booking_id', new.id,
    'booking_number', new.booking_number,
    'vendor_id', new.company_id,
    'car_id', new.vehicle_id,
    'status', new.status,
    'pickup_at', new.pickup_at,
    'dropoff_at', new.dropoff_at,
    'pickup_location_id', new.pickup_location_id,
    'dropoff_location_id', new.dropoff_location_id,
    'currency', new.currency,
    'total_price', new.total_price,
    'source', new.booking_source,
    'external_reference', new.external_reference
  );

  if tg_op = 'INSERT' then
    perform private.enqueue_partner_webhook_event(
      'booking.created:' || new.id::text,
      new.company_id, 'booking.created', 'booking', new.id, v_payload
    );
    if new.status = 'confirmed' then
      perform private.enqueue_partner_webhook_event(
        'booking.confirmed:' || new.id::text || ':' || v_stamp,
        new.company_id, 'booking.confirmed', 'booking', new.id, v_payload
      );
    end if;
    return new;
  end if;

  if new.company_id is distinct from old.company_id then
    perform private.enqueue_partner_webhook_event(
      'booking.modified:source:' || new.id::text || ':' || v_stamp,
      old.company_id, 'booking.modified', 'booking', new.id,
      v_payload || jsonb_build_object(
        'removed_from_vendor', true,
        'previous_vendor_id', old.company_id,
        'previous_car_id', old.vehicle_id
      )
    );
  end if;

  if new.status is distinct from old.status then
    v_event := case
      when new.status = 'confirmed' then 'booking.confirmed'
      when new.status = 'cancelled' and old.status = 'awaiting_supplier'
        then 'booking.rejected'
      when new.status = 'cancelled' then 'booking.cancelled'
      else 'booking.modified'
    end;
    perform private.enqueue_partner_webhook_event(
      v_event || ':' || new.id::text || ':' || v_stamp,
      new.company_id, v_event, 'booking', new.id,
      v_payload || jsonb_build_object('previous_status', old.status)
    );
  elsif new.vehicle_id is distinct from old.vehicle_id
     or new.company_id is distinct from old.company_id
     or new.pickup_at is distinct from old.pickup_at
     or new.dropoff_at is distinct from old.dropoff_at
     or new.pickup_location_id is distinct from old.pickup_location_id
     or new.dropoff_location_id is distinct from old.dropoff_location_id then
    perform private.enqueue_partner_webhook_event(
      'booking.modified:' || new.id::text || ':' || v_stamp,
      new.company_id, 'booking.modified', 'booking', new.id,
      v_payload || jsonb_build_object(
        'previous_vendor_id', old.company_id,
        'previous_car_id', old.vehicle_id
      )
    );
  end if;
  return new;
end
$function$;

create or replace function private.queue_partner_block_webhooks()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_vendor_id uuid;
  v_row public.availability_blocks%rowtype;
  v_event text;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  select company_id into v_vendor_id
    from public.vehicles where id = v_row.vehicle_id;
  if v_vendor_id is null then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  v_event := case when tg_op = 'DELETE' or v_row.status = 'released'
    then 'availability.unblocked' else 'availability.blocked' end;
  perform private.enqueue_partner_webhook_event(
    v_event || ':' || v_row.id::text || ':' || tg_op || ':' ||
      replace(coalesce(v_row.updated_at, now())::text, ' ', 'T'),
    v_vendor_id, v_event, 'availability_block', v_row.id,
    jsonb_build_object(
      'block_id', v_row.id,
      'vendor_id', v_vendor_id,
      'car_id', v_row.vehicle_id,
      'start_at', v_row.starts_at,
      'end_at', v_row.ends_at,
      'type', v_row.block_type,
      'source', v_row.source,
      'status', v_row.status,
      'external_reference', v_row.external_reference
    )
  );
  if tg_op = 'DELETE' then return old; else return new; end if;
end
$function$;

create or replace function private.queue_partner_car_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform private.enqueue_partner_webhook_event(
    'car.updated:' || new.id::text || ':' || replace(new.updated_at::text, ' ', 'T'),
    new.company_id, 'car.updated', 'car', new.id,
    jsonb_build_object(
      'car_id', new.id,
      'vendor_id', new.company_id,
      'slug', new.slug,
      'status', new.status,
      'updated_at', new.updated_at
    )
  );
  return new;
end
$function$;

create or replace function private.queue_partner_price_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.pricing_rules%rowtype;
  v_vendor_id uuid;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  select company_id into v_vendor_id
    from public.vehicles where id = v_row.vehicle_id;
  if v_vendor_id is null then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  perform private.enqueue_partner_webhook_event(
    'price.updated:' || v_row.id::text || ':' || tg_op || ':' ||
      extract(epoch from clock_timestamp())::bigint::text,
    v_vendor_id, 'price.updated', 'pricing_rule', v_row.id,
    jsonb_build_object(
      'pricing_rule_id', v_row.id,
      'car_id', v_row.vehicle_id,
      'vendor_id', v_vendor_id,
      'operation', lower(tg_op)
    )
  );
  if tg_op = 'DELETE' then return old; else return new; end if;
end
$function$;

revoke all on function private.queue_partner_booking_webhooks()
  from public, anon, authenticated, service_role;
revoke all on function private.queue_partner_block_webhooks()
  from public, anon, authenticated, service_role;
revoke all on function private.queue_partner_car_webhook()
  from public, anon, authenticated, service_role;
revoke all on function private.queue_partner_price_webhook()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_partner_booking_webhooks on public.bookings;
create trigger trg_partner_booking_webhooks
after insert or update of status, company_id, vehicle_id, pickup_at, dropoff_at,
  pickup_location_id, dropoff_location_id
on public.bookings
for each row execute function private.queue_partner_booking_webhooks();

drop trigger if exists trg_partner_block_webhooks on public.availability_blocks;
create trigger trg_partner_block_webhooks
after insert or update of status, vehicle_id, starts_at, ends_at or delete
on public.availability_blocks
for each row execute function private.queue_partner_block_webhooks();

drop trigger if exists trg_partner_car_webhook on public.vehicles;
create trigger trg_partner_car_webhook
after update of status, brand, model, base_daily_price, deposit_amount,
  instant_confirmation, updated_at
on public.vehicles
for each row execute function private.queue_partner_car_webhook();

drop trigger if exists trg_partner_price_webhook on public.pricing_rules;
create trigger trg_partner_price_webhook
after insert or update or delete on public.pricing_rules
for each row execute function private.queue_partner_price_webhook();

create or replace function public.claim_partner_webhook_deliveries(
  p_limit integer default 20
)
returns setof public.webhook_deliveries
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return query
  with candidates as (
    select d.id
      from public.webhook_deliveries d
     where (
       d.status in ('pending', 'failed')
       or (d.status = 'processing' and d.locked_at < now() - interval '5 minutes')
     )
       and d.next_retry_at <= now()
       and d.attempt < 10
     order by d.next_retry_at, d.created_at
     for update skip locked
     limit greatest(1, least(coalesce(p_limit, 20), 100))
  )
  update public.webhook_deliveries d
     set status = 'processing',
         attempt = d.attempt + 1,
         locked_at = now(),
         updated_at = now()
   where d.id in (select id from candidates)
  returning d.*;
end
$function$;

create or replace function public.finish_partner_webhook_delivery(
  p_delivery_id uuid,
  p_success boolean,
  p_response_code integer default null,
  p_response_body text default null,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_delivery public.webhook_deliveries%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  select * into v_delivery
    from public.webhook_deliveries where id = p_delivery_id for update;
  if not found then return false; end if;

  update public.webhook_deliveries
     set status = case
           when p_success then 'delivered'
           when v_delivery.attempt >= 10 then 'dead'
           else 'failed'
         end,
         response_code = p_response_code,
         response_body = left(coalesce(p_response_body, ''), 4000),
         last_error = case when p_success then null
           else left(coalesce(p_error, 'webhook_delivery_failed'), 1000) end,
         next_retry_at = case when p_success then next_retry_at else
           now() + make_interval(secs => least(21600, 30 * (2 ^ least(v_delivery.attempt, 9))::integer))
         end,
         locked_at = null,
         updated_at = now()
   where id = p_delivery_id;

  update public.partner_webhooks w
     set last_success_at = case when p_success then now() else last_success_at end,
         last_failure_at = case when p_success then last_failure_at else now() end,
         updated_at = now()
    from public.webhook_deliveries d
   where d.id = p_delivery_id and w.id = d.webhook_id;
  return true;
end
$function$;

revoke all on function public.claim_partner_webhook_deliveries(integer)
  from public, anon, authenticated;
grant execute on function public.claim_partner_webhook_deliveries(integer)
  to service_role;
revoke all on function public.finish_partner_webhook_delivery(
  uuid, boolean, integer, text, text
) from public, anon, authenticated;
grant execute on function public.finish_partner_webhook_delivery(
  uuid, boolean, integer, text, text
) to service_role;

-- -------------------------------------------------------------------------
-- RLS and explicit grants. Partner credentials are authenticated only in the
-- Next.js server API; neither WordPress nor browser code receives a Supabase
-- service credential.
-- -------------------------------------------------------------------------

alter table public.partner_apps enable row level security;
alter table public.partner_api_keys enable row level security;
alter table public.booking_transfers enable row level security;
alter table public.partner_webhooks enable row level security;
alter table public.partner_webhook_events enable row level security;
alter table public.webhook_deliveries enable row level security;
alter table public.api_idempotency_keys enable row level security;

revoke all on table
  public.partner_apps,
  public.partner_api_keys,
  public.booking_transfers,
  public.partner_webhooks,
  public.partner_webhook_events,
  public.webhook_deliveries,
  public.api_idempotency_keys
from public, anon, authenticated;

grant select, insert, update, delete on table
  public.partner_apps,
  public.partner_api_keys,
  public.booking_transfers,
  public.partner_webhooks,
  public.partner_webhook_events,
  public.webhook_deliveries,
  public.api_idempotency_keys
to service_role;

-- Availability/bookings already have their own RLS. Server-only Partner API
-- uses the service role after validating and scoping the custom API key.

comment on table public.partner_api_keys is
  'Partner API keys: only prefix + HMAC hash are stored; plaintext is reveal-once.';
comment on table public.partner_webhooks is
  'Webhook signing secrets are encrypted by the application before storage.';
comment on view public.partner_availability_windows is
  'Unified server-only read model for booking and availability block windows.';

commit;
