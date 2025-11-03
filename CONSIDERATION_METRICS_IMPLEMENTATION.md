# Consideration Metrics Implementation Summary

## ✅ What Was Implemented

### 1. **Database Tables**

#### `consideration_metrics_daily`
Stores daily aggregated consideration metrics:
- **Product Engagement**: `total_product_views`, `total_add_to_cart`, `total_wishlist_adds`, `total_checkout_starts`, `total_checkout_completions`
- **Calculated Rates**: `add_to_cart_rate`, `view_to_add_to_cart_ratio`, `wishlist_add_rate`, `cart_abandonment_rate`, `product_page_bounce_rate` (pre-computed)
- **Session Metrics**: `total_sessions`, `total_page_views`, `avg_pages_per_session`, `avg_session_duration_seconds`, `avg_scroll_depth_percent`
- **Retention**: `sessions_with_repeat_visits_7d`, `repeat_visit_rate_7d`
- **Email Engagement**: `total_emails_sent`, `total_emails_opened`, `total_emails_clicked`, `email_open_rate`, `email_ctr`
- **Engagement Score**: `engagement_score` (weighted across site + email)

#### `session_engagement_daily`
Stores session-level engagement metrics (optional, for detailed analysis):
- Session-level tracking for bounce, duration, scroll depth, repeat visits

### 2. **Functions** (11 functions created)

All consideration metrics can be calculated using SQL functions:

```sql
-- Add-to-Cart Rate
SELECT calculate_add_to_cart_rate('2024-01-01', '2024-12-31');

-- View-to-Add-to-Cart Ratio
SELECT calculate_view_to_add_to_cart_ratio('2024-01-01', '2024-12-31');

-- Product View Depth (avg pages per session)
SELECT calculate_product_view_depth('2024-01-01', '2024-12-31');

-- Average Session Duration
SELECT calculate_avg_session_duration('2024-01-01', '2024-12-31');

-- Average Scroll Depth
SELECT calculate_avg_scroll_depth('2024-01-01', '2024-12-31');

-- Wishlist Add Rate
SELECT calculate_wishlist_add_rate('2024-01-01', '2024-12-31');

-- Cart Abandonment Rate (pre-checkout)
SELECT calculate_cart_abandonment_rate('2024-01-01', '2024-12-31');

-- Product Page Bounce Rate
SELECT calculate_product_page_bounce_rate('2024-01-01', '2024-12-31');

-- Email Open Rate (from Klaviyo)
SELECT calculate_email_open_rate('2024-01-01', '2024-12-31');

-- Email Click-Through Rate
SELECT calculate_email_ctr('2024-01-01', '2024-12-31');

-- Repeat Visit Rate (7 days)
SELECT calculate_repeat_visit_rate_7d('2024-01-01', '2024-12-31');

-- Engagement Score (weighted)
SELECT calculate_engagement_score('2024-01-01', '2024-12-31');
```

### 3. **Materialized Views**

#### `consideration_metrics_summary`
Aggregated metrics summary (all time):
- Total counts (product views, add-to-cart, wishlist, checkouts)
- Average rates (add-to-cart, wishlist, cart abandonment, bounce)
- Average session metrics (pages, duration, scroll depth)
- Average email metrics (open rate, CTR)
- Average engagement score

#### `consideration_metrics_trends`
Daily trends view:
- Shows daily metrics with percentages formatted
- Useful for time-series analysis

### 4. **Refresh Function**

#### `refresh_consideration_metrics_daily(target_date)`
Populates `consideration_metrics_daily` for a specific date:
- Aggregates from `shopify_events` and `klaviyo_events`
- Calculates all metrics automatically
- Handles edge cases (NULL values, empty data)

## 📊 Where Each Metric Is Stored

| Metric | Primary Storage | Query Method |
|--------|----------------|--------------|
| **Add-to-Cart Rate** | `consideration_metrics_daily.add_to_cart_rate` | `consideration_metrics_summary.avg_add_to_cart_rate` or `calculate_add_to_cart_rate()` |
| **View-to-Add-to-Cart Ratio** | `consideration_metrics_daily.view_to_add_to_cart_ratio` | `consideration_metrics_summary.avg_view_to_add_to_cart_ratio` or `calculate_view_to_add_to_cart_ratio()` |
| **Product View Depth** | `consideration_metrics_daily.avg_pages_per_session` | `consideration_metrics_summary.avg_pages_per_session` or `calculate_product_view_depth()` |
| **Time on Site / Session Duration** | `consideration_metrics_daily.avg_session_duration_seconds` | `consideration_metrics_summary.avg_session_duration_seconds` or `calculate_avg_session_duration()` |
| **Scroll Depth %** | `consideration_metrics_daily.avg_scroll_depth_percent` | `consideration_metrics_summary.avg_scroll_depth_percent` or `calculate_avg_scroll_depth()` |
| **Wishlist Add Rate** | `consideration_metrics_daily.wishlist_add_rate` | `consideration_metrics_summary.avg_wishlist_add_rate` or `calculate_wishlist_add_rate()` |
| **Cart Abandonment Rate** | `consideration_metrics_daily.cart_abandonment_rate` | `consideration_metrics_summary.avg_cart_abandonment_rate` or `calculate_cart_abandonment_rate()` |
| **Product Page Bounce Rate** | `consideration_metrics_daily.product_page_bounce_rate` | `consideration_metrics_summary.avg_product_page_bounce_rate` or `calculate_product_page_bounce_rate()` |
| **Email Open Rate** | `consideration_metrics_daily.email_open_rate` | `consideration_metrics_summary.avg_email_open_rate` or `calculate_email_open_rate()` |
| **Email CTR** | `consideration_metrics_daily.email_ctr` | `consideration_metrics_summary.avg_email_ctr` or `calculate_email_ctr()` |
| **Engagement Score** | `consideration_metrics_daily.engagement_score` | `consideration_metrics_summary.avg_engagement_score` or `calculate_engagement_score()` |
| **Repeat Visit Rate (7d)** | `consideration_metrics_daily.repeat_visit_rate_7d` | `consideration_metrics_summary.avg_repeat_visit_rate_7d` or `calculate_repeat_visit_rate_7d()` |

## 🚀 Usage

### Populate Metrics (Run Daily)

```bash
npm run metrics:consideration:populate
```

This will:
- Process all dates with shopify_events data
- Populate `consideration_metrics_daily`
- Calculate all rates and metrics automatically

### Query All Metrics

```bash
npm run metrics:consideration
```

Shows:
- Overall summary (all-time averages)
- Daily trends (last 7 days)
- Sample function calculations

### Custom Queries

```sql
-- Get add-to-cart rate for last 30 days
SELECT calculate_add_to_cart_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE);

-- Get engagement score trend
SELECT date, engagement_score 
FROM consideration_metrics_daily 
WHERE date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date DESC;

-- Get cart abandonment by date
SELECT date, cart_abandonment_rate * 100 as abandonment_pct
FROM consideration_metrics_trends
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
ORDER BY date DESC;

-- Compare email metrics
SELECT 
  date,
  email_open_rate * 100 as open_rate_pct,
  email_ctr * 100 as ctr_pct
FROM consideration_metrics_daily
WHERE date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date DESC;
```

## 📈 Scheduled Refresh (Recommended)

Set up a cron job or scheduled Lambda to refresh metrics daily:

```sql
-- Refresh yesterday's metrics
SELECT refresh_consideration_metrics_daily(CURRENT_DATE - 1);

-- Refresh last 7 days (backfill)
DO $$
DECLARE
  d date;
BEGIN
  FOR d IN SELECT generate_series(CURRENT_DATE - 7, CURRENT_DATE - 1, '1 day'::interval)::date
  LOOP
    PERFORM refresh_consideration_metrics_daily(d);
  END LOOP;
END $$;
```

## 🔗 Relationships

- **consideration_metrics_daily** ← aggregates from `shopify_events` + `klaviyo_events`
- **Views** ← aggregate from the daily table for fast queries
- **Functions** ← calculate metrics on-demand from base tables

## 📝 Notes

- Metrics are **pre-calculated** for performance (no real-time computation needed)
- Daily table is **append-only** (one row per date)
- Functions allow **custom date ranges** for ad-hoc analysis
- Views provide **aggregated summaries** across all time periods
- All metrics handle **NULL values** gracefully
- Engagement score is **weighted**: 70% site engagement, 30% email engagement
- Scroll depth requires `event_properties->>'scroll_depth'` in `shopify_events` (optional)

## ✅ Status

All 12 consideration metrics are now:
- ✅ Stored in database tables
- ✅ Calculated via SQL functions  
- ✅ Available in materialized views
- ✅ Populated with mock data
- ✅ Queryable via scripts

## 🎯 Use Cases

1. **Identify Intent**: Track add-to-cart rates, product views, wishlist adds
2. **Measure Engagement**: Monitor session duration, scroll depth, pages per session
3. **Detect Drop-offs**: Analyze cart abandonment, product page bounces
4. **Email Performance**: Track open rates and CTR from Klaviyo campaigns
5. **Retention**: Measure repeat visit rates within 7 days
6. **Overall Health**: Use weighted engagement score for holistic view

