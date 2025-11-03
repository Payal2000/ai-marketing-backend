# E-Commerce Data Warehouse Setup Guide

## Files

- **`ecommerce_schema.sql`**: Complete database schema with all tables, indexes, functions, and triggers
- **`METRICS_DOCUMENTATION.md`**: Comprehensive documentation of all metrics and their calculations

## Quick Start

### 1. Create Supabase Project

1. Go to [Supabase Dashboard](https://supabase.com)
2. Create a new project
3. Wait for project to finish provisioning
4. Copy your database connection string (Settings → Database → Connection string)

### 2. Run the Schema

1. Open Supabase SQL Editor
2. Copy and paste the entire contents of `ecommerce_schema.sql`
3. Click "Run" to execute
4. Verify tables were created (should see ~20+ tables)

### 3. Verify Installation

Run this query to verify all tables exist:

```sql
SELECT 
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns 
   WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

Expected tables:
- `customers`
- `customer_addresses`
- `shopify_orders`
- `shopify_order_line_items`
- `shopify_products`
- `shopify_product_variants`
- `klaviyo_profiles`
- `klaviyo_campaigns`
- `klaviyo_flows`
- `klaviyo_flow_steps`
- `klaviyo_lists`
- `klaviyo_segments`
- `klaviyo_profile_lists`
- `klaviyo_predictive_metrics`
- `shopify_events`
- `klaviyo_events`
- `ad_events`
- `customer_metrics_daily`
- `campaign_performance_daily`
- `product_performance_daily`

### 4. Test Views and Functions

```sql
-- Test customer lifetime metrics view
SELECT * FROM customer_lifetime_metrics LIMIT 5;

-- Test campaign performance view
SELECT * FROM campaign_performance_summary LIMIT 5;

-- Test product performance view
SELECT * FROM product_performance_summary LIMIT 5;
```

## Data Sync Strategy

### Shopify Data Sync

Use Shopify Admin API or webhooks to sync:

1. **Orders**: POST to `shopify_orders` (use `ON CONFLICT` for updates)
2. **Products**: POST to `shopify_products` and `shopify_product_variants`
3. **Customers**: POST to `customers` (merge with Klaviyo profile if exists)
4. **Events**: POST to `shopify_events` from Shopify Tracking API

Example upsert for orders:

```sql
INSERT INTO shopify_orders (
  shopify_order_id, customer_id, order_number, order_date,
  source, financial_status, total_price, currency_code
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
ON CONFLICT (shopify_order_id) 
DO UPDATE SET
  financial_status = EXCLUDED.financial_status,
  fulfillment_status = EXCLUDED.fulfillment_status,
  updated_at = NOW();
```

### Klaviyo Data Sync

Use Klaviyo API to sync:

1. **Profiles**: POST to `klaviyo_profiles` (link to `customers` via email)
2. **Campaigns**: POST to `klaviyo_campaigns` when campaigns are sent
3. **Flows**: POST to `klaviyo_flows` and `klaviyo_flow_steps`
4. **Events**: POST to `klaviyo_events` from Klaviyo webhooks
5. **Predictive Metrics**: POST to `klaviyo_predictive_metrics` (refresh weekly)

Example profile sync:

```sql
-- First, ensure customer exists
INSERT INTO customers (email, klaviyo_profile_id)
VALUES ($1, $2)
ON CONFLICT (email) 
DO UPDATE SET klaviyo_profile_id = EXCLUDED.klaviyo_profile_id
RETURNING id;

-- Then insert/update profile
INSERT INTO klaviyo_profiles (
  klaviyo_profile_id, customer_id, email, properties
) VALUES ($2, $3, $1, $4)
ON CONFLICT (klaviyo_profile_id)
DO UPDATE SET properties = EXCLUDED.properties, updated_at = NOW();
```

### Advertising Platform Sync

1. **Meta Ads**: Use Meta Marketing API → POST to `ad_events`
2. **Google Ads**: Use Google Ads API → POST to `ad_events`
3. **TikTok Ads**: Use TikTok Ads API → POST to `ad_events`

Example ad event:

```sql
INSERT INTO ad_events (
  platform, campaign_id, spend, impressions, clicks, revenue, date
) VALUES ('meta', $1, $2, $3, $4, $5, $6)
ON CONFLICT DO NOTHING; -- Or define unique constraint
```

## Daily Aggregation Jobs

Set up scheduled jobs to populate aggregation tables:

### Customer Metrics Daily

```sql
INSERT INTO customer_metrics_daily (
  customer_id, date, orders_count, revenue,
  products_viewed_count, cart_adds_count, checkouts_started_count,
  emails_opened_count, emails_clicked_count
)
SELECT 
  c.id,
  CURRENT_DATE,
  COUNT(DISTINCT o.id) FILTER (WHERE o.order_date::date = CURRENT_DATE),
  COALESCE(SUM(o.total_price) FILTER (WHERE o.financial_status = 'paid' AND o.order_date::date = CURRENT_DATE), 0),
  COUNT(DISTINCT se.id) FILTER (WHERE se.event_type = 'product_viewed' AND se.occurred_at::date = CURRENT_DATE),
  COUNT(DISTINCT se.id) FILTER (WHERE se.event_type = 'cart_added' AND se.occurred_at::date = CURRENT_DATE),
  COUNT(DISTINCT se.id) FILTER (WHERE se.event_type = 'checkout_started' AND se.occurred_at::date = CURRENT_DATE),
  COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Opened Email' AND ke.occurred_at::date = CURRENT_DATE),
  COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Clicked Email' AND ke.occurred_at::date = CURRENT_DATE)
FROM customers c
LEFT JOIN shopify_orders o ON o.customer_id = c.id
LEFT JOIN shopify_events se ON se.customer_id = c.id
LEFT JOIN klaviyo_events ke ON ke.customer_id = c.id
WHERE c.id IN (
  SELECT DISTINCT customer_id FROM shopify_orders WHERE order_date::date = CURRENT_DATE
  UNION
  SELECT DISTINCT customer_id FROM shopify_events WHERE occurred_at::date = CURRENT_DATE
)
GROUP BY c.id
ON CONFLICT (customer_id, date)
DO UPDATE SET
  orders_count = EXCLUDED.orders_count,
  revenue = EXCLUDED.revenue,
  products_viewed_count = EXCLUDED.products_viewed_count,
  cart_adds_count = EXCLUDED.cart_adds_count,
  checkouts_started_count = EXCLUDED.checkouts_started_count,
  emails_opened_count = EXCLUDED.emails_opened_count,
  emails_clicked_count = EXCLUDED.emails_clicked_count,
  updated_at = NOW();
```

### Campaign Performance Daily

```sql
INSERT INTO campaign_performance_daily (
  campaign_id, date, sent_count, delivered_count,
  opens_count, clicks_count, unsubscribes_count, revenue
)
SELECT 
  kc.id,
  CURRENT_DATE,
  kc.recipients_count,
  kc.delivered_count,
  kc.unique_opens_count,
  kc.unique_clicks_count,
  kc.unsubscribes_count,
  kc.revenue
FROM klaviyo_campaigns kc
WHERE kc.send_date::date = CURRENT_DATE
ON CONFLICT (campaign_id, date)
DO UPDATE SET
  sent_count = EXCLUDED.sent_count,
  delivered_count = EXCLUDED.delivered_count,
  opens_count = EXCLUDED.opens_count,
  clicks_count = EXCLUDED.clicks_count,
  unsubscribes_count = EXCLUDED.unsubscribes_count,
  revenue = EXCLUDED.revenue,
  updated_at = NOW();
```

## Key Queries for Common Metrics

### Total Revenue (Last 30 Days)

```sql
SELECT SUM(total_price) as revenue
FROM shopify_orders
WHERE financial_status = 'paid'
  AND order_date >= CURRENT_DATE - INTERVAL '30 days';
```

### Customer LTV Distribution

```sql
SELECT 
  CASE 
    WHEN total_revenue < 50 THEN '$0-50'
    WHEN total_revenue < 100 THEN '$50-100'
    WHEN total_revenue < 200 THEN '$100-200'
    ELSE '$200+'
  END as ltv_bucket,
  COUNT(*) as customer_count
FROM customers
WHERE total_orders > 0
GROUP BY ltv_bucket
ORDER BY MIN(total_revenue);
```

### Top Performing Campaigns (Last 90 Days)

```sql
SELECT 
  name,
  type,
  recipients_count,
  calculate_open_rate(id) * 100 as open_rate_pct,
  calculate_click_rate(id) * 100 as click_rate_pct,
  revenue,
  revenue / NULLIF(delivered_count, 0) as revenue_per_delivered
FROM klaviyo_campaigns
WHERE send_date >= CURRENT_DATE - INTERVAL '90 days'
  AND status = 'sent'
ORDER BY revenue DESC
LIMIT 10;
```

### Product Funnel (Last 7 Days)

```sql
SELECT 
  sp.title,
  COUNT(DISTINCT se1.id) as views,
  COUNT(DISTINCT se2.id) as cart_adds,
  COUNT(DISTINCT oli.order_id) as purchases,
  ROUND(
    COUNT(DISTINCT oli.order_id)::decimal / 
    NULLIF(COUNT(DISTINCT se1.id), 0) * 100, 
    2
  ) as conversion_rate_pct
FROM shopify_products sp
LEFT JOIN shopify_events se1 
  ON se1.product_id = sp.id 
  AND se1.event_type = 'product_viewed'
  AND se1.occurred_at >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN shopify_events se2 
  ON se2.product_id = sp.id 
  AND se2.event_type = 'cart_added'
  AND se2.occurred_at >= CURRENT_DATE - INTERVAL '7 days'
LEFT JOIN shopify_order_line_items oli 
  ON oli.product_id = sp.id
  AND EXISTS (
    SELECT 1 FROM shopify_orders o 
    WHERE o.id = oli.order_id 
    AND o.order_date >= CURRENT_DATE - INTERVAL '7 days'
  )
GROUP BY sp.id, sp.title
HAVING COUNT(DISTINCT se1.id) > 0
ORDER BY conversion_rate_pct DESC;
```

### ROAS by Platform (Last 30 Days)

```sql
SELECT 
  platform,
  SUM(spend) as total_spend,
  SUM(revenue) as total_revenue,
  CASE 
    WHEN SUM(spend) > 0 
    THEN SUM(revenue) / SUM(spend) 
    ELSE 0 
  END as roas
FROM ad_events
WHERE date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY platform
ORDER BY roas DESC;
```

## Performance Optimization

### Indexes

All necessary indexes are included in the schema. Key indexes:
- Foreign keys (for JOIN performance)
- Date columns (for time-range queries)
- JSONB columns (GIN indexes for flexible queries)

### Partitioning (Optional, for High Volume)

For very large event tables (>100M rows), consider partitioning:

```sql
-- Example: Partition shopify_events by month
CREATE TABLE shopify_events_2024_01 PARTITION OF shopify_events
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

### Materialized Views (For Expensive Aggregations)

If real-time views are too slow, create materialized views:

```sql
CREATE MATERIALIZED VIEW customer_lifetime_metrics_mv AS
SELECT * FROM customer_lifetime_metrics;

CREATE INDEX ON customer_lifetime_metrics_mv(customer_id);

-- Refresh daily
REFRESH MATERIALIZED VIEW customer_lifetime_metrics_mv;
```

## Troubleshooting

### Error: "relation already exists"
- Tables already exist. Use `DROP TABLE IF EXISTS` or skip existing tables.

### Error: "permission denied for schema"
- Run as the `postgres` user or ensure your user has CREATE permissions.

### Slow Queries
- Check if indexes are being used: `EXPLAIN ANALYZE [your query]`
- Consider adding indexes on frequently filtered columns

### Missing Data
- Verify foreign key constraints are satisfied
- Check that sync jobs are running
- Validate data types match API responses

## Next Steps

1. **Set up data sync jobs** (Shopify webhooks, Klaviyo API polling, Ad platform APIs)
2. **Create dashboards** using the views and pre-aggregated tables
3. **Set up alerts** on key metrics (low ROAS, high churn risk, etc.)
4. **Schedule daily aggregation jobs** to populate `*_daily` tables

For detailed metric definitions and calculations, see `METRICS_DOCUMENTATION.md`.

