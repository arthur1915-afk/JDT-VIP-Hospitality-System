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
drop policy if exists "profile update own name only" on public.profiles;
create policy "profile update own name only" on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid() and role = (select p.role from public.profiles p where p.id = auth.uid()) and vendor_id is not distinct from (select p.vendor_id from public.profiles p where p.id = auth.uid()));
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
