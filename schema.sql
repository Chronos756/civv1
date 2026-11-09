-- WallWatch database setup.
-- Run in Supabase: SQL Editor > New query > paste this whole file > Run.

-- 1. Tables ---------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'customer' check (role in ('customer', 'technician', 'admin')),
  created_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price_inr numeric(10, 2) not null check (price_inr >= 0),
  category text not null check (category in ('sensor', 'pipe', 'accessory')),
  image_url text,
  stock integer not null default 0 check (stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id),
  total_inr numeric(10, 2) not null check (total_inr >= 0),
  status text not null default 'pending' check (status in ('pending', 'paid', 'shipped', 'delivered', 'cancelled')),
  created_at timestamptz not null default now()
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  product_id uuid not null references public.products (id),
  quantity integer not null check (quantity > 0),
  unit_price_inr numeric(10, 2) not null check (unit_price_inr >= 0)
);

create table public.technicians (
  id uuid primary key references public.profiles (id) on delete cascade,
  city text,
  experience_years integer check (experience_years >= 0),
  bio text,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id),
  technician_id uuid references public.technicians (id),
  address text not null,
  city text not null,
  preferred_date date,
  details text,
  status text not null default 'open' check (status in ('open', 'accepted', 'completed', 'cancelled')),
  created_at timestamptz not null default now()
);

-- 2. Create a profile automatically when someone signs up -------------------
-- Everyone starts as 'customer'. Make yourself admin by hand (see notes at bottom).

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3. Row Level Security: nobody can touch data unless a policy allows it -----

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.technicians enable row level security;
alter table public.service_requests enable row level security;

-- Anyone can browse active products. Nobody can change them from the website.
create policy "Anyone can view active products"
  on public.products for select
  using (is_active = true);

-- People can read their own profile. (No update policy yet: otherwise a user
-- could change their own role to admin. We'll add a safe one later.)
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- Customers see and create only their own orders.
create policy "Users can view own orders"
  on public.orders for select
  using (auth.uid() = user_id);

create policy "Users can create own orders"
  on public.orders for insert
  with check (auth.uid() = user_id);

create policy "Users can view own order items"
  on public.order_items for select
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

create policy "Users can add items to own orders"
  on public.order_items for insert
  with check (exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid()));

-- Customers see and create only their own service requests.
create policy "Customers can view own service requests"
  on public.service_requests for select
  using (auth.uid() = customer_id);

create policy "Customers can create own service requests"
  on public.service_requests for insert
  with check (auth.uid() = customer_id);

-- Technician and admin policies come in later build steps.

-- 4. Sample products (placeholder prices: replace with your real ones) ------

insert into public.products (name, description, price_inr, category, stock) values
  ('Acoustic Leak Sensor', 'Wall-mount sensor that listens for the hiss of a leaking pipe.', 1999, 'sensor', 20),
  ('Sensor Starter Kit (3 units)', 'Three sensors and a hub to cover a small flat.', 4999, 'sensor', 10),
  ('Monitorable Pipe, 3 m', 'Pipe section with sensor mounting points built in.', 899, 'pipe', 50),
  ('Sensor Mounting Kit', 'Clamps and adhesive pads for fixing sensors to pipes.', 299, 'accessory', 100);

-- Notes ----------------------------------------------------------------------
-- To make yourself an admin after signing up, run this with your own email:
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'you@example.com');
