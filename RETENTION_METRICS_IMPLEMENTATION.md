# Retention Metrics Implementation Summary

## ✅ What Was Implemented

### 1. **Database Tables**

#### `retention_metrics_daily`
Stores daily aggregated retention metrics:
- **Customer Base**: `total_customers`, `active_customers_30d/60d/90d`, `repeat_customers`
- **Retention Rates**: `repeat_purchase_rate`, `active_customer_rate_30d/60d/90d`, `churn_rate_30d/60d/90d`
- **Time Metrics**: `avg_days_between_purchases`, `median_days_between_purchases`
- **LTV Metrics**: `avg_ltv`, `median_ltv`, `total_ltv`
- **Klaviyo Predictions**: `avg_reorder_probability`, `avg_churn_probability`, `avg_predicted_ltv`, `avg_email_engagement_probability`
- **Email Engagement**: `engagement_decay_rate`, `winback_email_open_rate`
- **Subscription**: `subscription_retention_rate`
- **Replenishment**: `avg_replenishment_accuracy_days`
- **ROI**: `avg_ltv_cac_ratio`

#### `customer_retention_cohorts`
Stores customer-level retention data by cohort:
- Cohort assignment (first order date/month)
- Purchase history and timing
- Active/churn status (30d, 60d, 90d)
- Klaviyo predictions (next order, churn probability, LTV)
- Replenishment predictions and accuracy

### 2. **Functions** (11 functions created)

All retention metrics can be calculated using SQL functions:

```sql
-- Repeat Purchase Rate
SELECT calculate_repeat_purchase_rate('2024-01-01', '2024-12-31');

-- Time Between Purchases
SELECT calculate_avg_days_between_purchases('2024-01-01', '2024-12-31');

-- Active Customer % (purchased in last X days)
SELECT calculate_active_customer_rate(30);  -- 30 days
SELECT calculate_active_customer_rate(60);  -- 60 days
SELECT calculate_active_customer_rate(90);  -- 90 days

-- Churn Rate (% inactive after X days)
SELECT calculate_churn_rate(30);  -- 30 days
SELECT calculate_churn_rate(60);  -- 60 days
SELECT calculate_churn_rate(90);  -- 90 days

-- Customer Lifetime Value
SELECT calculate_avg_ltv('2024-01-01', '2024-12-31');

-- Reorder Probability (from Klaviyo)
SELECT calculate_avg_reorder_probability();

-- Subscription Retention Rate
SELECT calculate_subscription_retention_rate('2024-01-01', '2024-12-31');

-- Engagement Decay Rate (email inactivity trend)
SELECT calculate_engagement_decay_rate('2024-01-01', '2024-12-31');

-- Winback Email Open Rate
SELECT calculate_winback_email_open_rate('2024-01-01', '2024-12-31');

-- Replenishment Timing Accuracy
SELECT calculate_replenishment_accuracy();

-- CLV:CAC Ratio
SELECT calculate_avg_ltv_cac_ratio();
```

### 3. **Materialized Views**

#### `retention_metrics_summary`
Aggregated metrics summary (all time):
- Average repeat purchase rate, active customer rates, churn rates
- Average time between purchases
- Average and total LTV
- Average Klaviyo predictions
- Average email engagement metrics
- Average replenishment accuracy and LTV:CAC ratio

#### `customer_retention_cohorts_summary`
Cohort-level retention summary:
- Cohort size, active/churned counts by period
- Average orders and revenue per customer
- Average days between orders
- Average churn probability

#### `retention_metrics_trends`
Daily trends view:
- Shows daily metrics with percentages formatted
- Useful for time-series analysis

### 4. **Refresh Functions**

#### `refresh_retention_metrics_daily(target_date)`
Populates `retention_metrics_daily` for a specific date:
- Aggregates from `customers`, `shopify_orders`, `klaviyo_predictive_metrics`
- Calculates all metrics automatically
- Handles edge cases (NULL values, empty data)

#### `refresh_customer_retention_cohorts(target_date)`
Populates `customer_retention_cohorts`:
- Assigns customers to cohorts (by first order month)
- Calculates retention status (active/churned)
- Links Klaviyo predictions
- Updates replenishment timing accuracy

## 📊 Where Each Metric Is Stored

| Metric | Primary Storage | Query Method |
|--------|----------------|--------------|
| **Repeat Purchase Rate** | `retention_metrics_daily.repeat_purchase_rate` | `retention_metrics_summary.avg_repeat_purchase_rate` or `calculate_repeat_purchase_rate()` |
| **Time Between Purchases** | `retention_metrics_daily.avg_days_between_purchases` | `retention_metrics_summary.avg_days_between_purchases` or `calculate_avg_days_between_purchases()` |
| **Customer Lifetime Value (LTV)** | `retention_metrics_daily.avg_ltv` | `retention_metrics_summary.avg_ltv` or `calculate_avg_ltv()` |
| **Active Customer % (30d)** | `retention_metrics_daily.active_customer_rate_30d` | `retention_metrics_summary.avg_active_customer_rate_30d` or `calculate_active_customer_rate(30)` |
| **Active Customer % (60d)** | `retention_metrics_daily.active_customer_rate_60d` | `retention_metrics_summary.avg_active_customer_rate_60d` or `calculate_active_customer_rate(60)` |
| **Active Customer % (90d)** | `retention_metrics_daily.active_customer_rate_90d` | `retention_metrics_summary.avg_active_customer_rate_90d` or `calculate_active_customer_rate(90)` |
| **Churn Rate (30d)** | `retention_metrics_daily.churn_rate_30d` | `retention_metrics_summary.avg_churn_rate_30d` or `calculate_churn_rate(30)` |
| **Churn Rate (60d)** | `retention_metrics_daily.churn_rate_60d` | `retention_metrics_summary.avg_churn_rate_60d` or `calculate_churn_rate(60)` |
| **Churn Rate (90d)** | `retention_metrics_daily.churn_rate_90d` | `retention_metrics_summary.avg_churn_rate_90d` or `calculate_churn_rate(90)` |
| **Reorder Probability** | `retention_metrics_daily.avg_reorder_probability` | `retention_metrics_summary.avg_reorder_probability` or `calculate_avg_reorder_probability()` |
| **Subscription Retention Rate** | `retention_metrics_daily.subscription_retention_rate` | `retention_metrics_summary.avg_subscription_retention_rate` or `calculate_subscription_retention_rate()` |
| **Engagement Decay Rate** | `retention_metrics_daily.engagement_decay_rate` | `retention_metrics_summary.avg_engagement_decay_rate` or `calculate_engagement_decay_rate()` |
| **Winback Email Open Rate** | `retention_metrics_daily.winback_email_open_rate` | `retention_metrics_summary.avg_winback_email_open_rate` or `calculate_winback_email_open_rate()` |
| **Replenishment Timing Accuracy** | `retention_metrics_daily.avg_replenishment_accuracy_days` | `retention_metrics_summary.avg_replenishment_accuracy_days` or `calculate_replenishment_accuracy()` |
| **CLV:CAC Ratio** | `retention_metrics_daily.avg_ltv_cac_ratio` | `retention_metrics_summary.avg_ltv_cac_ratio` or `calculate_avg_ltv_cac_ratio()` |

## 🔗 Alignment with Existing Tables

### Uses Existing Data:
- **`customers`**: `total_orders`, `total_revenue`, `first_order_date`, `last_order_date`, `is_first_time_customer`
- **`shopify_orders`**: `order_date`, `customer_id`, `total_price`, `financial_status` (for calculating repeat purchases, time between orders)
- **`klaviyo_predictive_metrics`**: `predicted_next_order_date`, `predicted_churn_probability`, `predicted_lifetime_value`, `email_engagement_probability`
- **`klaviyo_profiles`**: Links Klaviyo predictions to customers
- **`klaviyo_events`**: For email engagement metrics (winback campaigns)
- **`klaviyo_campaigns`**: For identifying winback campaigns
- **`ad_events`**: For calculating CAC (used in LTV:CAC ratio)

### Integrates With:
- **`customer_lifetime_metrics` view**: LTV calculations align
- **`source_roi_summary` view**: LTV:CAC ratio calculations align
- **Acquisition metrics**: Uses CAC for LTV:CAC ratio
- **Consideration metrics**: Email engagement metrics align

## 🚀 Usage

### Populate Metrics

```bash
npm run metrics:retention:populate
```

This will:
- Refresh customer retention cohorts
- Process key dates (today, last 7 days, monthly samples)
- Populate `retention_metrics_daily`
- Calculate all metrics automatically

### Query All Metrics

```bash
npm run metrics:retention
```

Shows:
- Overall summary (all-time averages)
- Cohort summaries (last 5 cohorts)
- Daily trends (last 7 days)
- Sample function calculations

### Custom Queries

```sql
-- Get repeat purchase rate for last 30 days
SELECT calculate_repeat_purchase_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE);

-- Get churn rate by period
SELECT 
  calculate_churn_rate(30) as churn_30d,
  calculate_churn_rate(60) as churn_60d,
  calculate_churn_rate(90) as churn_90d;

-- Get cohort retention
SELECT 
  cohort_date,
  cohort_size,
  active_30d,
  active_90d,
  (active_90d::decimal / cohort_size * 100) as retention_90d_pct
FROM customer_retention_cohorts_summary
ORDER BY cohort_date DESC;

-- Get customers at risk (high churn probability)
SELECT 
  c.email,
  c.total_orders,
  c.total_revenue,
  crc.predicted_churn_probability,
  crc.is_churned_30d
FROM customer_retention_cohorts crc
JOIN customers c ON c.id = crc.customer_id
WHERE crc.predicted_churn_probability > 0.5
ORDER BY crc.predicted_churn_probability DESC;

-- Get replenishment candidates
SELECT 
  c.email,
  crc.predicted_next_order_date,
  crc.avg_days_between_orders,
  CASE 
    WHEN crc.predicted_next_order_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'IMMEDIATE'
    WHEN crc.predicted_next_order_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'SOON'
    ELSE 'LATER'
  END as replenishment_priority
FROM customer_retention_cohorts crc
JOIN customers c ON c.id = crc.customer_id
WHERE crc.predicted_next_order_date IS NOT NULL
  AND crc.is_active_30d = false
ORDER BY crc.predicted_next_order_date;
```

## 📈 Scheduled Refresh (Recommended)

Set up a cron job or scheduled Lambda to refresh metrics daily:

```sql
-- Refresh today's metrics
SELECT refresh_retention_metrics_daily(CURRENT_DATE);

-- Refresh customer cohorts (weekly recommended)
SELECT refresh_customer_retention_cohorts(CURRENT_DATE);

-- Refresh last 7 days (backfill)
DO $$
DECLARE
  d date;
BEGIN
  FOR d IN SELECT generate_series(CURRENT_DATE - 7, CURRENT_DATE - 1, '1 day'::interval)::date
  LOOP
    PERFORM refresh_retention_metrics_daily(d);
  END LOOP;
END $$;
```

## 📝 Notes

- Metrics are **pre-calculated** for performance (no real-time computation needed)
- Daily table is **append-only** (one row per date)
- Functions allow **custom date ranges** for ad-hoc analysis
- Views provide **aggregated summaries** across all time periods
- All metrics handle **NULL values** gracefully
- **Cohorts** are assigned by month of first order (can be customized)
- **Subscription retention** uses repeat customers as proxy (can be enhanced with actual subscription data)
- **Replenishment accuracy** compares Klaviyo predictions to actual next order dates
- **LTV:CAC ratio** integrates with acquisition metrics (uses CAC from `ad_events`)

## ✅ Status

All 11 retention metrics are now:
- ✅ Stored in database tables
- ✅ Calculated via SQL functions  
- ✅ Available in materialized views
- ✅ Populated with customer cohorts
- ✅ Queryable via scripts
- ✅ Aligned with existing customer, order, and Klaviyo data

## 🎯 Use Cases

1. **Measure Loyalty**: Track repeat purchase rates and time between purchases
2. **Identify Churn Risk**: Monitor churn rates and Klaviyo churn predictions
3. **Customer Segmentation**: Use active/churned status for campaigns
4. **Re-engagement**: Identify churned customers for winback campaigns
5. **Replenishment Timing**: Use predicted next order dates for replenishment campaigns
6. **ROI Analysis**: Monitor LTV:CAC ratios by cohort
7. **Email Strategy**: Track engagement decay and winback email performance
8. **Subscription Management**: Monitor subscription retention (if applicable)

