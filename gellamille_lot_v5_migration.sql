
-- ============================================================
-- GELLAMILLE LOT V5 MIGRÁCIÓ
-- Készlet + Partnerek + Szállítmányok
--
-- ELŐFELTÉTEL:
-- A Gellamille LOT V4 migráció már sikeresen lefutott.
--
-- A partneri rendelési felület NINCS ebben a verzióban.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. PARTNEREK
-- ------------------------------------------------------------

create table if not exists public.partners (
  id bigint generated always as identity primary key,
  name text not null,
  billing_name text,
  tax_number text,
  shipping_address text,
  contact_name text,
  email text,
  phone text,
  note text,
  active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists partners_name_unique_ci
on public.partners (lower(trim(name)));

create index if not exists partners_active_name_idx
on public.partners (active, name);

-- ------------------------------------------------------------
-- 2. SZÁLLÍTMÁNYOK
-- ------------------------------------------------------------

create table if not exists public.shipments (
  id bigint generated always as identity primary key,
  shipment_number text not null unique,
  shipment_year smallint not null,
  shipment_sequence integer not null check (shipment_sequence between 1 and 9999),
  partner_id bigint not null references public.partners(id),
  shipment_date date not null,
  shipping_address text,
  customer_order_number text,
  delivery_note_number text,
  note text,
  status text not null default 'draft'
    check (status in ('draft', 'closed', 'shipped', 'void')),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_by uuid references auth.users(id),
  closed_at timestamptz,
  shipped_by uuid references auth.users(id),
  shipped_at timestamptz,
  voided_by uuid references auth.users(id),
  voided_at timestamptz,
  void_reason text,
  unique (shipment_year, shipment_sequence)
);

create index if not exists shipments_partner_date_idx
on public.shipments (partner_id, shipment_date desc);

create index if not exists shipments_status_date_idx
on public.shipments (status, shipment_date desc);

create table if not exists public.shipment_items (
  id bigint generated always as identity primary key,
  shipment_id bigint not null references public.shipments(id) on delete cascade,
  lot_id bigint not null references public.lots(id),
  quantity integer not null check (quantity > 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shipment_id, lot_id)
);

create index if not exists shipment_items_lot_idx
on public.shipment_items (lot_id);

create index if not exists shipment_items_shipment_idx
on public.shipment_items (shipment_id);

create table if not exists public.shipment_events (
  id bigint generated always as identity primary key,
  shipment_id bigint not null references public.shipments(id) on delete cascade,
  event_type text not null
    check (event_type in (
      'created',
      'item_set',
      'item_removed',
      'closed',
      'shipped',
      'voided'
    )),
  reason text,
  actor_user_id uuid references auth.users(id),
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists shipment_events_shipment_idx
on public.shipment_events (shipment_id, created_at desc);

-- ------------------------------------------------------------
-- 3. PARTNER LÉTREHOZÁSA
-- ------------------------------------------------------------

create or replace function public.create_gellamille_partner(
  p_name text,
  p_billing_name text default null,
  p_tax_number text default null,
  p_shipping_address text default null,
  p_contact_name text default null,
  p_email text default null,
  p_phone text default null,
  p_note text default null
)
returns public.partners
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_result public.partners;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  v_name := trim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));

  if char_length(v_name) < 2 then
    raise exception 'A partner neve legalább 2 karakter legyen.';
  end if;

  if exists (
    select 1
    from public.partners
    where lower(trim(name)) = lower(v_name)
  ) then
    raise exception 'Már létezik ilyen nevű partner.';
  end if;

  insert into public.partners (
    name,
    billing_name,
    tax_number,
    shipping_address,
    contact_name,
    email,
    phone,
    note,
    created_by
  )
  values (
    v_name,
    nullif(trim(p_billing_name), ''),
    nullif(trim(p_tax_number), ''),
    nullif(trim(p_shipping_address), ''),
    nullif(trim(p_contact_name), ''),
    nullif(trim(p_email), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_note), ''),
    auth.uid()
  )
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.create_gellamille_partner(
  text, text, text, text, text, text, text, text
) from public, anon;

grant execute on function public.create_gellamille_partner(
  text, text, text, text, text, text, text, text
) to authenticated;

-- ------------------------------------------------------------
-- 4. ÚJ SZÁLLÍTMÁNY LÉTREHOZÁSA
-- ------------------------------------------------------------

create or replace function public.create_gellamille_shipment(
  p_partner_id bigint,
  p_shipment_date date,
  p_shipping_address text default null,
  p_customer_order_number text default null,
  p_delivery_note_number text default null,
  p_note text default null
)
returns public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_year integer;
  v_sequence integer;
  v_partner public.partners;
  v_result public.shipments;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  if p_shipment_date is null then
    raise exception 'A szállítás dátuma kötelező.';
  end if;

  select *
  into v_partner
  from public.partners
  where id = p_partner_id
    and active = true;

  if not found then
    raise exception 'Ismeretlen vagy inaktív partner.';
  end if;

  v_year := extract(year from p_shipment_date)::integer;

  perform pg_advisory_xact_lock(
    hashtext('gellamille-shipment:' || v_year::text)
  );

  select coalesce(max(shipment_sequence), 0) + 1
  into v_sequence
  from public.shipments
  where shipment_year = v_year;

  if v_sequence > 9999 then
    raise exception 'Az éves szállítmánysorszám elérte a 9999-et.';
  end if;

  insert into public.shipments (
    shipment_number,
    shipment_year,
    shipment_sequence,
    partner_id,
    shipment_date,
    shipping_address,
    customer_order_number,
    delivery_note_number,
    note,
    status,
    created_by
  )
  values (
    'SZ-' || to_char(p_shipment_date, 'YY') || '-' || lpad(v_sequence::text, 4, '0'),
    v_year,
    v_sequence,
    p_partner_id,
    p_shipment_date,
    coalesce(nullif(trim(p_shipping_address), ''), v_partner.shipping_address),
    nullif(trim(p_customer_order_number), ''),
    nullif(trim(p_delivery_note_number), ''),
    nullif(trim(p_note), ''),
    'draft',
    auth.uid()
  )
  returning * into v_result;

  insert into public.shipment_events (
    shipment_id,
    event_type,
    actor_user_id,
    snapshot
  )
  values (
    v_result.id,
    'created',
    auth.uid(),
    to_jsonb(v_result)
  );

  return v_result;
end;
$$;

revoke all on function public.create_gellamille_shipment(
  bigint, date, text, text, text, text
) from public, anon;

grant execute on function public.create_gellamille_shipment(
  bigint, date, text, text, text, text
) to authenticated;

-- ------------------------------------------------------------
-- 5. LOT MENNYISÉG HOZZÁRENDELÉSE SZÁLLÍTMÁNYHOZ
-- ------------------------------------------------------------

create or replace function public.set_gellamille_shipment_item(
  p_shipment_id bigint,
  p_lot_id bigint,
  p_quantity integer
)
returns public.shipment_items
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shipment public.shipments;
  v_lot public.lots;
  v_allocated_other integer;
  v_available_for_shipment integer;
  v_result public.shipment_items;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'A hozzárendelt darabszám pozitív egész szám legyen.';
  end if;

  select *
  into v_shipment
  from public.shipments
  where id = p_shipment_id
  for update;

  if not found then
    raise exception 'A szállítmány nem található.';
  end if;

  if v_shipment.status <> 'draft' then
    raise exception 'Csak piszkozat állapotú szállítmány módosítható.';
  end if;

  select *
  into v_lot
  from public.lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'A LOT nem található.';
  end if;

  if v_lot.status <> 'active' then
    raise exception 'Sztornózott LOT nem rendelhető szállítmányhoz.';
  end if;

  perform pg_advisory_xact_lock(p_lot_id);

  select coalesce(sum(si.quantity), 0)::integer
  into v_allocated_other
  from public.shipment_items si
  join public.shipments s on s.id = si.shipment_id
  where si.lot_id = p_lot_id
    and si.shipment_id <> p_shipment_id
    and s.status in ('draft', 'closed', 'shipped');

  v_available_for_shipment := v_lot.quantity - v_allocated_other;

  if p_quantity > v_available_for_shipment then
    raise exception
      'Nincs elegendő készlet. Ehhez a szállítmányhoz legfeljebb % db rendelhető hozzá.',
      v_available_for_shipment;
  end if;

  insert into public.shipment_items (
    shipment_id,
    lot_id,
    quantity,
    created_by
  )
  values (
    p_shipment_id,
    p_lot_id,
    p_quantity,
    auth.uid()
  )
  on conflict (shipment_id, lot_id)
  do update set
    quantity = excluded.quantity,
    updated_at = now()
  returning * into v_result;

  update public.shipments
  set updated_at = now()
  where id = p_shipment_id;

  insert into public.shipment_events (
    shipment_id,
    event_type,
    actor_user_id,
    snapshot
  )
  values (
    p_shipment_id,
    'item_set',
    auth.uid(),
    jsonb_build_object(
      'shipment_item', to_jsonb(v_result),
      'lot_number', v_lot.lot_number,
      'available_for_shipment', v_available_for_shipment
    )
  );

  return v_result;
end;
$$;

revoke all on function public.set_gellamille_shipment_item(
  bigint, bigint, integer
) from public, anon;

grant execute on function public.set_gellamille_shipment_item(
  bigint, bigint, integer
) to authenticated;

-- ------------------------------------------------------------
-- 6. LOT ELTÁVOLÍTÁSA PISZKOZAT SZÁLLÍTMÁNYBÓL
-- ------------------------------------------------------------

create or replace function public.remove_gellamille_shipment_item(
  p_shipment_item_id bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.shipment_items;
  v_shipment public.shipments;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  select *
  into v_item
  from public.shipment_items
  where id = p_shipment_item_id
  for update;

  if not found then
    raise exception 'A szállítmánytétel nem található.';
  end if;

  select *
  into v_shipment
  from public.shipments
  where id = v_item.shipment_id
  for update;

  if v_shipment.status <> 'draft' then
    raise exception 'Csak piszkozat szállítmányból törölhető tétel.';
  end if;

  delete from public.shipment_items
  where id = p_shipment_item_id;

  update public.shipments
  set updated_at = now()
  where id = v_shipment.id;

  insert into public.shipment_events (
    shipment_id,
    event_type,
    actor_user_id,
    snapshot
  )
  values (
    v_shipment.id,
    'item_removed',
    auth.uid(),
    to_jsonb(v_item)
  );
end;
$$;

revoke all on function public.remove_gellamille_shipment_item(bigint)
from public, anon;

grant execute on function public.remove_gellamille_shipment_item(bigint)
to authenticated;

-- ------------------------------------------------------------
-- 7. SZÁLLÍTMÁNY LEZÁRÁSA / KISZÁLLÍTÁSA
-- ------------------------------------------------------------

create or replace function public.advance_gellamille_shipment(
  p_shipment_id bigint,
  p_target_status text
)
returns public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target text;
  v_current public.shipments;
  v_result public.shipments;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  v_target := lower(trim(coalesce(p_target_status, '')));

  select *
  into v_current
  from public.shipments
  where id = p_shipment_id
  for update;

  if not found then
    raise exception 'A szállítmány nem található.';
  end if;

  if v_current.status = 'draft' and v_target = 'closed' then
    if not exists (
      select 1 from public.shipment_items
      where shipment_id = p_shipment_id
    ) then
      raise exception 'Üres szállítmány nem zárható le.';
    end if;

    update public.shipments
    set
      status = 'closed',
      closed_by = auth.uid(),
      closed_at = now(),
      updated_at = now()
    where id = p_shipment_id
    returning * into v_result;

    insert into public.shipment_events (
      shipment_id, event_type, actor_user_id, snapshot
    )
    values (
      p_shipment_id, 'closed', auth.uid(), to_jsonb(v_result)
    );

    return v_result;
  end if;

  if v_current.status = 'closed' and v_target = 'shipped' then
    update public.shipments
    set
      status = 'shipped',
      shipped_by = auth.uid(),
      shipped_at = now(),
      updated_at = now()
    where id = p_shipment_id
    returning * into v_result;

    insert into public.shipment_events (
      shipment_id, event_type, actor_user_id, snapshot
    )
    values (
      p_shipment_id, 'shipped', auth.uid(), to_jsonb(v_result)
    );

    return v_result;
  end if;

  raise exception
    'Érvénytelen státuszváltás: % → %',
    v_current.status,
    v_target;
end;
$$;

revoke all on function public.advance_gellamille_shipment(bigint, text)
from public, anon;

grant execute on function public.advance_gellamille_shipment(bigint, text)
to authenticated;

-- ------------------------------------------------------------
-- 8. SZÁLLÍTMÁNY SZTORNÓZÁSA
-- ------------------------------------------------------------

create or replace function public.void_gellamille_shipment(
  p_shipment_id bigint,
  p_reason text
)
returns public.shipments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_current public.shipments;
  v_result public.shipments;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  v_reason := trim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));

  if char_length(v_reason) < 5 then
    raise exception 'A sztornózás indoka legalább 5 karakter legyen.';
  end if;

  select *
  into v_current
  from public.shipments
  where id = p_shipment_id
  for update;

  if not found then
    raise exception 'A szállítmány nem található.';
  end if;

  if v_current.status = 'void' then
    raise exception 'Ez a szállítmány már sztornózva van.';
  end if;

  if v_current.status = 'shipped' then
    raise exception 'Kiszállított szállítmány nem sztornózható. Ehhez később visszáru vagy korrekció szükséges.';
  end if;

  update public.shipments
  set
    status = 'void',
    void_reason = v_reason,
    voided_by = auth.uid(),
    voided_at = now(),
    updated_at = now()
  where id = p_shipment_id
  returning * into v_result;

  insert into public.shipment_events (
    shipment_id,
    event_type,
    reason,
    actor_user_id,
    snapshot
  )
  values (
    p_shipment_id,
    'voided',
    v_reason,
    auth.uid(),
    to_jsonb(v_result)
  );

  return v_result;
end;
$$;

revoke all on function public.void_gellamille_shipment(bigint, text)
from public, anon;

grant execute on function public.void_gellamille_shipment(bigint, text)
to authenticated;

-- ------------------------------------------------------------
-- 9. KÉSZLETNÉZET
-- ------------------------------------------------------------

create or replace view public.lot_stock
with (security_invoker = true)
as
select
  l.id as lot_id,
  l.lot_number,
  l.production_date,
  l.production_period,
  l.flavor_code,
  l.size_ml,
  l.quantity as produced_quantity,
  l.best_before,
  l.operator_id,
  l.operator_name,
  l.status as lot_status,
  coalesce(sum(si.quantity) filter (
    where s.status in ('draft', 'closed')
  ), 0)::integer as reserved_quantity,
  coalesce(sum(si.quantity) filter (
    where s.status = 'shipped'
  ), 0)::integer as shipped_quantity,
  greatest(
    l.quantity - coalesce(sum(si.quantity) filter (
      where s.status in ('draft', 'closed', 'shipped')
    ), 0),
    0
  )::integer as available_quantity
from public.lots l
left join public.shipment_items si
  on si.lot_id = l.id
left join public.shipments s
  on s.id = si.shipment_id
  and s.status <> 'void'
group by
  l.id,
  l.lot_number,
  l.production_date,
  l.production_period,
  l.flavor_code,
  l.size_ml,
  l.quantity,
  l.best_before,
  l.operator_id,
  l.operator_name,
  l.status;


-- ------------------------------------------------------------
-- 9/B. LOT SZTORNÓZÁS KÉSZLETVÉDELEMMEL
-- ------------------------------------------------------------
-- Aktív, lezárt vagy kiszállított szállítmányhoz kapcsolódó LOT
-- adatbázis-szinten sem sztornózható.

create or replace function public.void_gellamille_lot(
  p_lot_id bigint,
  p_reason text
)
returns public.lots
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_result public.lots;
begin
  if auth.uid() is null then
    raise exception 'Bejelentkezés szükséges.';
  end if;

  v_reason := trim(regexp_replace(coalesce(p_reason, ''), '\s+', ' ', 'g'));

  if char_length(v_reason) < 5 then
    raise exception 'A sztornózás indoka legalább 5 karakter legyen.';
  end if;

  select *
  into v_result
  from public.lots
  where id = p_lot_id
  for update;

  if not found then
    raise exception 'A LOT nem található.';
  end if;

  if v_result.status = 'void' then
    raise exception 'Ez a LOT már sztornózva van.';
  end if;

  if exists (
    select 1
    from public.shipment_items si
    join public.shipments s on s.id = si.shipment_id
    where si.lot_id = p_lot_id
      and s.status in ('draft', 'closed', 'shipped')
  ) then
    raise exception 'A LOT aktív vagy kiszállított szállítmányhoz kapcsolódik, ezért nem sztornózható.';
  end if;

  update public.lots
  set
    status = 'void',
    void_reason = v_reason,
    voided_by = auth.uid(),
    voided_at = now()
  where id = p_lot_id
  returning * into v_result;

  insert into public.lot_events (
    lot_id,
    event_type,
    reason,
    actor_user_id,
    snapshot
  )
  values (
    v_result.id,
    'voided',
    v_reason,
    auth.uid(),
    to_jsonb(v_result)
  );

  return v_result;
end;
$$;

revoke all on function public.void_gellamille_lot(bigint, text)
from public, anon;

grant execute on function public.void_gellamille_lot(bigint, text)
to authenticated;

-- ------------------------------------------------------------
-- 10. RLS ÉS JOGOSULTSÁGOK
-- ------------------------------------------------------------

alter table public.partners enable row level security;
alter table public.shipments enable row level security;
alter table public.shipment_items enable row level security;
alter table public.shipment_events enable row level security;

drop policy if exists "Authenticated users can read partners"
on public.partners;

create policy "Authenticated users can read partners"
on public.partners
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read shipments"
on public.shipments;

create policy "Authenticated users can read shipments"
on public.shipments
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read shipment items"
on public.shipment_items;

create policy "Authenticated users can read shipment items"
on public.shipment_items
for select
to authenticated
using (true);

drop policy if exists "Authenticated users can read shipment events"
on public.shipment_events;

create policy "Authenticated users can read shipment events"
on public.shipment_events
for select
to authenticated
using (true);

revoke all on table public.partners from anon, authenticated;
revoke all on table public.shipments from anon, authenticated;
revoke all on table public.shipment_items from anon, authenticated;
revoke all on table public.shipment_events from anon, authenticated;

grant select on table public.partners to authenticated;
grant select on table public.shipments to authenticated;
grant select on table public.shipment_items to authenticated;
grant select on table public.shipment_events to authenticated;
grant select on public.lot_stock to authenticated;

commit;
