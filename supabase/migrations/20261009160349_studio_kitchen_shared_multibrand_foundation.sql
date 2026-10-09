-- Shared, fail-closed foundation for future Nora Burgers and Crust & Coal services.
-- This migration creates schema only: it inserts no brand, location, menu, price, or credential data.

create schema if not exists studio_kitchen_private;
revoke all on schema studio_kitchen_private from public, anon, authenticated;
grant usage on schema studio_kitchen_private to authenticated, service_role;

create table public.brands (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  address_line_1 text,
  address_line_2 text,
  locality text,
  region text,
  postal_code text,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  timezone text,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.brand_locations (
  brand_id uuid not null references public.brands (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (brand_id, location_id)
);

create table public.menus (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  location_id uuid not null,
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  is_active boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (brand_id, location_id, slug),
  unique (id, brand_id),
  unique (id, brand_id, location_id, currency_code),
  foreign key (brand_id, location_id)
    references public.brand_locations (brand_id, location_id) on delete restrict
);

create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  menu_id uuid not null,
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  sort_order integer not null default 0 check (sort_order >= 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (menu_id, slug),
  unique (id, menu_id, brand_id),
  foreign key (menu_id, brand_id)
    references public.menus (id, brand_id) on delete restrict
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  menu_id uuid not null,
  category_id uuid not null,
  slug text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null check (length(btrim(name)) > 0),
  description text,
  price_minor bigint not null check (price_minor >= 0),
  sort_order integer not null default 0 check (sort_order >= 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  unique (menu_id, slug),
  unique (id, brand_id, menu_id),
  foreign key (category_id, menu_id, brand_id)
    references public.menu_categories (id, menu_id, brand_id) on delete restrict
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.brands (id) on delete restrict,
  email text check (email is null or length(btrim(email)) > 0),
  phone text check (phone is null or length(btrim(phone)) > 0),
  display_name text check (display_name is null or length(btrim(display_name)) > 0),
  created_at timestamptz not null default now(),
  unique (id, brand_id)
);

create table public.collection_slots (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  location_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity integer not null check (capacity > 0),
  status text not null default 'closed' check (status in ('open', 'closed', 'cancelled')),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  unique (id, brand_id, location_id),
  foreign key (brand_id, location_id)
    references public.brand_locations (brand_id, location_id) on delete restrict
);

create table public.collection_holds (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  location_id uuid not null,
  slot_id uuid not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  status text not null default 'active' check (status in ('active', 'consumed', 'released')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  released_at timestamptz,
  check (expires_at > created_at),
  check ((status = 'consumed') = (consumed_at is not null)),
  check ((status = 'released') = (released_at is not null)),
  unique (id, brand_id, location_id, slot_id),
  foreign key (slot_id, brand_id, location_id)
    references public.collection_slots (id, brand_id, location_id) on delete restrict
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  location_id uuid not null,
  menu_id uuid not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  collection_slot_id uuid not null,
  collection_hold_id uuid not null,
  customer_id uuid,
  checkout_idempotency_key text not null
    check (length(checkout_idempotency_key) between 1 and 255),
  status text not null default 'pending_payment'
    check (status in ('pending_payment', 'confirmed', 'preparing', 'ready', 'collected', 'cancelled')),
  total_amount_minor bigint not null check (total_amount_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, checkout_idempotency_key),
  unique (collection_hold_id),
  unique (id, brand_id),
  unique (id, brand_id, currency_code),
  unique (id, brand_id, menu_id),
  foreign key (brand_id, location_id)
    references public.brand_locations (brand_id, location_id) on delete restrict,
  foreign key (menu_id, brand_id, location_id, currency_code)
    references public.menus (id, brand_id, location_id, currency_code) on delete restrict,
  foreign key (collection_slot_id, brand_id, location_id)
    references public.collection_slots (id, brand_id, location_id) on delete restrict,
  foreign key (collection_hold_id, brand_id, location_id, collection_slot_id)
    references public.collection_holds (id, brand_id, location_id, slot_id) on delete restrict,
  foreign key (customer_id, brand_id)
    references public.customers (id, brand_id) on delete restrict
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  order_id uuid not null,
  menu_id uuid not null,
  menu_item_id uuid not null,
  item_name_snapshot text not null check (length(btrim(item_name_snapshot)) > 0),
  quantity integer not null check (quantity > 0),
  unit_amount_minor bigint not null check (unit_amount_minor >= 0),
  line_total_minor bigint not null check (line_total_minor >= 0),
  created_at timestamptz not null default now(),
  check (line_total_minor::numeric = unit_amount_minor::numeric * quantity::numeric),
  foreign key (order_id, brand_id, menu_id)
    references public.orders (id, brand_id, menu_id) on delete restrict,
  foreign key (menu_item_id, brand_id, menu_id)
    references public.menu_items (id, brand_id, menu_id) on delete restrict
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  order_id uuid not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  provider text not null check (length(btrim(provider)) > 0),
  provider_payment_id text,
  idempotency_key text not null check (length(idempotency_key) between 1 and 255),
  status text not null default 'pending'
    check (status in ('pending', 'authorized', 'paid', 'failed', 'partially_refunded', 'refunded', 'cancelled')),
  amount_minor bigint not null check (amount_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (brand_id, idempotency_key),
  foreign key (order_id, brand_id, currency_code)
    references public.orders (id, brand_id, currency_code) on delete restrict
);

create table public.collection_codes (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  order_id uuid not null,
  code_hash text not null check (code_hash ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at),
  unique (brand_id, code_hash),
  foreign key (order_id, brand_id)
    references public.orders (id, brand_id) on delete restrict
);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null,
  order_id uuid not null,
  status text not null
    check (status in ('pending_payment', 'confirmed', 'preparing', 'ready', 'collected', 'cancelled')),
  changed_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (order_id, brand_id)
    references public.orders (id, brand_id) on delete restrict
);

create table public.stripe_webhook_events (
  id uuid primary key default gen_random_uuid(),
  stripe_event_id text not null unique check (length(btrim(stripe_event_id)) > 0),
  event_type text not null check (length(btrim(event_type)) > 0),
  status text not null default 'received' check (status in ('received', 'processing', 'processed', 'failed')),
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  check ((status = 'processed') = (processed_at is not null))
);

create table public.brand_members (
  brand_id uuid not null references public.brands (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'kitchen')),
  created_at timestamptz not null default now(),
  primary key (brand_id, user_id)
);

create index brand_locations_location_idx on public.brand_locations (location_id, brand_id);
create index menus_brand_location_active_idx on public.menus (brand_id, location_id, is_active);
create index menu_categories_menu_brand_sort_idx on public.menu_categories (menu_id, brand_id, sort_order);
create index menu_items_category_fk_idx on public.menu_items (category_id, menu_id, brand_id);
create index menu_items_brand_menu_category_sort_idx on public.menu_items (brand_id, menu_id, category_id, sort_order);
create index customers_brand_created_idx on public.customers (brand_id, created_at desc);
create unique index customers_brand_email_lower_idx
  on public.customers (brand_id, lower(email)) where email is not null;
create index collection_slots_brand_location_start_idx
  on public.collection_slots (brand_id, location_id, starts_at) where status = 'open';
create index collection_holds_slot_status_expiry_idx
  on public.collection_holds (slot_id, status, expires_at);
create index orders_kds_queue_idx on public.orders (brand_id, location_id, status, created_at);
create index orders_menu_fk_idx on public.orders (menu_id, brand_id, location_id, currency_code);
create index orders_collection_slot_fk_idx on public.orders (collection_slot_id, brand_id, location_id);
create index orders_customer_created_idx on public.orders (brand_id, customer_id, created_at desc)
  where customer_id is not null;
create index orders_customer_fk_idx on public.orders (customer_id, brand_id) where customer_id is not null;
create index order_items_order_idx on public.order_items (order_id, brand_id, menu_id);
create index order_items_menu_item_idx on public.order_items (menu_item_id, brand_id, menu_id);
create index payments_order_created_idx on public.payments (brand_id, order_id, created_at desc);
create index payments_order_fk_idx on public.payments (order_id, brand_id, currency_code);
create unique index payments_provider_reference_idx
  on public.payments (provider, provider_payment_id) where provider_payment_id is not null;
create index collection_codes_order_idx on public.collection_codes (order_id, brand_id);
create index order_status_history_order_created_idx
  on public.order_status_history (order_id, brand_id, created_at);
create index order_status_history_changed_by_idx
  on public.order_status_history (changed_by) where changed_by is not null;
create index stripe_webhook_events_processing_idx
  on public.stripe_webhook_events (status, received_at);
create index brand_members_user_brand_idx on public.brand_members (user_id, brand_id);

create or replace function studio_kitchen_private.has_brand_role(
  p_brand_id uuid,
  p_roles text[] default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.brand_members as bm
    where bm.brand_id = p_brand_id
      and bm.user_id = (select auth.uid())
      and (p_roles is null or bm.role = any (p_roles))
  );
$$;

revoke all on function studio_kitchen_private.has_brand_role(uuid, text[]) from public, anon;
grant execute on function studio_kitchen_private.has_brand_role(uuid, text[]) to authenticated;

create or replace function studio_kitchen_private.record_order_status_history()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.order_status_history (brand_id, order_id, status, changed_by)
  values (new.brand_id, new.id, new.status, (select auth.uid()));
  return new;
end;
$$;

revoke all on function studio_kitchen_private.record_order_status_history() from public, anon, authenticated;
grant execute on function studio_kitchen_private.record_order_status_history() to service_role;

create trigger orders_record_initial_status
  after insert on public.orders
  for each row execute function studio_kitchen_private.record_order_status_history();

create trigger orders_record_status_change
  after update of status on public.orders
  for each row
  when (old.status is distinct from new.status)
  execute function studio_kitchen_private.record_order_status_history();

alter table public.brands enable row level security;
alter table public.locations enable row level security;
alter table public.brand_locations enable row level security;
alter table public.menus enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.collection_slots enable row level security;
alter table public.collection_holds enable row level security;
alter table public.collection_codes enable row level security;
alter table public.order_status_history enable row level security;
alter table public.stripe_webhook_events enable row level security;
alter table public.brand_members enable row level security;

create policy brands_public_read_active
  on public.brands for select to anon, authenticated
  using (is_active);

create policy locations_public_read_active
  on public.locations for select to anon, authenticated
  using (is_active);

create policy brand_locations_public_read_active
  on public.brand_locations for select to anon, authenticated
  using (
    is_active
    and exists (
      select 1 from public.brands as b
      where b.id = brand_locations.brand_id and b.is_active
    )
    and exists (
      select 1 from public.locations as l
      where l.id = brand_locations.location_id and l.is_active
    )
  );

create policy menus_public_read_published
  on public.menus for select to anon, authenticated
  using (
    is_active
    and published_at <= statement_timestamp()
    and exists (
      select 1 from public.brand_locations as bl
      where bl.brand_id = menus.brand_id
        and bl.location_id = menus.location_id
        and bl.is_active
    )
  );

create policy menu_categories_public_read_active
  on public.menu_categories for select to anon, authenticated
  using (
    is_active
    and exists (
      select 1 from public.menus as m
      where m.id = menu_categories.menu_id and m.brand_id = menu_categories.brand_id
    )
  );

create policy menu_items_public_read_active
  on public.menu_items for select to anon, authenticated
  using (
    is_active
    and exists (
      select 1 from public.menu_categories as mc
      where mc.id = menu_items.category_id
        and mc.menu_id = menu_items.menu_id
        and mc.brand_id = menu_items.brand_id
    )
  );

create policy customers_brand_managers_read
  on public.customers for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager']::text[]));

create policy orders_brand_staff_read
  on public.orders for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager', 'kitchen']::text[]));

create policy order_items_brand_staff_read
  on public.order_items for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager', 'kitchen']::text[]));

create policy payments_brand_managers_read
  on public.payments for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager']::text[]));

create policy collection_slots_brand_staff_read
  on public.collection_slots for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager', 'kitchen']::text[]));

create policy order_status_history_brand_staff_read
  on public.order_status_history for select to authenticated
  using (studio_kitchen_private.has_brand_role(brand_id, array['owner', 'manager', 'kitchen']::text[]));

create policy brand_members_read_own_membership
  on public.brand_members for select to authenticated
  using (user_id = (select auth.uid()));

-- Clients receive read-only access only where RLS defines an explicit read path.
-- Holds, codes, payments writes, orders writes, and webhook events stay server-only.
revoke all on table
  public.brands,
  public.locations,
  public.brand_locations,
  public.menus,
  public.menu_categories,
  public.menu_items,
  public.customers,
  public.orders,
  public.order_items,
  public.payments,
  public.collection_slots,
  public.collection_holds,
  public.collection_codes,
  public.order_status_history,
  public.stripe_webhook_events,
  public.brand_members
from public, anon, authenticated;

grant select on table
  public.brands,
  public.locations,
  public.brand_locations,
  public.menus,
  public.menu_categories,
  public.menu_items
 to anon, authenticated;

grant select on table
  public.customers,
  public.order_items,
  public.payments,
  public.collection_slots,
  public.order_status_history,
  public.brand_members
 to authenticated;

grant select (id, brand_id, location_id, menu_id, currency_code, collection_slot_id, status, total_amount_minor, created_at, updated_at)
  on table public.orders to authenticated;

grant all on table
  public.brands,
  public.locations,
  public.brand_locations,
  public.menus,
  public.menu_categories,
  public.menu_items,
  public.customers,
  public.orders,
  public.order_items,
  public.payments,
  public.collection_slots,
  public.collection_holds,
  public.collection_codes,
  public.order_status_history,
  public.stripe_webhook_events,
  public.brand_members
 to service_role;

comment on table public.orders is
  'Shared order record; client writes are intentionally disabled. Server checkout must validate menu prices, totals, hold expiry, and slot capacity transactionally.';
comment on table public.collection_holds is
  'Stores only a hash of a cryptographically random high-entropy hold token. Server checkout must create and consume holds atomically to prevent slot overbooking.';
comment on table public.collection_codes is
  'Stores only a 64-character hash; use HMAC-SHA-256 for short human-entered codes or a high-entropy random code, and verify server-side with rate limits. Never store raw codes.';
comment on table public.stripe_webhook_events is
  'Deduplication metadata only; never store webhook signing secrets or raw request secrets here.';

commit;
