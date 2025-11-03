# Acquisition Metrics Implementation Summary

## ✅ What Was Implemented

### 1. **Database Tables**

#### `acquisition_metrics_daily`
Stores daily aggregated metrics per platform/campaign:
- **Spend & Traffic**: `total_spend`, `total_impressions`, `total_clicks`, `total_conversions`, `total_revenue`
- **Calculated Metrics**: `cpc`, `cpm`, `ctr`, `cvr`, `roas` (pre-computed for performance)
- **Customer Metrics**: `new_customers_count`, `email_signups_count`, `cost_per_customer` (CAC), `cost_per_signup`
- **Session Metrics**: `sessions_count`, `bounced_sessions_count`, `bounce_rate`, `session_to_signup_ratio`

#### `traffic_source_metrics_daily`
Stores daily traffic and conversion metrics by source:
- **Traffic**: `sessions_count`, `page_views_count`, `unique_visitors_count`
- **Engagement**: `bounced_sessions_count`, `avg_session_duration_seconds`
- **Conversions**: `signups_count`, `orders_count`, `revenue`
- **UTM Tracking**: `utm_source`, `utm_medium`, `utm_campaign`
- **Calculated**: `bounce_rate`, `signup_rate`, `conversion_rate`

### 2. **Functions** (11 functions created)

All acquisition metrics can be calculated using SQL functions:

```sql
-- Calculate CAC
SELECT calculate_cac('meta', '2024-01-01', '2024-12-31');

-- Calculate CTR
SELECT calculate_ctr('google', 'campaign_123', '2024-01-01', '2024-12-31');

-- Calculate CVR
SELECT calculate_cvr('tiktok', '2024-01-01', '2024-12-31');

-- Calculate Cost per Signup
SELECT calculate_cost_per_signup('meta', '2024-01-01', '2024-12-31');

-- Calculate Session-to-Signup Ratio
SELECT calculate_session_to_signup_ratio('2024-01-01', '2024-12-31');

-- Calculate Bounce Rate
SELECT calculate_bounce_rate('2024-01-01', '2024-12-31');

-- Calculate LTV:CAC Ratio
SELECT calculate_ltv_cac_ratio('google');
```

### 3. **Materialized Views**

#### `acquisition_metrics_summary`
Aggregated metrics by platform (all time):
- Total spend, impressions, clicks, conversions, revenue
- Average CPC, CPM, CTR, CVR, ROAS, CAC
- Total new customers and signups

#### `traffic_source_summary`
Traffic source performance summary:
- Total sessions, page views, signups, orders, revenue
- Average bounce rate, signup rate, conversion rate
- Session-to-signup ratio

#### `source_roi_summary`
Source ROI (LTV:CAC ratio) by platform:
- Customers acquired, CAC, Average LTV, LTV:CAC ratio

### 4. **Refresh Functions**

#### `refresh_acquisition_metrics_daily(target_date)`
Populates `acquisition_metrics_daily` for a specific date:
- Aggregates from `ad_events`, `customers`, `klaviyo_events`, `shopify_events`
- Calculates all metrics automatically

#### `refresh_traffic_source_metrics_daily(target_date)`
Populates `traffic_source_metrics_daily` for a specific date:
- Aggregates from `shopify_events`, `klaviyo_events`, `shopify_orders`
- Tracks UTM parameters and referrers

## 📊 Where Each Metric Is Stored

| Metric | Primary Storage | Query Method |
|--------|----------------|--------------|
| **CAC** | `acquisition_metrics_daily.cost_per_customer` | `acquisition_metrics_summary.avg_cac` or `calculate_cac()` |
| **CTR** | `acquisition_metrics_daily.ctr` | `acquisition_metrics_summary.avg_ctr` or `calculate_ctr()` |
| **CVR** | `acquisition_metrics_daily.cvr` | `acquisition_metrics_summary.avg_cvr` or `calculate_cvr()` |
| **CPC** | `acquisition_metrics_daily.cpc` | `acquisition_metrics_summary.avg_cpc` |
| **CPM** | `acquisition_metrics_daily.cpm` | `acquisition_metrics_summary.avg_cpm` |
| **ROAS** | `acquisition_metrics_daily.roas` | `acquisition_metrics_summary.avg_roas` or `calculate_roas()` |
| **Traffic by Source** | `traffic_source_metrics_daily` | `traffic_source_summary` |
| **New Users** | `acquisition_metrics_daily.new_customers_count` | `acquisition_metrics_summary.total_new_customers` |
| **Email Sign-up Rate** | `traffic_source_metrics_daily.signup_rate` | `traffic_source_summary.avg_signup_rate` |
| **Cost per Signup** | `acquisition_metrics_daily.cost_per_signup` | `calculate_cost_per_signup()` |
| **Session-to-Signup** | `acquisition_metrics_daily.session_to_signup_ratio` | `traffic_source_summary.session_to_signup_ratio` |
| **Bounce Rate** | `traffic_source_metrics_daily.bounce_rate` | `traffic_source_summary.avg_bounce_rate` |
| **Source ROI (LTV:CAC)** | Calculated | `source_roi_summary.ltv_cac_ratio` or `calculate_ltv_cac_ratio()` |

## 🚀 Usage

### Populate Metrics (Run Daily)

```bash
npm run metrics:populate
```

This will:
- Process all dates with ad_events data
- Populate `acquisition_metrics_daily`
- Populate `traffic_source_metrics_daily`

### Query All Metrics

```bash
npm run metrics:all
```

Shows:
- Platform-level acquisition metrics
- Traffic source performance
- Source ROI (LTV:CAC)
- Daily trends

### Query Basic Acquisition Metrics

```bash
npm run metrics:acquisition
```

Shows raw calculated metrics from base tables.

### Custom Queries

```sql
-- Get CAC for last 30 days
SELECT calculate_cac('meta', CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE);

-- Get platform summary
SELECT * FROM acquisition_metrics_summary WHERE platform = 'google';

-- Get traffic sources with signups
SELECT * FROM traffic_source_summary WHERE total_signups > 0 ORDER BY total_signups DESC;

-- Get best performing platform by ROAS
SELECT * FROM acquisition_metrics_summary ORDER BY avg_roas DESC LIMIT 1;
```

## 📈 Scheduled Refresh (Recommended)

Set up a cron job or scheduled Lambda to refresh metrics daily:

```sql
-- Refresh yesterday's metrics
SELECT refresh_acquisition_metrics_daily(CURRENT_DATE - 1);
SELECT refresh_traffic_source_metrics_daily(CURRENT_DATE - 1);

-- Refresh last 7 days (backfill)
DO $$
DECLARE
  d date;
BEGIN
  FOR d IN SELECT generate_series(CURRENT_DATE - 7, CURRENT_DATE - 1, '1 day'::interval)::date
  LOOP
    PERFORM refresh_acquisition_metrics_daily(d);
    PERFORM refresh_traffic_source_metrics_daily(d);
  END LOOP;
END $$;
```

## 🔗 Relationships

- **acquisition_metrics_daily** ← aggregates from `ad_events` + `customers` + `klaviyo_events` + `shopify_events`
- **traffic_source_metrics_daily** ← aggregates from `shopify_events` + `klaviyo_events` + `shopify_orders`
- **Views** ← aggregate from the daily tables for fast queries

## 📝 Notes

- Metrics are **pre-calculated** for performance (no real-time computation needed)
- Daily tables are **append-only** (one row per platform/campaign/date)
- Functions allow **custom date ranges** for ad-hoc analysis
- Views provide **aggregated summaries** across all time periods
- All metrics handle **NULL values** gracefully

## ✅ Status

All 13 acquisition metrics are now:
- ✅ Stored in database tables
- ✅ Calculated via SQL functions  
- ✅ Available in materialized views
- ✅ Populated with mock data
- ✅ Queryable via scripts

