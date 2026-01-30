-- ============================================================================
-- E-COMMERCE DATA WAREHOUSE SCHEMA
-- Comprehensive schema for Shopify + Klaviyo + Advertising Platforms
-- ============================================================================

-- Enable required extensions
create extension if not exists pgcrypto;
create extension if not exists vector; -- Keep for future vector search on product descriptions

-- ============================================================================
-- 1. CUSTOMER & IDENTITY LAYER
-- ============================================================================

-- Unified customer master table - single source of truth across all systems
create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  shopify_customer_id text unique,
  klaviyo_profile_id text unique,
  email text not null unique,
  phone text,
  first_name text,
  last_name text,
  location_country text,
  location_region text,
  location_city text,
  timezone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_first_time_customer boolean default true,
  total_orders int default 0,
  total_revenue decimal(12,2) default 0,
  average_order_value decimal(12,2) default 0,
  first_order_date date,
  last_order_date date,
  tags text[],
  marketing_consent_email boolean default false,
  marketing_consent_sms boolean default false,
  source text -- 'shopify' | 'klaviyo' | 'api' | 'form' | etc.
);

create index if not exists customers_email_idx on customers(email);
create index if not exists customers_shopify_id_idx on customers(shopify_customer_id) where shopify_customer_id is not null;
create index if not exists customers_klaviyo_id_idx on customers(klaviyo_profile_id) where klaviyo_profile_id is not null;
create index if not exists customers_tags_idx on customers using gin(tags);

-- Customer addresses
create table if not exists customer_addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  shopify_address_id text,
  type text not null, -- 'shipping' | 'billing'
  is_default boolean default false,
  address_line1 text,
  address_line2 text,
  city text,
  province text,
  postal_code text,
  country text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customer_addresses_customer_id_idx on customer_addresses(customer_id);

-- ============================================================================
-- 2. SHOPIFY COMMERCE LAYER
-- ============================================================================

-- Shopify orders
create table if not exists shopify_orders (
  id uuid primary key default gen_random_uuid(),
  shopify_order_id text not null unique,
  customer_id uuid references customers(id),
  order_number text,
  order_date timestamptz not null,
  source text, -- 'online_store' | 'pos' | 'draft_order' | 'api' | 'shopify_draft' | etc.
  financial_status text, -- 'paid' | 'pending' | 'refunded' | 'voided' | 'partially_paid' | 'partially_refunded'
  fulfillment_status text, -- 'fulfilled' | 'partial' | 'unfulfilled' | null
  subtotal_price decimal(12,2) not null,
  total_tax decimal(12,2) default 0,
  total_discounts decimal(12,2) default 0,
  total_price decimal(12,2) not null,
  currency_code text default 'USD',
  payment_gateway text,
  payment_method text,
  discount_codes text[],
  tags text[],
  refund_status text, -- 'full' | 'partial' | null
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shopify_orders_customer_id_idx on shopify_orders(customer_id);
create index if not exists shopify_orders_date_idx on shopify_orders(order_date);
create index if not exists shopify_orders_status_idx on shopify_orders(financial_status);
create index if not exists shopify_orders_source_idx on shopify_orders(source);

-- Shopify products
create table if not exists shopify_products (
  id uuid primary key default gen_random_uuid(),
  shopify_product_id text not null unique,
  title text not null,
  handle text,
  product_type text,
  vendor text,
  collection_ids text[],
  tags text[],
  published_at timestamptz,
  status text default 'active', -- 'active' | 'archived' | 'draft'
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shopify_products_handle_idx on shopify_products(handle);
create index if not exists shopify_products_status_idx on shopify_products(status);
create index if not exists shopify_products_tags_idx on shopify_products using gin(tags);

-- Shopify product variants
create table if not exists shopify_product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references shopify_products(id) on delete cascade,
  shopify_variant_id text not null unique,
  sku text unique,
  title text,
  price decimal(12,2) not null,
  cost decimal(12,2), -- For margin calculation
  compare_at_price decimal(12,2),
  inventory_quantity int default 0,
  inventory_policy text default 'deny', -- 'deny' | 'continue'
  option1 text, -- e.g., "Small", "Red"
  option2 text,
  option3 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists shopify_variants_product_id_idx on shopify_product_variants(product_id);
create index if not exists shopify_variants_sku_idx on shopify_product_variants(sku) where sku is not null;
create index if not exists shopify_variants_inventory_idx on shopify_product_variants(inventory_quantity);

-- Shopify order line items
create table if not exists shopify_order_line_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references shopify_orders(id) on delete cascade,
  shopify_line_item_id text not null,
  product_id uuid references shopify_products(id),
  variant_id uuid references shopify_product_variants(id),
  sku text,
  title text,
  quantity int not null,
  price decimal(12,2) not null,
  total_discount decimal(12,2) default 0,
  total_tax decimal(12,2) default 0,
  line_total decimal(12,2) not null, -- (price * quantity) - discount + tax
  fulfillment_status text,
  created_at timestamptz not null default now()
);

create index if not exists shopify_line_items_order_id_idx on shopify_order_line_items(order_id);
create index if not exists shopify_line_items_product_id_idx on shopify_order_line_items(product_id);
create index if not exists shopify_line_items_variant_id_idx on shopify_order_line_items(variant_id);

-- ============================================================================
-- 3. KLAVIYO MARKETING LAYER
-- ============================================================================

-- Klaviyo profiles (synced with customers table)
create table if not exists klaviyo_profiles (
  id uuid primary key default gen_random_uuid(),
  klaviyo_profile_id text not null unique,
  customer_id uuid references customers(id),
  email text not null,
  phone text,
  first_name text,
  last_name text,
  location_properties jsonb, -- Timezone, country, region, city
  properties jsonb, -- Custom Klaviyo properties
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists klaviyo_profiles_customer_id_idx on klaviyo_profiles(customer_id);
create index if not exists klaviyo_profiles_email_idx on klaviyo_profiles(email);
create index if not exists klaviyo_profiles_properties_idx on klaviyo_profiles using gin(properties);

-- Klaviyo campaigns (Email/SMS campaigns)
create table if not exists klaviyo_campaigns (
  id uuid primary key default gen_random_uuid(),
  klaviyo_campaign_id text not null unique,
  name text not null,
  type text not null, -- 'email' | 'sms'
  send_date timestamptz,
  status text, -- 'sent' | 'draft' | 'scheduled' | 'cancelled'
  recipients_count int default 0,
  delivered_count int default 0,
  opens_count int default 0,
  unique_opens_count int default 0,
  clicks_count int default 0,
  unique_clicks_count int default 0,
  unsubscribes_count int default 0,
  bounces_count int default 0,
  spam_reports_count int default 0,
  revenue decimal(12,2) default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists klaviyo_campaigns_send_date_idx on klaviyo_campaigns(send_date);
create index if not exists klaviyo_campaigns_type_idx on klaviyo_campaigns(type);
create index if not exists klaviyo_campaigns_status_idx on klaviyo_campaigns(status);

-- Klaviyo flows (Automation workflows: Abandoned Cart, Welcome Series, etc.)
create table if not exists klaviyo_flows (
  id uuid primary key default gen_random_uuid(),
  klaviyo_flow_id text not null unique,
  name text not null,
  trigger_type text, -- 'abandoned_cart' | 'welcome_series' | 'browse_abandonment' | 'post_purchase' | etc.
  status text, -- 'live' | 'draft' | 'archived'
  recipients_entered_count int default 0,
  conversion_count int default 0,
  revenue decimal(12,2) default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists klaviyo_flows_trigger_type_idx on klaviyo_flows(trigger_type);
create index if not exists klaviyo_flows_status_idx on klaviyo_flows(status);

-- Klaviyo flow steps (Individual emails/actions within a flow)
create table if not exists klaviyo_flow_steps (
  id uuid primary key default gen_random_uuid(),
  flow_id uuid not null references klaviyo_flows(id) on delete cascade,
  klaviyo_step_id text not null,
  step_name text,
  step_order int not null, -- Position in flow (1, 2, 3...)
  step_type text, -- 'email' | 'delay' | 'split' | 'wait' | etc.
  recipients_count int default 0,
  opens_count int default 0,
  clicks_count int default 0,
  conversions_count int default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(flow_id, step_order)
);

create index if not exists klaviyo_flow_steps_flow_id_idx on klaviyo_flow_steps(flow_id);

-- Klaviyo lists
create table if not exists klaviyo_lists (
  id uuid primary key default gen_random_uuid(),
  klaviyo_list_id text not null unique,
  name text not null,
  profile_count int default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Klaviyo segments
create table if not exists klaviyo_segments (
  id uuid primary key default gen_random_uuid(),
  klaviyo_segment_id text not null unique,
  name text not null,
  rule_logic jsonb, -- Conditions that define segment
  profile_count int default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists klaviyo_segments_rule_logic_idx on klaviyo_segments using gin(rule_logic);

-- Junction table: Profiles in Lists
create table if not exists klaviyo_profile_lists (
  profile_id uuid not null references klaviyo_profiles(id) on delete cascade,
  list_id uuid not null references klaviyo_lists(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (profile_id, list_id)
);

create index if not exists klaviyo_profile_lists_list_id_idx on klaviyo_profile_lists(list_id);

-- Klaviyo predictive metrics (AI predictions per profile)
create table if not exists klaviyo_predictive_metrics (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references klaviyo_profiles(id) on delete cascade,
  predicted_next_order_date date,
  predicted_churn_probability decimal(5,4), -- 0.0 to 1.0
  predicted_lifetime_value decimal(12,2), -- PLTV
  predicted_gender text,
  email_engagement_probability decimal(5,4), -- 0.0 to 1.0
  calculated_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(profile_id, calculated_at)
);

create index if not exists klaviyo_predictive_metrics_profile_id_idx on klaviyo_predictive_metrics(profile_id);
create index if not exists klaviyo_predictive_metrics_churn_idx on klaviyo_predictive_metrics(predicted_churn_probability);

-- ============================================================================
-- 4. EVENT LAYER (Behavioral Tracking)
-- ============================================================================

-- Shopify store events
create table if not exists shopify_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null, -- 'page_viewed' | 'product_viewed' | 'cart_added' | 'checkout_started' | 'checkout_completed' | 'purchase'
  customer_id uuid references customers(id),
  order_id uuid references shopify_orders(id),
  product_id uuid references shopify_products(id),
  session_id text,
  event_properties jsonb, -- Flexible event data (UTMs, referrer, device, etc.)
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists shopify_events_event_type_idx on shopify_events(event_type);
create index if not exists shopify_events_occurred_at_idx on shopify_events(occurred_at);
create index if not exists shopify_events_customer_id_idx on shopify_events(customer_id);
create index if not exists shopify_events_session_id_idx on shopify_events(session_id) where session_id is not null;
create index if not exists shopify_events_properties_idx on shopify_events using gin(event_properties);
create index if not exists shopify_events_order_id_idx on shopify_events(order_id) where order_id is not null;

-- Klaviyo behavioral events
create table if not exists klaviyo_events (
  id uuid primary key default gen_random_uuid(),
  klaviyo_event_id text unique,
  event_type text not null, -- 'Viewed Product' | 'Added to Cart' | 'Started Checkout' | 'Placed Order' | 'Opened Email' | 'Clicked Email' | 'Unsubscribed' | etc.
  profile_id uuid references klaviyo_profiles(id),
  customer_id uuid references customers(id),
  campaign_id uuid references klaviyo_campaigns(id),
  flow_id uuid references klaviyo_flows(id),
  event_properties jsonb, -- Event-specific data
  occurred_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists klaviyo_events_event_type_idx on klaviyo_events(event_type);
create index if not exists klaviyo_events_occurred_at_idx on klaviyo_events(occurred_at);
create index if not exists klaviyo_events_profile_id_idx on klaviyo_events(profile_id);
create index if not exists klaviyo_events_campaign_id_idx on klaviyo_events(campaign_id) where campaign_id is not null;
create index if not exists klaviyo_events_properties_idx on klaviyo_events using gin(event_properties);

-- Advertising platform events (Meta, Google, TikTok, etc.)
create table if not exists ad_events (
  id uuid primary key default gen_random_uuid(),
  platform text not null, -- 'meta' | 'google' | 'tiktok' | 'pinterest' | 'linkedin'
  campaign_id text,
  ad_set_id text,
  ad_id text,
  event_type text, -- 'impression' | 'click' | 'conversion' | 'purchase'
  customer_id uuid references customers(id),
  order_id uuid references shopify_orders(id),
  spend decimal(12,2),
  impressions int,
  clicks int,
  conversions int,
  revenue decimal(12,2),
  date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ad_events_platform_idx on ad_events(platform);
create index if not exists ad_events_date_idx on ad_events(date);
create index if not exists ad_events_campaign_id_idx on ad_events(campaign_id) where campaign_id is not null;
create index if not exists ad_events_customer_id_idx on ad_events(customer_id) where customer_id is not null;
create index if not exists ad_events_order_id_idx on ad_events(order_id) where order_id is not null;

-- ============================================================================
-- 5. ANALYTICS & AGGREGATION LAYER
-- ============================================================================

-- Daily customer metrics (pre-aggregated for performance)
create table if not exists customer_metrics_daily (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  date date not null,
  orders_count int default 0,
  revenue decimal(12,2) default 0,
  products_viewed_count int default 0,
  cart_adds_count int default 0,
  checkouts_started_count int default 0,
  emails_opened_count int default 0,
  emails_clicked_count int default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(customer_id, date)
);

create index if not exists customer_metrics_daily_customer_id_idx on customer_metrics_daily(customer_id);
create index if not exists customer_metrics_daily_date_idx on customer_metrics_daily(date);

-- Daily campaign performance
create table if not exists campaign_performance_daily (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references klaviyo_campaigns(id) on delete cascade,
  date date not null,
  sent_count int default 0,
  delivered_count int default 0,
  opens_count int default 0,
  clicks_count int default 0,
  unsubscribes_count int default 0,
  revenue decimal(12,2) default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(campaign_id, date)
);

create index if not exists campaign_performance_daily_campaign_id_idx on campaign_performance_daily(campaign_id);
create index if not exists campaign_performance_daily_date_idx on campaign_performance_daily(date);

-- Daily product performance
create table if not exists product_performance_daily (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references shopify_products(id) on delete cascade,
  date date not null,
  views_count int default 0,
  cart_adds_count int default 0,
  orders_count int default 0,
  units_sold int default 0,
  revenue decimal(12,2) default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id, date)
);

create index if not exists product_performance_daily_product_id_idx on product_performance_daily(product_id);
create index if not exists product_performance_daily_date_idx on product_performance_daily(date);

-- ============================================================================
-- COMPUTED COLUMNS & VIEWS (PostgreSQL functions for common metrics)
-- ============================================================================

-- Function to calculate AOV (Average Order Value)
create or replace function calculate_aov(customer_uuid uuid)
returns decimal(12,2) as $$
  select coalesce(avg(total_price), 0)
  from shopify_orders
  where customer_id = customer_uuid
    and financial_status = 'paid';
$$ language sql stable;

-- Function to calculate email open rate for a campaign
create or replace function calculate_open_rate(campaign_uuid uuid)
returns decimal(5,4) as $$
  select case
    when delivered_count > 0 then unique_opens_count::decimal / delivered_count
    else 0
  end
  from klaviyo_campaigns
  where id = campaign_uuid;
$$ language sql stable;

-- Function to calculate email click rate for a campaign
create or replace function calculate_click_rate(campaign_uuid uuid)
returns decimal(5,4) as $$
  select case
    when delivered_count > 0 then unique_clicks_count::decimal / delivered_count
    else 0
  end
  from klaviyo_campaigns
  where id = campaign_uuid;
$$ language sql stable;

-- Function to calculate ROAS (Return on Ad Spend)
create or replace function calculate_roas(ad_event_uuid uuid)
returns decimal(10,2) as $$
  select case
    when spend > 0 then revenue / spend
    else 0
  end
  from ad_events
  where id = ad_event_uuid;
$$ language sql stable;

-- View: Customer lifetime metrics
create or replace view customer_lifetime_metrics as
select
  c.id as customer_id,
  c.email,
  c.total_orders,
  c.total_revenue,
  c.average_order_value,
  c.first_order_date,
  c.last_order_date,
  case
    when c.last_order_date is not null then (now()::date - c.last_order_date)::integer
    else null
  end as days_since_last_order,
  case
    when c.total_orders > 1 then true
    else false
  end as is_repeat_customer,
  (select count(*) from shopify_orders o where o.customer_id = c.id and o.financial_status = 'refunded') as refunded_orders_count,
  (select sum(o.total_price) from shopify_orders o where o.customer_id = c.id and o.financial_status = 'refunded') as total_refunded
from customers c;

-- View: Campaign performance summary
create or replace view campaign_performance_summary as
select
  kc.id as campaign_id,
  kc.name,
  kc.type,
  kc.send_date,
  kc.recipients_count,
  kc.delivered_count,
  kc.unique_opens_count,
  kc.unique_clicks_count,
  kc.unsubscribes_count,
  kc.revenue,
  calculate_open_rate(kc.id) as open_rate,
  calculate_click_rate(kc.id) as click_rate,
  case
    when kc.delivered_count > 0 then kc.unsubscribes_count::decimal / kc.delivered_count
    else 0
  end as unsubscribe_rate,
  case
    when kc.delivered_count > 0 then kc.revenue / kc.delivered_count
    else 0
  end as revenue_per_delivered
from klaviyo_campaigns kc;

-- View: Product performance summary
create or replace view product_performance_summary as
select
  sp.id as product_id,
  sp.title,
  sp.handle,
  sp.status,
  (select sum(oli.quantity) from shopify_order_line_items oli where oli.product_id = sp.id) as total_units_sold,
  (select sum(oli.line_total) from shopify_order_line_items oli 
   join shopify_orders so on oli.order_id = so.id 
   where oli.product_id = sp.id and so.financial_status = 'paid') as total_revenue,
  (select count(distinct oli.order_id) from shopify_order_line_items oli where oli.product_id = sp.id) as orders_count,
  (select count(*) from shopify_events se where se.product_id = sp.id and se.event_type = 'product_viewed') as total_views,
  (select count(*) from shopify_events se where se.product_id = sp.id and se.event_type = 'cart_added') as total_cart_adds,
  case
    when (select count(*) from shopify_events se where se.product_id = sp.id and se.event_type = 'product_viewed') > 0
    then (select count(distinct oli.order_id)::decimal 
          from shopify_order_line_items oli
          where oli.product_id = sp.id) / 
          (select count(*)::decimal from shopify_events se where se.product_id = sp.id and se.event_type = 'product_viewed')
    else 0
  end as conversion_rate
from shopify_products sp;

-- ============================================================================
-- TRIGGERS FOR AUTOMATIC UPDATES
-- ============================================================================

-- Trigger to update customers.updated_at
create or replace function update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Apply updated_at trigger to all tables with updated_at column
create trigger customers_updated_at before update on customers
  for each row execute function update_updated_at_column();

create trigger customer_addresses_updated_at before update on customer_addresses
  for each row execute function update_updated_at_column();

create trigger shopify_orders_updated_at before update on shopify_orders
  for each row execute function update_updated_at_column();

create trigger shopify_products_updated_at before update on shopify_products
  for each row execute function update_updated_at_column();

create trigger shopify_product_variants_updated_at before update on shopify_product_variants
  for each row execute function update_updated_at_column();

create trigger klaviyo_profiles_updated_at before update on klaviyo_profiles
  for each row execute function update_updated_at_column();

create trigger klaviyo_campaigns_updated_at before update on klaviyo_campaigns
  for each row execute function update_updated_at_column();

create trigger klaviyo_flows_updated_at before update on klaviyo_flows
  for each row execute function update_updated_at_column();

create trigger klaviyo_flow_steps_updated_at before update on klaviyo_flow_steps
  for each row execute function update_updated_at_column();

create trigger klaviyo_lists_updated_at before update on klaviyo_lists
  for each row execute function update_updated_at_column();

create trigger klaviyo_segments_updated_at before update on klaviyo_segments
  for each row execute function update_updated_at_column();

create trigger klaviyo_predictive_metrics_updated_at before update on klaviyo_predictive_metrics
  for each row execute function update_updated_at_column();

create trigger ad_events_updated_at before update on ad_events
  for each row execute function update_updated_at_column();

create trigger customer_metrics_daily_updated_at before update on customer_metrics_daily
  for each row execute function update_updated_at_column();

create trigger campaign_performance_daily_updated_at before update on campaign_performance_daily
  for each row execute function update_updated_at_column();

create trigger product_performance_daily_updated_at before update on product_performance_daily
  for each row execute function update_updated_at_column();

-- ============================================================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================================================

comment on table customers is 'Unified customer master - single source of truth linking Shopify and Klaviyo identities';
comment on table shopify_orders is 'All Shopify orders with financial and fulfillment status';
comment on table shopify_products is 'Shopify product catalog with collections and tags';
comment on table klaviyo_campaigns is 'Email/SMS campaign performance metrics';
comment on table klaviyo_flows is 'Marketing automation workflows (Abandoned Cart, Welcome Series, etc.)';
comment on table shopify_events is 'Behavioral events from Shopify store (pageviews, cart, checkout)';
comment on table klaviyo_events is 'Behavioral events from Klaviyo tracking (email opens, clicks, etc.)';
comment on table ad_events is 'Advertising platform data (Meta, Google, TikTok, etc.) with ROAS calculations';
comment on table customer_metrics_daily is 'Pre-aggregated daily metrics for cohort analysis and customer journey';
comment on table campaign_performance_daily is 'Daily breakdown of campaign performance for trend analysis';
comment on table product_performance_daily is 'Daily product metrics for inventory and conversion analysis';

