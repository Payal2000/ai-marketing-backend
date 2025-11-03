# Acquisition Metrics Storage & Calculation Guide

This document shows where each acquisition metric is stored in the database and how to calculate them.

---

## 1. Customer Acquisition Cost (CAC)

**Storage**: Calculated from `ad_events` table

**Calculation**:
```sql
SELECT 
  platform,
  SUM(spend) / COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL) as cac
FROM ad_events
WHERE event_type = 'conversion' OR event_type = 'purchase'
GROUP BY platform;
```

**Fields Used**:
- `ad_events.spend` - Total ad spend
- `ad_events.customer_id` - New customers acquired
- `ad_events.platform` - Marketing channel

---

## 2. Click-Through Rate (CTR)

**Storage**: Calculated from `ad_events` table

**Calculation**:
```sql
SELECT 
  platform,
  campaign_id,
  SUM(clicks)::decimal / NULLIF(SUM(impressions), 0) * 100 as ctr_percentage
FROM ad_events
WHERE impressions > 0
GROUP BY platform, campaign_id;
```

**Fields Used**:
- `ad_events.clicks` - Number of clicks
- `ad_events.impressions` - Number of impressions

**Note**: Can also be stored in a view or materialized table for performance.

---

## 3. Conversion Rate (CVR) from Ad → Signup

**Storage**: Calculated from `ad_events` + `customers` or `klaviyo_events`

**Calculation (Ad → Customer Signup)**:
```sql
SELECT 
  ae.platform,
  COUNT(DISTINCT c.id) FILTER (WHERE c.source = 'ad')::decimal / 
  NULLIF(SUM(ae.clicks), 0) * 100 as cvr_percentage
FROM ad_events ae
LEFT JOIN customers c ON c.id = ae.customer_id
WHERE ae.event_type = 'click'
GROUP BY ae.platform;
```

**Calculation (Ad → Email Signup)**:
```sql
SELECT 
  ae.platform,
  COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')::decimal / 
  NULLIF(SUM(ae.clicks), 0) * 100 as signup_cvr_percentage
FROM ad_events ae
LEFT JOIN klaviyo_events ke ON ke.customer_id = ae.customer_id
WHERE ae.event_type = 'click'
GROUP BY ae.platform;
```

**Fields Used**:
- `ad_events.clicks` - Clicks from ads
- `customers.id` - New customers (via `ad_events.customer_id`)
- `klaviyo_events.event_type = 'Subscribed to List'` - Email signups

---

## 4. Cost per Click (CPC)

**Storage**: Calculated from `ad_events` table

**Calculation**:
```sql
SELECT 
  platform,
  campaign_id,
  SUM(spend) / NULLIF(SUM(clicks), 0) as cpc
FROM ad_events
WHERE clicks > 0
GROUP BY platform, campaign_id;
```

**Fields Used**:
- `ad_events.spend` - Total spend
- `ad_events.clicks` - Total clicks

**Can be stored in**: Materialized view or computed column

---

## 5. Cost per Impression (CPM)

**Storage**: Calculated from `ad_events` table

**Calculation**:
```sql
SELECT 
  platform,
  campaign_id,
  SUM(spend) / NULLIF(SUM(impressions), 0) * 1000 as cpm
FROM ad_events
WHERE impressions > 0
GROUP BY platform, campaign_id;
```

**Fields Used**:
- `ad_events.spend` - Total spend
- `ad_events.impressions` - Total impressions

---

## 6. Return on Ad Spend (ROAS)

**Storage**: 
- Calculated: `ad_events` table (using function `calculate_roas()`)
- Can be stored: Computed in queries or materialized view

**Calculation**:
```sql
SELECT 
  platform,
  campaign_id,
  SUM(revenue) / NULLIF(SUM(spend), 0) as roas,
  -- Or use the function:
  calculate_roas(id) as roas_per_event
FROM ad_events
WHERE spend > 0
GROUP BY platform, campaign_id;
```

**Fields Used**:
- `ad_events.revenue` - Revenue generated
- `ad_events.spend` - Ad spend
- Function: `calculate_roas(ad_event_uuid)` - Pre-built calculation

**Note**: Function exists in schema: `calculate_roas(ad_event_uuid)`

---

## 7. Traffic by Source/Channel

**Storage**: `shopify_events.event_properties` (JSONB) and `shopify_orders.source`

**Calculation**:
```sql
-- From Shopify events (page views, sessions)
SELECT 
  event_properties->>'referrer' as source,
  event_properties->>'utm_source' as utm_source,
  event_properties->>'utm_medium' as utm_medium,
  COUNT(*) as traffic_count
FROM shopify_events
WHERE event_type IN ('page_viewed', 'product_viewed')
GROUP BY source, utm_source, utm_medium;

-- From Orders (final conversion source)
SELECT 
  source,
  COUNT(*) as order_count,
  SUM(total_price) as revenue
FROM shopify_orders
WHERE financial_status = 'paid'
GROUP BY source;
```

**Fields Used**:
- `shopify_events.event_properties` (JSONB) - Contains `referrer`, `utm_source`, `utm_medium`, `utm_campaign`
- `shopify_orders.source` - Order source ('online_store', 'pos', 'api', etc.)
- Index: `shopify_events_properties_idx` (GIN index on JSONB)

**Note**: UTM parameters are stored in `event_properties` JSONB field for flexibility.

---

## 8. New Users / First-Time Visitors

**Storage**: `customers` table

**Calculation**:
```sql
SELECT 
  COUNT(*) FILTER (WHERE is_first_time_customer = true) as new_customers,
  COUNT(*) FILTER (WHERE is_first_time_customer = false) as returning_customers,
  COUNT(*) as total_customers
FROM customers;

-- By date
SELECT 
  DATE(created_at) as signup_date,
  COUNT(*) FILTER (WHERE is_first_time_customer = true) as new_customers
FROM customers
GROUP BY DATE(created_at)
ORDER BY signup_date DESC;
```

**Fields Used**:
- `customers.is_first_time_customer` (boolean) - Flag for first-time customers
- `customers.created_at` - Customer creation date
- `customers.total_orders = 1` - Alternative indicator for first-time

---

## 9. Email Sign-Up Rate (Popup or Embedded Forms)

**Storage**: `klaviyo_events` table

**Calculation**:
```sql
-- Overall sign-up rate
SELECT 
  COUNT(*) FILTER (WHERE event_type = 'Subscribed to List') as signups,
  COUNT(*) FILTER (WHERE event_type = 'Viewed Page') as page_views,
  COUNT(*) FILTER (WHERE event_type = 'Subscribed to List')::decimal / 
  NULLIF(COUNT(*) FILTER (WHERE event_type = 'Viewed Page'), 0) * 100 as signup_rate
FROM klaviyo_events
WHERE occurred_at >= CURRENT_DATE - INTERVAL '30 days';

-- By list/source
SELECT 
  event_properties->>'source' as signup_source,
  COUNT(*) FILTER (WHERE event_type = 'Subscribed to List') as signups
FROM klaviyo_events
WHERE event_type = 'Subscribed to List'
GROUP BY signup_source;
```

**Fields Used**:
- `klaviyo_events.event_type = 'Subscribed to List'` - Signup events
- `klaviyo_events.event_properties` (JSONB) - Contains `source` (e.g., 'popup', 'embedded_form', 'checkout')
- `klaviyo_profile_lists.added_at` - When profile was added to list (indirect signup indicator)

**Related Tables**:
- `klaviyo_lists` - Lists where signups occurred
- `klaviyo_profile_lists` - Junction table tracking profile-list relationships

---

## 10. Cost per Signup / Lead

**Storage**: Calculated from `ad_events` + `klaviyo_events`

**Calculation**:
```sql
-- Cost per email signup
SELECT 
  ae.platform,
  ae.campaign_id,
  SUM(ae.spend) / 
  NULLIF(COUNT(DISTINCT ke.id) FILTER (
    WHERE ke.event_type = 'Subscribed to List' 
    AND ke.occurred_at >= ae.date
    AND ke.occurred_at < ae.date + INTERVAL '7 days'
  ), 0) as cost_per_signup
FROM ad_events ae
LEFT JOIN klaviyo_events ke ON ke.customer_id = ae.customer_id
WHERE ae.spend > 0
GROUP BY ae.platform, ae.campaign_id;

-- Cost per new customer (lead)
SELECT 
  ae.platform,
  SUM(ae.spend) / 
  NULLIF(COUNT(DISTINCT c.id) FILTER (WHERE c.is_first_time_customer = true), 0) as cost_per_lead
FROM ad_events ae
LEFT JOIN customers c ON c.id = ae.customer_id
WHERE ae.event_type IN ('conversion', 'purchase')
GROUP BY ae.platform;
```

**Fields Used**:
- `ad_events.spend` - Ad spend
- `klaviyo_events.event_type = 'Subscribed to List'` - Signups
- `customers.is_first_time_customer` - New customers/leads

---

## 11. Session-to-Signup Ratio

**Storage**: Calculated from `shopify_events` + `klaviyo_events`

**Calculation**:
```sql
SELECT 
  COUNT(DISTINCT se.session_id) as total_sessions,
  COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List') as signups,
  COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')::decimal / 
  NULLIF(COUNT(DISTINCT se.session_id), 0) * 100 as session_to_signup_ratio
FROM shopify_events se
LEFT JOIN customers c ON c.id = se.customer_id
LEFT JOIN klaviyo_events ke ON ke.customer_id = c.id
WHERE se.event_type = 'page_viewed'
  AND se.occurred_at >= CURRENT_DATE - INTERVAL '30 days';
```

**Fields Used**:
- `shopify_events.session_id` - Session tracking
- `shopify_events.event_type = 'page_viewed'` - Page views (sessions)
- `klaviyo_events.event_type = 'Subscribed to List'` - Signups
- Index: `shopify_events_session_id_idx`

---

## 12. Bounce Rate

**Storage**: `shopify_events` table (needs single-page-view sessions)

**Calculation**:
```sql
-- Single-page sessions (bounces)
WITH session_pages AS (
  SELECT 
    session_id,
    COUNT(*) as page_views,
    MIN(occurred_at) as first_view,
    MAX(occurred_at) as last_view,
    EXTRACT(EPOCH FROM (MAX(occurred_at) - MIN(occurred_at))) as session_duration_seconds
  FROM shopify_events
  WHERE event_type = 'page_viewed'
    AND session_id IS NOT NULL
  GROUP BY session_id
)
SELECT 
  COUNT(*) FILTER (WHERE page_views = 1 OR session_duration_seconds < 30) as bounced_sessions,
  COUNT(*) as total_sessions,
  COUNT(*) FILTER (WHERE page_views = 1 OR session_duration_seconds < 30)::decimal / 
  NULLIF(COUNT(*), 0) * 100 as bounce_rate_percentage
FROM session_pages;
```

**Fields Used**:
- `shopify_events.session_id` - Session tracking
- `shopify_events.event_type = 'page_viewed'` - Page views
- `shopify_events.occurred_at` - Timestamp for session duration calculation

**Note**: Bounce = single page view OR session duration < 30 seconds

---

## 13. Source ROI (LTV:CAC Ratio by Channel)

**Storage**: Calculated from `customers` + `ad_events`

**Calculation**:
```sql
WITH channel_cac AS (
  SELECT 
    platform,
    SUM(spend) / NULLIF(COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL), 0) as cac
  FROM ad_events
  WHERE event_type IN ('conversion', 'purchase')
  GROUP BY platform
),
channel_ltv AS (
  SELECT 
    ae.platform,
    AVG(c.total_revenue) as avg_ltv
  FROM ad_events ae
  JOIN customers c ON c.id = ae.customer_id
  WHERE ae.customer_id IS NOT NULL
  GROUP BY ae.platform
)
SELECT 
  cc.platform,
  cc.cac,
  cl.avg_ltv,
  cl.avg_ltv / NULLIF(cc.cac, 0) as ltv_cac_ratio
FROM channel_cac cc
JOIN channel_ltv cl ON cl.platform = cc.platform
ORDER BY ltv_cac_ratio DESC;
```

**Fields Used**:
- `ad_events.platform` - Marketing channel
- `ad_events.spend` - Acquisition cost
- `ad_events.customer_id` - Acquired customers
- `customers.total_revenue` - Customer lifetime value

---

## Summary: Where Metrics Are Stored

| Metric | Primary Table | Calculation Type |
|--------|--------------|------------------|
| CAC | `ad_events` | Calculated |
| CTR | `ad_events` | Calculated (clicks/impressions) |
| CVR | `ad_events` + `klaviyo_events` | Calculated |
| CPC | `ad_events` | Calculated (spend/clicks) |
| CPM | `ad_events` | Calculated (spend/impressions*1000) |
| ROAS | `ad_events` | Calculated (revenue/spend) - Function exists |
| Traffic by Source | `shopify_events.event_properties` (JSONB) | Stored in JSONB, queried |
| New Users | `customers.is_first_time_customer` | Stored boolean |
| Email Sign-up Rate | `klaviyo_events` | Calculated |
| Cost per Signup | `ad_events` + `klaviyo_events` | Calculated |
| Session-to-Signup | `shopify_events` + `klaviyo_events` | Calculated |
| Bounce Rate | `shopify_events` | Calculated |
| Source ROI (LTV:CAC) | `ad_events` + `customers` | Calculated |

---

## Recommended: Create Materialized Views for Performance

For frequently accessed metrics, consider creating materialized views:

```sql
-- Example: Daily acquisition metrics
CREATE MATERIALIZED VIEW acquisition_metrics_daily AS
SELECT 
  DATE(ae.date) as date,
  ae.platform,
  SUM(ae.spend) as total_spend,
  SUM(ae.impressions) as total_impressions,
  SUM(ae.clicks) as total_clicks,
  SUM(ae.conversions) as total_conversions,
  SUM(ae.revenue) as total_revenue,
  SUM(ae.spend) / NULLIF(SUM(ae.clicks), 0) as cpc,
  SUM(ae.clicks)::decimal / NULLIF(SUM(ae.impressions), 0) * 100 as ctr,
  SUM(ae.revenue) / NULLIF(SUM(ae.spend), 0) as roas
FROM ad_events ae
GROUP BY DATE(ae.date), ae.platform;

CREATE INDEX ON acquisition_metrics_daily(date, platform);

-- Refresh daily
REFRESH MATERIALIZED VIEW acquisition_metrics_daily;
```

---

## Quick Reference Queries

See `METRICS_DOCUMENTATION.md` for additional detailed query examples and cross-system relationship queries.

