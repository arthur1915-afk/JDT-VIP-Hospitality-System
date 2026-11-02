-- JDT VIP Hospitality System
-- Supabase PostgreSQL schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'guest' check (role in ('guest','staff','vendor','admin')),
  vendor_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.profiles
  add constraint profiles_vendor_id_fkey
  foreign key (vendor_id) references public.vendors(id) on delete set null;

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id),
  name text not null,
  description text not null default '',
  price_myr numeric(10,2) not null check (price_myr >= 0),
  available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('JDT-' || upper(substr(encode(gen_random_bytes(5),'hex'),1,8))),
  guest_id uuid not null references auth.users(id),
  guest_name text not null,
  booth text not null,
  vendor_id uuid not null references public.vendors(id),
  status text not null default 'received'
    check (status in ('received','accepted','preparing','ready','delivered','cancelled')),
  notes text not null default '',
  total_myr numeric(10,2) not null default 0 check (total_myr >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id),
  item_name text not null,
  quantity integer not null check (quantity > 0 and quantity <= 100),
  unit_price_myr numeric(10,2) not null check (unit_price_myr >= 0),
  line_total_myr numeric(10,2) generated always as (quantity * unit_price_myr) stored
);

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  request_number text not null unique default ('SR-' || upper(substr(encode(gen_random_bytes(5),'hex'),1,8))),
  requester_id uuid not null references auth.users(id),
  booth text not null,
  request_type text not null,
  details text not null,
  status text not null default 'open' check (status in ('open','assigned','in_progress','completed','cancelled')),
  assigned_to uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists orders_guest_created_idx on public.orders(guest_id, created_at desc);
create index if not exists orders_vendor_status_idx on public.orders(vendor_id, status, created_at desc);
create index if not exists service_requests_status_idx on public.service_requests(status, created_at desc);
create index if not exists order_items_order_idx on public.order_items(order_id);

create or replace function public.current_user_role()
returns text language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_staff_or_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role in ('staff','admin'))
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at before update on public.profiles
for each row execute function public.touch_updated_at();
drop trigger if exists menu_items_touch_updated_at on public.menu_items;
create trigger menu_items_touch_updated_at before update on public.menu_items
for each row execute function public.touch_updated_at();
drop trigger if exists orders_touch_updated_at on public.orders;
create trigger orders_touch_updated_at before update on public.orders
for each row execute function public.touch_updated_at();
drop trigger if exists service_requests_touch_updated_at on public.service_requests;
create trigger service_requests_touch_updated_at before update on public.service_requests
for each row execute function public.touch_updated_at();

-- New accounts always start as guests. Never accept a role from signup metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), 'guest')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.vendors enable row level security;
alter table public.menu_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.service_requests enable row level security;

-- Profiles: users can read their own profile; staff/admin can read all.
drop policy if exists "profile read own or staff" on public.profiles;
create policy "profile read own or staff" on public.profiles for select to authenticated
using (id = auth.uid() or public.is_staff_or_admin());
drop policy if exists "admin manage profiles" on public.profiles;
create policy "admin manage profiles" on public.profiles for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Publicly readable active vendor/menu catalogue; only admins manage it.
drop policy if exists "active vendors visible" on public.vendors;
create policy "active vendors visible" on public.vendors for select to anon, authenticated using (active or public.is_staff_or_admin());
drop policy if exists "admin manage vendors" on public.vendors;
create policy "admin manage vendors" on public.vendors for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "available menu visible" on public.menu_items;
create policy "available menu visible" on public.menu_items for select to anon, authenticated using (available or public.is_staff_or_admin());
drop policy if exists "admin manage menu" on public.menu_items;
create policy "admin manage menu" on public.menu_items for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Orders: guests see their own; staff/admin see all; vendors see assigned vendor orders.
drop policy if exists "read authorised orders" on public.orders;
create policy "read authorised orders" on public.orders for select to authenticated
using (
  guest_id = auth.uid()
  or public.is_staff_or_admin()
  or exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'vendor' and p.vendor_id = orders.vendor_id)
);
drop policy if exists "guest create own orders" on public.orders;
create policy "guest create own orders" on public.orders for insert to authenticated
with check (guest_id = auth.uid() and status = 'received');
drop policy if exists "staff update orders" on public.orders;
create policy "staff update orders" on public.orders for update to authenticated
using (public.is_staff_or_admin() or exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'vendor' and p.vendor_id = orders.vendor_id))
with check (public.is_staff_or_admin() or exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'vendor' and p.vendor_id = orders.vendor_id));

-- Order lines inherit access from their parent order.
drop policy if exists "read authorised order items" on public.order_items;
create policy "read authorised order items" on public.order_items for select to authenticated
using (exists(select 1 from public.orders o where o.id = order_items.order_id));
drop policy if exists "guest add items to own received order" on public.order_items;
create policy "guest add items to own received order" on public.order_items for insert to authenticated
with check (exists(select 1 from public.orders o where o.id = order_items.order_id and o.guest_id = auth.uid() and o.status = 'received'));

-- Service requests: requester sees own; staff/admin manage; guests may create for themselves.
drop policy if exists "read authorised service requests" on public.service_requests;
create policy "read authorised service requests" on public.service_requests for select to authenticated
using (requester_id = auth.uid() or public.is_staff_or_admin());
drop policy if exists "guest create own service requests" on public.service_requests;
create policy "guest create own service requests" on public.service_requests for insert to authenticated
with check (requester_id = auth.uid() and status = 'open');
drop policy if exists "staff update service requests" on public.service_requests;
create policy "staff update service requests" on public.service_requests for update to authenticated
using (public.is_staff_or_admin()) with check (public.is_staff_or_admin());

-- Seed the four initial vendor records.
insert into public.vendors(name) values
 ('JDT Hospitality Kitchen'),
 ('Stadium Beverage Service'),
 ('Premium Lounge'),
 ('Concessions')
on conflict (name) do nothing;

-- Assign roles and vendor IDs manually in Supabase SQL Editor after users sign up.
-- Example:
-- update public.profiles set role = 'admin' where id = '<AUTH_USER_UUID>';
-- update public.profiles set role = 'vendor', vendor_id = (select id from public.vendors where name='Concessions')
-- where id = '<AUTH_USER_UUID>';


-- Trusted order creation: prices and totals are calculated from the database catalogue.
drop policy if exists "guest create own orders" on public.orders;
drop policy if exists "guest add items to own received order" on public.order_items;

create or replace function public.create_guest_order(
  p_guest_name text,
  p_booth text,
  p_vendor_id uuid,
  p_notes text,
  p_items jsonb
)
returns table(order_id uuid, order_number text, total_myr numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_total numeric(10,2);
  v_item jsonb;
  v_menu public.menu_items%rowtype;
  v_qty integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if length(trim(coalesce(p_guest_name,''))) = 0 or length(trim(coalesce(p_booth,''))) = 0 then
    raise exception 'Guest name and booth are required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one menu item is required';
  end if;
  if not exists(select 1 from public.vendors v where v.id=p_vendor_id and v.active) then
    raise exception 'Vendor is unavailable';
  end if;

  v_total := 0;
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty < 1 or v_qty > 100 then raise exception 'Invalid item quantity'; end if;
    select * into v_menu from public.menu_items
      where id=(v_item->>'menu_item_id')::uuid
        and vendor_id=p_vendor_id and available=true;
    if not found then raise exception 'Menu item unavailable for selected vendor'; end if;
    v_total := v_total + (v_menu.price_myr * v_qty);
  end loop;

  insert into public.orders(guest_id,guest_name,booth,vendor_id,notes,total_myr)
  values(auth.uid(),trim(p_guest_name),trim(p_booth),p_vendor_id,coalesce(p_notes,''),v_total)
  returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_menu from public.menu_items where id=(v_item->>'menu_item_id')::uuid;
    insert into public.order_items(order_id,menu_item_id,item_name,quantity,unit_price_myr)
    values(v_order_id,v_menu.id,v_menu.name,v_qty,v_menu.price_myr);
  end loop;

  return query select o.id,o.order_number,o.total_myr from public.orders o where o.id=v_order_id;
end;
$$;

revoke all on function public.create_guest_order(text,text,uuid,text,jsonb) from public, anon;
grant execute on function public.create_guest_order(text,text,uuid,text,jsonb) to authenticated;

-- Status changes are performed through a constrained function, not arbitrary row edits.
drop policy if exists "staff update orders" on public.orders;
create or replace function public.update_order_status(p_order_id uuid,p_status text)
returns void language plpgsql security definer
set search_path = public
as $$
declare v_role text; v_vendor_id uuid;
begin
  select role,vendor_id into v_role,v_vendor_id from public.profiles where id=auth.uid();
  if v_role is null or p_status not in ('received','accepted','preparing','ready','delivered','cancelled') then
    raise exception 'Not authorised or invalid status';
  end if;
  if v_role not in ('staff','admin','vendor') then raise exception 'Not authorised'; end if;
  if v_role='vendor' and not exists(select 1 from public.orders where id=p_order_id and vendor_id=v_vendor_id) then
    raise exception 'Order is not assigned to this vendor';
  end if;
  update public.orders set status=p_status where id=p_order_id;
  if not found then raise exception 'Order not found'; end if;
end;
$$;
revoke all on function public.update_order_status(uuid,text) from public, anon;
grant execute on function public.update_order_status(uuid,text) to authenticated;


-- Starter catalogue. Review prices, descriptions and availability before launch.
insert into public.menu_items(vendor_id,name,description,price_myr)
select v.id, x.name, x.description, x.price
from (values
 ('JDT Hospitality Kitchen','VIP Signature Burger','Beef patty, aged cheddar, house sauce',28.00::numeric),
 ('JDT Hospitality Kitchen','Grilled Chicken Wrap','Grilled chicken, fresh greens',22.00::numeric),
 ('Premium Lounge','Premium Fruit Platter','Seasonal fresh fruit selection',25.00::numeric),
 ('Stadium Beverage Service','Sparkling Water','Chilled bottled water',8.00::numeric),
 ('Stadium Beverage Service','Fresh Orange Juice','Freshly prepared juice',12.00::numeric),
 ('Premium Lounge','Coffee','Espresso-based hot coffee',12.00::numeric),
 ('Concessions','Nachos & Cheese','Crispy nachos with cheese dip',18.00::numeric),
 ('Concessions','Soft Drink','Chilled soft drink',7.00::numeric)
) as x(vendor_name,name,description,price)
join public.vendors v on v.name=x.vendor_name
where not exists (
 select 1 from public.menu_items m where m.vendor_id=v.id and m.name=x.name
);
