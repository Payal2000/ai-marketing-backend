-- ============================================================================
-- RETENTION METRICS IMPLEMENTATION
-- Pre-computed metrics for loyalty, repeat behavior, and churn risk
-- Aligned with existing customers, shopify_orders, and klaviyo_predictive_metrics
-- ============================================================================

-- ============================================================================
-- 1. RETENTION METRICS DAILY AGGREGATION TABLE
-- ============================================================================

DROP TABLE IF EXISTS retention_metrics_daily CASCADE;
CREATE TABLE retention_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  -- Customer Base
  total_customers int DEFAULT 0,
  active_customers_30d int DEFAULT 0,
  active_customers_60d int DEFAULT 0,
  active_customers_90d int DEFAULT 0,
  repeat_customers int DEFAULT 0,
  -- Calculated Metrics (stored for performance)
  repeat_purchase_rate decimal(5,4), -- Repeat Purchase Rate
  active_customer_rate_30d decimal(5,4), -- Active Customer % (30 days)
  active_customer_rate_60d decimal(5,4), -- Active Customer % (60 days)
  active_customer_rate_90d decimal(5,4), -- Active Customer % (90 days)
  churn_rate_30d decimal(5,4), -- Churn Rate (% inactive after 30 days)
  churn_rate_60d decimal(5,4), -- Churn Rate (% inactive after 60 days)
  churn_rate_90d decimal(5,4), -- Churn Rate (% inactive after 90 days)
  -- Time Between Purchases
  avg_days_between_purchases decimal(10,2), -- Average time between purchases for repeat customers
  median_days_between_purchases decimal(10,2), -- Median time between purchases
  -- Customer Lifetime Value
  avg_ltv decimal(12,2), -- Average LTV
  median_ltv decimal(12,2), -- Median LTV
  total_ltv decimal(15,2), -- Total LTV across all customers
  -- Klaviyo Predictive Metrics
  avg_reorder_probability decimal(5,4), -- Average reorder probability from Klaviyo
  avg_churn_probability decimal(5,4), -- Average churn probability from Klaviyo
  avg_predicted_ltv decimal(12,2), -- Average predicted LTV from Klaviyo
  -- Email Engagement
  avg_email_engagement_probability decimal(5,4), -- Average email engagement probability
  engagement_decay_rate decimal(5,4), -- Email inactivity trend (declining engagement)
  winback_email_open_rate decimal(5,4), -- Winback email open rate
  -- Subscription Metrics (if applicable)
  subscription_retention_rate decimal(5,4), -- Subscription retention rate
  -- Replenishment Timing
  avg_replenishment_accuracy_days decimal(10,2), -- Average accuracy of predicted vs actual reorder timing
  -- CLV:CAC Ratio
  avg_ltv_cac_ratio decimal(10,2), -- Average LTV:CAC ratio
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(date)
);

CREATE INDEX IF NOT EXISTS retention_metrics_daily_date_idx ON retention_metrics_daily(date);

-- ============================================================================
-- 2. CUSTOMER RETENTION COHORT TABLE
-- ============================================================================

DROP TABLE IF EXISTS customer_retention_cohorts CASCADE;
CREATE TABLE customer_retention_cohorts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  cohort_date date NOT NULL, -- First order date (cohort month/week)
  -- Purchase History
  first_order_date date NOT NULL,
  last_order_date date,
  total_orders int DEFAULT 0,
  total_revenue decimal(12,2) DEFAULT 0,
  -- Time Metrics
  days_since_first_order int,
  days_since_last_order int,
  avg_days_between_orders decimal(10,2),
  -- Retention Status
  is_active_30d boolean DEFAULT false,
  is_active_60d boolean DEFAULT false,
  is_active_90d boolean DEFAULT false,
  is_churned_30d boolean DEFAULT false,
  is_churned_60d boolean DEFAULT false,
  is_churned_90d boolean DEFAULT false,
  is_repeat_customer boolean DEFAULT false,
  -- Klaviyo Predictions
  predicted_next_order_date date,
  predicted_churn_probability decimal(5,4),
  predicted_ltv decimal(12,2),
  email_engagement_probability decimal(5,4),
  -- Replenishment
  predicted_replenishment_date date,
  actual_replenishment_date date,
  replenishment_accuracy_days int, -- Difference between predicted and actual
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id, cohort_date)
);

CREATE INDEX IF NOT EXISTS customer_retention_cohorts_customer_idx ON customer_retention_cohorts(customer_id);
CREATE INDEX IF NOT EXISTS customer_retention_cohorts_cohort_idx ON customer_retention_cohorts(cohort_date);
CREATE INDEX IF NOT EXISTS customer_retention_cohorts_active_idx ON customer_retention_cohorts(is_active_30d, is_active_60d, is_active_90d);
CREATE INDEX IF NOT EXISTS customer_retention_cohorts_churn_idx ON customer_retention_cohorts(is_churned_30d, is_churned_60d, is_churned_90d);

-- ============================================================================
-- 3. FUNCTIONS FOR CALCULATING METRICS
-- ============================================================================

-- Function: Calculate Repeat Purchase Rate
CREATE OR REPLACE FUNCTION calculate_repeat_purchase_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE total_orders > 1)::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE total_orders > 0), 0),
      0
    )
  FROM customers
  WHERE (start_date IS NULL OR first_order_date >= start_date)
    AND (end_date IS NULL OR first_order_date <= end_date);
$$ LANGUAGE sql STABLE;

-- Function: Calculate Average Time Between Purchases
CREATE OR REPLACE FUNCTION calculate_avg_days_between_purchases(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(10,2) AS $$
  WITH order_intervals AS (
    SELECT 
      o1.customer_id,
      (o2.order_date::date - o1.order_date::date)::integer as days_between
    FROM shopify_orders o1
    JOIN shopify_orders o2 ON o2.customer_id = o1.customer_id
      AND o2.order_date > o1.order_date
      AND o2.financial_status = 'paid'
    WHERE o1.financial_status = 'paid'
      AND (start_date IS NULL OR o1.order_date::date >= start_date)
      AND (end_date IS NULL OR o1.order_date::date <= end_date)
    GROUP BY o1.customer_id, (o2.order_date::date - o1.order_date::date)
  ),
  customer_intervals AS (
    SELECT 
      customer_id,
      MIN(days_between) as min_days_between
    FROM order_intervals
    GROUP BY customer_id
  )
  SELECT 
    COALESCE(AVG(min_days_between), 0)
  FROM customer_intervals;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Active Customer % (purchased in last X days)
CREATE OR REPLACE FUNCTION calculate_active_customer_rate(
  days_active int DEFAULT 30
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE last_order_date >= CURRENT_DATE - (days_active || ' days')::interval)::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE total_orders > 0), 0),
      0
    )
  FROM customers;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Churn Rate (% inactive after X days)
CREATE OR REPLACE FUNCTION calculate_churn_rate(
  days_inactive int DEFAULT 30
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (
        WHERE total_orders > 0 
          AND (last_order_date IS NULL OR last_order_date < CURRENT_DATE - (days_inactive || ' days')::interval)
      )::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE total_orders > 0), 0),
      0
    )
  FROM customers;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Average LTV
CREATE OR REPLACE FUNCTION calculate_avg_ltv(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(12,2) AS $$
  SELECT 
    COALESCE(AVG(total_revenue), 0)
  FROM customers
  WHERE total_orders > 0
    AND (start_date IS NULL OR first_order_date >= start_date)
    AND (end_date IS NULL OR first_order_date <= end_date);
$$ LANGUAGE sql STABLE;

-- Function: Calculate Average Reorder Probability (from Klaviyo)
CREATE OR REPLACE FUNCTION calculate_avg_reorder_probability()
RETURNS decimal(5,4) AS $$
  WITH latest_predictions AS (
    SELECT DISTINCT ON (profile_id)
      profile_id,
      predicted_next_order_date,
      CASE 
        WHEN predicted_next_order_date IS NOT NULL AND predicted_next_order_date >= CURRENT_DATE THEN 0.8
        WHEN predicted_next_order_date IS NOT NULL AND predicted_next_order_date < CURRENT_DATE THEN 0.3
        ELSE 0.5
      END as reorder_probability
    FROM klaviyo_predictive_metrics
    ORDER BY profile_id, calculated_at DESC
  )
  SELECT 
    COALESCE(AVG(reorder_probability), 0)
  FROM latest_predictions;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Subscription Retention Rate (if applicable)
CREATE OR REPLACE FUNCTION calculate_subscription_retention_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  -- For MVP: Use repeat customers as proxy for subscription retention
  -- In production, this would query actual subscription data
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE total_orders > 1 AND last_order_date >= CURRENT_DATE - INTERVAL '90 days')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE total_orders > 1), 0),
      0
    )
  FROM customers
  WHERE total_orders > 1
    AND (start_date IS NULL OR first_order_date >= start_date)
    AND (end_date IS NULL OR first_order_date <= end_date);
$$ LANGUAGE sql STABLE;

-- Function: Calculate Engagement Decay Rate (email inactivity trend)
CREATE OR REPLACE FUNCTION calculate_engagement_decay_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  WITH email_activity AS (
    SELECT 
      DATE_TRUNC('week', ke.occurred_at) as week,
      COUNT(DISTINCT ke.profile_id) FILTER (WHERE ke.event_type IN ('Opened Email', 'Clicked Email')) as engaged_profiles,
      COUNT(DISTINCT ke.profile_id) as total_profiles
    FROM klaviyo_events ke
    WHERE ke.event_type IN ('Sent Email', 'Opened Email', 'Clicked Email')
      AND (start_date IS NULL OR ke.occurred_at >= start_date)
      AND (end_date IS NULL OR ke.occurred_at <= end_date)
    GROUP BY DATE_TRUNC('week', ke.occurred_at)
  ),
  engagement_rates AS (
    SELECT 
      week,
      CASE 
        WHEN total_profiles > 0 THEN engaged_profiles::decimal / total_profiles
        ELSE 0
      END as engagement_rate
    FROM email_activity
  )
  SELECT 
    COALESCE(
      -- Calculate slope (trend) - negative means decay
      (SELECT 
        (last_rate - first_rate) / NULLIF(GREATEST(EXTRACT(EPOCH FROM (MAX(week) - MIN(week))) / 86400, 1), 0)
      FROM (
        SELECT 
          MIN(engagement_rate) FILTER (WHERE week = (SELECT MIN(week) FROM engagement_rates)) as first_rate,
          MAX(engagement_rate) FILTER (WHERE week = (SELECT MAX(week) FROM engagement_rates)) as last_rate
        FROM engagement_rates
      ) rates),
      0
    )
  FROM engagement_rates
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Winback Email Open Rate
CREATE OR REPLACE FUNCTION calculate_winback_email_open_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  WITH winback_campaigns AS (
    SELECT DISTINCT kc.id
    FROM klaviyo_campaigns kc
    WHERE LOWER(kc.name) LIKE '%winback%' 
       OR LOWER(kc.name) LIKE '%re-engage%'
       OR LOWER(kc.name) LIKE '%reactivate%'
  ),
  winback_events AS (
    SELECT 
      COUNT(*) FILTER (WHERE ke.event_type = 'Opened Email') as opens,
      COUNT(*) FILTER (WHERE ke.event_type = 'Sent Email') as sends
    FROM klaviyo_events ke
    JOIN klaviyo_campaigns kc ON kc.id = ke.campaign_id
    WHERE kc.id IN (SELECT id FROM winback_campaigns)
      AND (start_date IS NULL OR ke.occurred_at >= start_date)
      AND (end_date IS NULL OR ke.occurred_at <= end_date)
  )
  SELECT 
    COALESCE(
      opens::decimal / NULLIF(sends, 0),
      0
    )
  FROM winback_events;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Replenishment Timing Accuracy
CREATE OR REPLACE FUNCTION calculate_replenishment_accuracy()
RETURNS decimal(10,2) AS $$
  WITH customer_predictions AS (
    SELECT DISTINCT ON (c.id)
      c.id as customer_id,
      kpm.predicted_next_order_date,
      (SELECT MIN(order_date::date) 
       FROM shopify_orders 
       WHERE customer_id = c.id 
         AND order_date::date > kpm.calculated_at::date
         AND financial_status = 'paid'
      ) as actual_next_order_date
    FROM customers c
    JOIN klaviyo_profiles kp ON kp.customer_id = c.id
    JOIN klaviyo_predictive_metrics kpm ON kpm.profile_id = kp.id
    WHERE kpm.predicted_next_order_date IS NOT NULL
      AND c.total_orders > 0
    ORDER BY c.id, kpm.calculated_at DESC
  )
  SELECT 
    COALESCE(
      AVG(ABS((predicted_next_order_date - actual_next_order_date)::integer)),
      0
    )
  FROM customer_predictions
  WHERE actual_next_order_date IS NOT NULL;
$$ LANGUAGE sql STABLE;

-- Function: Calculate CLV:CAC Ratio (Average)
CREATE OR REPLACE FUNCTION calculate_avg_ltv_cac_ratio()
RETURNS decimal(10,2) AS $$
  WITH customer_cac AS (
    SELECT 
      c.id,
      COALESCE(
        SUM(ae.spend) / NULLIF(COUNT(DISTINCT ae.id), 0),
        0
      ) as cac
    FROM customers c
    LEFT JOIN ad_events ae ON ae.customer_id = c.id
      AND ae.event_type IN ('conversion', 'purchase')
    WHERE c.total_orders > 0
    GROUP BY c.id
  ),
  customer_ltv AS (
    SELECT 
      id,
      total_revenue as ltv
    FROM customers
    WHERE total_orders > 0
  )
  SELECT 
    COALESCE(
      AVG(
        CASE 
          WHEN cc.cac > 0 THEN cl.ltv / cc.cac
          ELSE NULL
        END
      ),
      0
    )
  FROM customer_ltv cl
  JOIN customer_cac cc ON cc.id = cl.id
  WHERE cc.cac > 0;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 4. MATERIALIZED VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Retention Metrics Summary (All Time)
CREATE OR REPLACE VIEW retention_metrics_summary AS
SELECT 
  SUM(total_customers) as total_customers_all_time,
  AVG(repeat_purchase_rate) as avg_repeat_purchase_rate,
  AVG(active_customer_rate_30d) as avg_active_customer_rate_30d,
  AVG(active_customer_rate_60d) as avg_active_customer_rate_60d,
  AVG(active_customer_rate_90d) as avg_active_customer_rate_90d,
  AVG(churn_rate_30d) as avg_churn_rate_30d,
  AVG(churn_rate_60d) as avg_churn_rate_60d,
  AVG(churn_rate_90d) as avg_churn_rate_90d,
  AVG(avg_days_between_purchases) as avg_days_between_purchases,
  AVG(median_days_between_purchases) as avg_median_days_between_purchases,
  AVG(avg_ltv) as avg_ltv,
  AVG(median_ltv) as avg_median_ltv,
  SUM(total_ltv) as total_ltv_all_time,
  AVG(avg_reorder_probability) as avg_reorder_probability,
  AVG(avg_churn_probability) as avg_churn_probability,
  AVG(avg_predicted_ltv) as avg_predicted_ltv,
  AVG(avg_email_engagement_probability) as avg_email_engagement_probability,
  AVG(engagement_decay_rate) as avg_engagement_decay_rate,
  AVG(winback_email_open_rate) as avg_winback_email_open_rate,
  AVG(subscription_retention_rate) as avg_subscription_retention_rate,
  AVG(avg_replenishment_accuracy_days) as avg_replenishment_accuracy_days,
  AVG(avg_ltv_cac_ratio) as avg_ltv_cac_ratio
FROM retention_metrics_daily;

-- View: Customer Retention Cohorts Summary
CREATE OR REPLACE VIEW customer_retention_cohorts_summary AS
SELECT 
  cohort_date,
  COUNT(*) as cohort_size,
  COUNT(*) FILTER (WHERE is_repeat_customer) as repeat_customers,
  COUNT(*) FILTER (WHERE is_active_30d) as active_30d,
  COUNT(*) FILTER (WHERE is_active_60d) as active_60d,
  COUNT(*) FILTER (WHERE is_active_90d) as active_90d,
  COUNT(*) FILTER (WHERE is_churned_30d) as churned_30d,
  COUNT(*) FILTER (WHERE is_churned_60d) as churned_60d,
  COUNT(*) FILTER (WHERE is_churned_90d) as churned_90d,
  AVG(total_orders) as avg_orders_per_customer,
  AVG(total_revenue) as avg_revenue_per_customer,
  AVG(avg_days_between_orders) as avg_days_between_orders,
  AVG(predicted_churn_probability) as avg_churn_probability
FROM customer_retention_cohorts
GROUP BY cohort_date
ORDER BY cohort_date DESC;

-- View: Daily Retention Trends
CREATE OR REPLACE VIEW retention_metrics_trends AS
SELECT 
  date,
  total_customers,
  repeat_purchase_rate * 100 as repeat_purchase_rate_pct,
  active_customer_rate_30d * 100 as active_customer_rate_30d_pct,
  active_customer_rate_60d * 100 as active_customer_rate_60d_pct,
  active_customer_rate_90d * 100 as active_customer_rate_90d_pct,
  churn_rate_30d * 100 as churn_rate_30d_pct,
  churn_rate_60d * 100 as churn_rate_60d_pct,
  churn_rate_90d * 100 as churn_rate_90d_pct,
  avg_days_between_purchases,
  avg_ltv,
  avg_reorder_probability * 100 as avg_reorder_probability_pct,
  avg_churn_probability * 100 as avg_churn_probability_pct,
  engagement_decay_rate,
  winback_email_open_rate * 100 as winback_email_open_rate_pct,
  subscription_retention_rate * 100 as subscription_retention_rate_pct,
  avg_replenishment_accuracy_days,
  avg_ltv_cac_ratio
FROM retention_metrics_daily
ORDER BY date DESC;

-- ============================================================================
-- 5. FUNCTION TO POPULATE DAILY RETENTION METRICS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_retention_metrics_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
DECLARE
  v_total_customers int;
  v_active_30d int;
  v_active_60d int;
  v_active_90d int;
  v_repeat_customers int;
  v_total_orders_for_date int;
BEGIN
  -- Delete existing records for the target date
  DELETE FROM retention_metrics_daily WHERE date = target_date;

  -- Get customer counts
  SELECT 
    COUNT(*) FILTER (WHERE total_orders > 0),
    COUNT(*) FILTER (WHERE last_order_date >= target_date - INTERVAL '30 days' AND total_orders > 0),
    COUNT(*) FILTER (WHERE last_order_date >= target_date - INTERVAL '60 days' AND total_orders > 0),
    COUNT(*) FILTER (WHERE last_order_date >= target_date - INTERVAL '90 days' AND total_orders > 0),
    COUNT(*) FILTER (WHERE total_orders > 1)
  INTO 
    v_total_customers,
    v_active_30d,
    v_active_60d,
    v_active_90d,
    v_repeat_customers
  FROM customers;

  -- Insert aggregated metrics
  INSERT INTO retention_metrics_daily (
    date,
    total_customers,
    active_customers_30d,
    active_customers_60d,
    active_customers_90d,
    repeat_customers,
    repeat_purchase_rate,
    active_customer_rate_30d,
    active_customer_rate_60d,
    active_customer_rate_90d,
    churn_rate_30d,
    churn_rate_60d,
    churn_rate_90d,
    avg_days_between_purchases,
    median_days_between_purchases,
    avg_ltv,
    median_ltv,
    total_ltv,
    avg_reorder_probability,
    avg_churn_probability,
    avg_predicted_ltv,
    avg_email_engagement_probability,
    engagement_decay_rate,
    winback_email_open_rate,
    subscription_retention_rate,
    avg_replenishment_accuracy_days,
    avg_ltv_cac_ratio
  )
  SELECT 
    target_date,
    v_total_customers,
    v_active_30d,
    v_active_60d,
    v_active_90d,
    v_repeat_customers,
    -- Repeat purchase rate
    CASE WHEN v_total_customers > 0 THEN v_repeat_customers::decimal / v_total_customers ELSE NULL END,
    -- Active customer rates
    CASE WHEN v_total_customers > 0 THEN v_active_30d::decimal / v_total_customers ELSE NULL END,
    CASE WHEN v_total_customers > 0 THEN v_active_60d::decimal / v_total_customers ELSE NULL END,
    CASE WHEN v_total_customers > 0 THEN v_active_90d::decimal / v_total_customers ELSE NULL END,
    -- Churn rates
    CASE 
      WHEN v_total_customers > 0 
      THEN (v_total_customers - v_active_30d)::decimal / v_total_customers
      ELSE NULL 
    END,
    CASE 
      WHEN v_total_customers > 0 
      THEN (v_total_customers - v_active_60d)::decimal / v_total_customers
      ELSE NULL 
    END,
    CASE 
      WHEN v_total_customers > 0 
      THEN (v_total_customers - v_active_90d)::decimal / v_total_customers
      ELSE NULL 
    END,
    -- Time between purchases
    (SELECT calculate_avg_days_between_purchases(NULL, target_date)),
    -- Median days between purchases (simplified - using percentile)
    (
      SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_between)
      FROM (
      SELECT DISTINCT
        (o2.order_date::date - o1.order_date::date)::integer as days_between
      FROM shopify_orders o1
      JOIN shopify_orders o2 ON o2.customer_id = o1.customer_id
        AND o2.order_date > o1.order_date
        AND o2.financial_status = 'paid'
      WHERE o1.financial_status = 'paid'
        AND o1.order_date::date <= target_date
      LIMIT 1000
      ) intervals
    ),
    -- Average LTV
    (SELECT calculate_avg_ltv(NULL, target_date)),
    -- Median LTV
    (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_revenue) FROM customers WHERE total_orders > 0),
    -- Total LTV
    (SELECT SUM(total_revenue) FROM customers WHERE total_orders > 0),
    -- Klaviyo predictions (average)
    (
      SELECT AVG(
        CASE 
          WHEN predicted_next_order_date IS NOT NULL AND predicted_next_order_date >= target_date THEN 0.8
          WHEN predicted_next_order_date IS NOT NULL AND predicted_next_order_date < target_date THEN 0.3
          ELSE 0.5
        END
      )
      FROM (
        SELECT DISTINCT ON (profile_id)
          predicted_next_order_date
        FROM klaviyo_predictive_metrics
        WHERE calculated_at::date <= target_date
        ORDER BY profile_id, calculated_at DESC
      ) latest_predictions
    ),
    -- Average churn probability
    (
      SELECT AVG(predicted_churn_probability)
      FROM (
        SELECT DISTINCT ON (profile_id)
          predicted_churn_probability
        FROM klaviyo_predictive_metrics
        WHERE calculated_at::date <= target_date
          AND predicted_churn_probability IS NOT NULL
        ORDER BY profile_id, calculated_at DESC
      ) latest_churn
    ),
    -- Average predicted LTV
    (
      SELECT AVG(predicted_lifetime_value)
      FROM (
        SELECT DISTINCT ON (profile_id)
          predicted_lifetime_value
        FROM klaviyo_predictive_metrics
        WHERE calculated_at::date <= target_date
          AND predicted_lifetime_value IS NOT NULL
        ORDER BY profile_id, calculated_at DESC
      ) latest_ltv
    ),
    -- Average email engagement probability
    (
      SELECT AVG(email_engagement_probability)
      FROM (
        SELECT DISTINCT ON (profile_id)
          email_engagement_probability
        FROM klaviyo_predictive_metrics
        WHERE calculated_at::date <= target_date
          AND email_engagement_probability IS NOT NULL
        ORDER BY profile_id, calculated_at DESC
      ) latest_engagement
    ),
    -- Engagement decay rate (simplified for daily)
    (
      SELECT calculate_engagement_decay_rate((target_date - INTERVAL '30 days')::date, target_date)
    ),
    -- Winback email open rate
    (
      SELECT calculate_winback_email_open_rate((target_date - INTERVAL '30 days')::date, target_date)
    ),
    -- Subscription retention rate
    (
      SELECT calculate_subscription_retention_rate(NULL, target_date)
    ),
    -- Replenishment accuracy
    (
      SELECT calculate_replenishment_accuracy()
    ),
    -- LTV:CAC ratio
    (
      SELECT calculate_avg_ltv_cac_ratio()
    )
  FROM (SELECT 1) dummy;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. FUNCTION TO POPULATE CUSTOMER RETENTION COHORTS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_customer_retention_cohorts(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
BEGIN
  -- Delete and refresh cohorts for all customers
  DELETE FROM customer_retention_cohorts;

  -- Insert customer cohorts
  INSERT INTO customer_retention_cohorts (
    customer_id,
    cohort_date,
    first_order_date,
    last_order_date,
    total_orders,
    total_revenue,
    days_since_first_order,
    days_since_last_order,
    avg_days_between_orders,
    is_active_30d,
    is_active_60d,
    is_active_90d,
    is_churned_30d,
    is_churned_60d,
    is_churned_90d,
    is_repeat_customer,
    predicted_next_order_date,
    predicted_churn_probability,
    predicted_ltv,
    email_engagement_probability
  )
  SELECT 
    c.id,
    DATE_TRUNC('month', c.first_order_date)::date as cohort_date,
    c.first_order_date,
    c.last_order_date,
    c.total_orders,
    c.total_revenue,
    (target_date - c.first_order_date)::integer as days_since_first_order,
    CASE 
      WHEN c.last_order_date IS NOT NULL THEN (target_date - c.last_order_date)::integer
      ELSE NULL
    END as days_since_last_order,
    -- Average days between orders
    (
      SELECT AVG(days_between)
      FROM (
        SELECT DISTINCT
          (o2.order_date::date - o1.order_date::date)::integer as days_between
        FROM shopify_orders o1
        JOIN shopify_orders o2 ON o2.customer_id = o1.customer_id
          AND o2.order_date > o1.order_date
          AND o2.financial_status = 'paid'
        WHERE o1.customer_id = c.id
          AND o1.financial_status = 'paid'
        LIMIT 10
      ) intervals
    ) as avg_days_between_orders,
    -- Active status
    (c.last_order_date >= target_date - INTERVAL '30 days' AND c.total_orders > 0) as is_active_30d,
    (c.last_order_date >= target_date - INTERVAL '60 days' AND c.total_orders > 0) as is_active_60d,
    (c.last_order_date >= target_date - INTERVAL '90 days' AND c.total_orders > 0) as is_active_90d,
    -- Churn status
    (c.total_orders > 0 AND (c.last_order_date IS NULL OR c.last_order_date < target_date - INTERVAL '30 days')) as is_churned_30d,
    (c.total_orders > 0 AND (c.last_order_date IS NULL OR c.last_order_date < target_date - INTERVAL '60 days')) as is_churned_60d,
    (c.total_orders > 0 AND (c.last_order_date IS NULL OR c.last_order_date < target_date - INTERVAL '90 days')) as is_churned_90d,
    -- Repeat customer
    (c.total_orders > 1) as is_repeat_customer,
    -- Klaviyo predictions (latest)
    (
      SELECT kpm.predicted_next_order_date
      FROM klaviyo_profiles kp
      JOIN klaviyo_predictive_metrics kpm ON kpm.profile_id = kp.id
      WHERE kp.customer_id = c.id
      ORDER BY kpm.calculated_at DESC
      LIMIT 1
    ) as predicted_next_order_date,
    (
      SELECT kpm.predicted_churn_probability
      FROM klaviyo_profiles kp
      JOIN klaviyo_predictive_metrics kpm ON kpm.profile_id = kp.id
      WHERE kp.customer_id = c.id
      ORDER BY kpm.calculated_at DESC
      LIMIT 1
    ) as predicted_churn_probability,
    (
      SELECT kpm.predicted_lifetime_value
      FROM klaviyo_profiles kp
      JOIN klaviyo_predictive_metrics kpm ON kpm.profile_id = kp.id
      WHERE kp.customer_id = c.id
      ORDER BY kpm.calculated_at DESC
      LIMIT 1
    ) as predicted_ltv,
    (
      SELECT kpm.email_engagement_probability
      FROM klaviyo_profiles kp
      JOIN klaviyo_predictive_metrics kpm ON kpm.profile_id = kp.id
      WHERE kp.customer_id = c.id
      ORDER BY kpm.calculated_at DESC
      LIMIT 1
    ) as email_engagement_probability
  FROM customers c
  WHERE c.total_orders > 0;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. TRIGGERS FOR AUTO-UPDATE
-- ============================================================================

DROP TRIGGER IF EXISTS retention_metrics_daily_updated_at ON retention_metrics_daily;
CREATE TRIGGER retention_metrics_daily_updated_at 
  BEFORE UPDATE ON retention_metrics_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS customer_retention_cohorts_updated_at ON customer_retention_cohorts;
CREATE TRIGGER customer_retention_cohorts_updated_at 
  BEFORE UPDATE ON customer_retention_cohorts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 8. COMMENTS
-- ============================================================================

COMMENT ON TABLE retention_metrics_daily IS 'Daily aggregated retention metrics (loyalty, repeat behavior, churn risk)';
COMMENT ON TABLE customer_retention_cohorts IS 'Customer-level retention cohorts with predictions and status';
COMMENT ON VIEW retention_metrics_summary IS 'Aggregated retention metrics summary (all time)';
COMMENT ON VIEW customer_retention_cohorts_summary IS 'Cohort-level retention summary';
COMMENT ON VIEW retention_metrics_trends IS 'Daily retention metrics trends';

