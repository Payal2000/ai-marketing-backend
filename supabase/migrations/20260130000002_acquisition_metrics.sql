-- ============================================================================
-- ACQUISITION METRICS IMPLEMENTATION
-- Pre-computed metrics for efficient querying
-- ============================================================================

-- ============================================================================
-- 1. ACQUISITION METRICS DAILY AGGREGATION TABLE
-- ============================================================================

DROP TABLE IF EXISTS acquisition_metrics_daily CASCADE;
CREATE TABLE acquisition_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform text NOT NULL,
  campaign_id text,
  date date NOT NULL,
  -- Spend & Traffic
  total_spend decimal(12,2) DEFAULT 0,
  total_impressions int DEFAULT 0,
  total_clicks int DEFAULT 0,
  total_conversions int DEFAULT 0,
  total_revenue decimal(12,2) DEFAULT 0,
  -- Calculated Metrics (stored for performance)
  cpc decimal(10,4), -- Cost per Click
  cpm decimal(10,4), -- Cost per Mille (per 1000 impressions)
  ctr decimal(5,4), -- Click-Through Rate
  cvr decimal(5,4), -- Conversion Rate
  roas decimal(10,2), -- Return on Ad Spend
  -- New Customers / Leads
  new_customers_count int DEFAULT 0,
  email_signups_count int DEFAULT 0,
  cost_per_customer decimal(10,2), -- CAC
  cost_per_signup decimal(10,2),
  -- Traffic Sources
  sessions_count int DEFAULT 0,
  bounced_sessions_count int DEFAULT 0,
  bounce_rate decimal(5,4),
  session_to_signup_ratio decimal(5,4),
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS acquisition_metrics_daily_date_idx ON acquisition_metrics_daily(date);
CREATE INDEX IF NOT EXISTS acquisition_metrics_daily_platform_idx ON acquisition_metrics_daily(platform);
CREATE INDEX IF NOT EXISTS acquisition_metrics_daily_campaign_idx ON acquisition_metrics_daily(campaign_id) WHERE campaign_id IS NOT NULL;
-- Unique constraint handling NULL campaign_id (using partial index for better performance)
CREATE UNIQUE INDEX IF NOT EXISTS acquisition_metrics_daily_unique_idx 
  ON acquisition_metrics_daily(platform, date) 
  WHERE campaign_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS acquisition_metrics_daily_unique_idx_campaign 
  ON acquisition_metrics_daily(platform, campaign_id, date) 
  WHERE campaign_id IS NOT NULL;

-- ============================================================================
-- 2. TRAFFIC SOURCE METRICS TABLE
-- ============================================================================

DROP TABLE IF EXISTS traffic_source_metrics_daily CASCADE;
CREATE TABLE traffic_source_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL, -- 'online_store', 'pos', 'api', 'email', 'social', 'search', 'direct', etc.
  utm_source text,
  utm_medium text,
  utm_campaign text,
  date date NOT NULL,
  -- Traffic
  sessions_count int DEFAULT 0,
  page_views_count int DEFAULT 0,
  unique_visitors_count int DEFAULT 0,
  -- Engagement
  bounced_sessions_count int DEFAULT 0,
  avg_session_duration_seconds int DEFAULT 0,
  -- Conversions
  signups_count int DEFAULT 0,
  orders_count int DEFAULT 0,
  revenue decimal(12,2) DEFAULT 0,
  -- Calculated Metrics
  bounce_rate decimal(5,4),
  signup_rate decimal(5,4),
  conversion_rate decimal(5,4),
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS traffic_source_metrics_date_idx ON traffic_source_metrics_daily(date);
CREATE INDEX IF NOT EXISTS traffic_source_metrics_source_idx ON traffic_source_metrics_daily(source);
-- Unique constraint handling NULL UTM values
CREATE UNIQUE INDEX IF NOT EXISTS traffic_source_metrics_daily_unique_idx 
  ON traffic_source_metrics_daily(source, COALESCE(utm_source, ''), COALESCE(utm_medium, ''), COALESCE(utm_campaign, ''), date);

-- ============================================================================
-- 3. FUNCTIONS FOR CALCULATING METRICS
-- ============================================================================

-- Function: Calculate CAC (Customer Acquisition Cost)
CREATE OR REPLACE FUNCTION calculate_cac(
  platform_param text,
  start_date date,
  end_date date
)
RETURNS decimal(10,2) AS $$
  SELECT 
    COALESCE(
      SUM(spend) / NULLIF(COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL), 0),
      0
    )
  FROM ad_events
  WHERE platform = platform_param
    AND date BETWEEN start_date AND end_date
    AND (event_type = 'conversion' OR event_type = 'purchase');
$$ LANGUAGE sql STABLE;

-- Function: Calculate CTR (Click-Through Rate)
CREATE OR REPLACE FUNCTION calculate_ctr(
  platform_param text,
  campaign_id_param text DEFAULT NULL,
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      SUM(clicks)::decimal / NULLIF(SUM(impressions), 0),
      0
    )
  FROM ad_events
  WHERE platform = platform_param
    AND (campaign_id_param IS NULL OR campaign_id = campaign_id_param)
    AND (start_date IS NULL OR date >= start_date)
    AND (end_date IS NULL OR date <= end_date)
    AND impressions > 0;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Conversion Rate (CVR)
CREATE OR REPLACE FUNCTION calculate_cvr(
  platform_param text,
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT ae.customer_id) FILTER (WHERE c.id IS NOT NULL)::decimal / 
      NULLIF(SUM(ae.clicks), 0),
      0
    )
  FROM ad_events ae
  LEFT JOIN customers c ON c.id = ae.customer_id AND c.is_first_time_customer = true
  WHERE ae.platform = platform_param
    AND ae.date BETWEEN start_date AND end_date
    AND ae.event_type = 'click';
$$ LANGUAGE sql STABLE;

-- Function: Calculate Cost per Signup
CREATE OR REPLACE FUNCTION calculate_cost_per_signup(
  platform_param text,
  start_date date,
  end_date date
)
RETURNS decimal(10,2) AS $$
  SELECT 
    COALESCE(
      SUM(ae.spend) / 
      NULLIF(
        COUNT(DISTINCT ke.id) FILTER (
          WHERE ke.event_type = 'Subscribed to List' 
          AND ke.occurred_at >= ae.date
          AND ke.occurred_at < ae.date + INTERVAL '7 days'
        ),
        0
      ),
      0
    )
  FROM ad_events ae
  LEFT JOIN klaviyo_events ke ON ke.customer_id = ae.customer_id
  WHERE ae.platform = platform_param
    AND ae.date BETWEEN start_date AND end_date
    AND ae.spend > 0;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Session-to-Signup Ratio
CREATE OR REPLACE FUNCTION calculate_session_to_signup_ratio(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')::decimal / 
      NULLIF(COUNT(DISTINCT se.session_id), 0),
      0
    )
  FROM shopify_events se
  LEFT JOIN customers c ON c.id = se.customer_id
  LEFT JOIN klaviyo_events ke ON ke.customer_id = c.id
  WHERE se.event_type = 'page_viewed'
    AND se.occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Bounce Rate
CREATE OR REPLACE FUNCTION calculate_bounce_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  WITH session_pages AS (
    SELECT 
      session_id,
      COUNT(*) as page_views,
      EXTRACT(EPOCH FROM (MAX(occurred_at) - MIN(occurred_at))) as session_duration_seconds
    FROM shopify_events
    WHERE event_type = 'page_viewed'
      AND session_id IS NOT NULL
      AND occurred_at::date BETWEEN start_date AND end_date
    GROUP BY session_id
  )
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE page_views = 1 OR session_duration_seconds < 30)::decimal / 
      NULLIF(COUNT(*), 0),
      0
    )
  FROM session_pages;
$$ LANGUAGE sql STABLE;

-- Function: Calculate LTV:CAC Ratio by Platform
CREATE OR REPLACE FUNCTION calculate_ltv_cac_ratio(
  platform_param text
)
RETURNS decimal(10,2) AS $$
  WITH channel_cac AS (
    SELECT 
      SUM(spend) / NULLIF(COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL), 0) as cac
    FROM ad_events
    WHERE platform = platform_param
      AND event_type IN ('conversion', 'purchase')
  ),
  channel_ltv AS (
    SELECT 
      AVG(c.total_revenue) as avg_ltv
    FROM ad_events ae
    JOIN customers c ON c.id = ae.customer_id
    WHERE ae.platform = platform_param
      AND ae.customer_id IS NOT NULL
  )
  SELECT 
    COALESCE(cl.avg_ltv / NULLIF(cc.cac, 0), 0)
  FROM channel_cac cc, channel_ltv cl;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 4. MATERIALIZED VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Acquisition Metrics Summary by Platform
CREATE OR REPLACE VIEW acquisition_metrics_summary AS
SELECT 
  platform,
  SUM(total_spend) as total_spend,
  SUM(total_impressions) as total_impressions,
  SUM(total_clicks) as total_clicks,
  SUM(total_conversions) as total_conversions,
  SUM(total_revenue) as total_revenue,
  SUM(new_customers_count) as total_new_customers,
  SUM(email_signups_count) as total_signups,
  -- Calculated aggregations
  CASE WHEN SUM(total_clicks) > 0 
    THEN SUM(total_spend) / SUM(total_clicks) 
    ELSE 0 
  END as avg_cpc,
  CASE WHEN SUM(total_impressions) > 0 
    THEN SUM(total_spend) / SUM(total_impressions) * 1000 
    ELSE 0 
  END as avg_cpm,
  CASE WHEN SUM(total_impressions) > 0 
    THEN SUM(total_clicks)::decimal / SUM(total_impressions) 
    ELSE 0 
  END as avg_ctr,
  CASE WHEN SUM(total_clicks) > 0 
    THEN SUM(total_conversions)::decimal / SUM(total_clicks) 
    ELSE 0 
  END as avg_cvr,
  CASE WHEN SUM(total_spend) > 0 
    THEN SUM(total_revenue) / SUM(total_spend) 
    ELSE 0 
  END as avg_roas,
  CASE WHEN SUM(new_customers_count) > 0 
    THEN SUM(total_spend) / SUM(new_customers_count) 
    ELSE 0 
  END as avg_cac
FROM acquisition_metrics_daily
GROUP BY platform;

-- View: Traffic Source Performance
CREATE OR REPLACE VIEW traffic_source_summary AS
SELECT 
  source,
  COALESCE(utm_source, 'unknown') as utm_source,
  COALESCE(utm_medium, 'unknown') as utm_medium,
  SUM(sessions_count) as total_sessions,
  SUM(page_views_count) as total_page_views,
  SUM(signups_count) as total_signups,
  SUM(orders_count) as total_orders,
  SUM(revenue) as total_revenue,
  AVG(bounce_rate) as avg_bounce_rate,
  AVG(signup_rate) as avg_signup_rate,
  AVG(conversion_rate) as avg_conversion_rate,
  CASE WHEN SUM(sessions_count) > 0 
    THEN SUM(signups_count)::decimal / SUM(sessions_count) 
    ELSE 0 
  END as session_to_signup_ratio
FROM traffic_source_metrics_daily
GROUP BY source, utm_source, utm_medium;

-- View: Source ROI (LTV:CAC) by Channel
CREATE OR REPLACE VIEW source_roi_summary AS
WITH platform_stats AS (
  SELECT 
    ae.platform,
    COUNT(DISTINCT ae.customer_id) FILTER (WHERE ae.customer_id IS NOT NULL) as customers_acquired,
    SUM(ae.spend) as total_spend,
    SUM(ae.spend) / NULLIF(COUNT(DISTINCT ae.customer_id) FILTER (WHERE ae.customer_id IS NOT NULL), 0) as cac
  FROM ad_events ae
  WHERE ae.event_type IN ('conversion', 'purchase')
    AND ae.customer_id IS NOT NULL
  GROUP BY ae.platform
),
platform_ltv AS (
  SELECT 
    ae.platform,
    AVG(c.total_revenue) as avg_ltv
  FROM ad_events ae
  JOIN customers c ON c.id = ae.customer_id
  WHERE ae.event_type IN ('conversion', 'purchase')
    AND ae.customer_id IS NOT NULL
  GROUP BY ae.platform
)
SELECT 
  ps.platform,
  ps.customers_acquired,
  ps.cac,
  pl.avg_ltv,
  CASE 
    WHEN ps.cac > 0 THEN pl.avg_ltv / ps.cac
    ELSE 0
  END as ltv_cac_ratio
FROM platform_stats ps
JOIN platform_ltv pl ON pl.platform = ps.platform;

-- ============================================================================
-- 5. FUNCTION TO POPULATE DAILY ACQUISITION METRICS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_acquisition_metrics_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
BEGIN
  -- Delete existing records for the target date
  DELETE FROM acquisition_metrics_daily WHERE date = target_date;

  -- Insert aggregated metrics from ad_events
  INSERT INTO acquisition_metrics_daily (
    platform, campaign_id, date,
    total_spend, total_impressions, total_clicks, total_conversions, total_revenue,
    cpc, cpm, ctr, cvr, roas,
    new_customers_count, email_signups_count, cost_per_customer, cost_per_signup,
    sessions_count, bounced_sessions_count, bounce_rate, session_to_signup_ratio
  )
  SELECT 
    ae.platform,
    ae.campaign_id,
    target_date,
    SUM(ae.spend) as total_spend,
    SUM(ae.impressions) as total_impressions,
    SUM(ae.clicks) as total_clicks,
    SUM(ae.conversions) as total_conversions,
    SUM(ae.revenue) as total_revenue,
    -- Calculated metrics
    CASE WHEN SUM(ae.clicks) > 0 
      THEN SUM(ae.spend) / SUM(ae.clicks) 
      ELSE NULL 
    END as cpc,
    CASE WHEN SUM(ae.impressions) > 0 
      THEN SUM(ae.spend) / SUM(ae.impressions) * 1000 
      ELSE NULL 
    END as cpm,
    CASE WHEN SUM(ae.impressions) > 0 
      THEN SUM(ae.clicks)::decimal / SUM(ae.impressions) 
      ELSE NULL 
    END as ctr,
    CASE WHEN SUM(ae.clicks) > 0 
      THEN SUM(ae.conversions)::decimal / SUM(ae.clicks) 
      ELSE NULL 
    END as cvr,
    CASE WHEN SUM(ae.spend) > 0 
      THEN SUM(ae.revenue) / SUM(ae.spend) 
      ELSE NULL 
    END as roas,
    -- Customer metrics
    COUNT(DISTINCT c.id) FILTER (WHERE c.is_first_time_customer = true) as new_customers_count,
    COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List') as email_signups_count,
    CASE WHEN COUNT(DISTINCT c.id) FILTER (WHERE c.is_first_time_customer = true) > 0 
      THEN SUM(ae.spend) / COUNT(DISTINCT c.id) FILTER (WHERE c.is_first_time_customer = true)
      ELSE NULL 
    END as cost_per_customer,
    CASE WHEN COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List') > 0 
      THEN SUM(ae.spend) / COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')
      ELSE NULL 
    END as cost_per_signup,
    -- Session metrics (from shopify_events)
    COUNT(DISTINCT se.session_id) as sessions_count,
    COUNT(DISTINCT se.session_id) FILTER (
      WHERE se.session_id IN (
        SELECT session_id 
        FROM shopify_events 
        WHERE event_type = 'page_viewed' 
          AND occurred_at::date = target_date
        GROUP BY session_id 
        HAVING COUNT(*) = 1
      )
    ) as bounced_sessions_count,
    -- Bounce rate calculation
    CASE 
      WHEN COUNT(DISTINCT se.session_id) > 0 
      THEN COUNT(DISTINCT se.session_id) FILTER (
        WHERE se.session_id IN (
          SELECT session_id 
          FROM shopify_events 
          WHERE event_type = 'page_viewed' 
            AND occurred_at::date = target_date
          GROUP BY session_id 
          HAVING COUNT(*) = 1
        )
      )::decimal / COUNT(DISTINCT se.session_id)
      ELSE NULL 
    END as bounce_rate,
    -- Session to signup ratio
    CASE 
      WHEN COUNT(DISTINCT se.session_id) > 0 
      THEN COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')::decimal / 
           COUNT(DISTINCT se.session_id)
      ELSE NULL 
    END as session_to_signup_ratio
  FROM ad_events ae
  LEFT JOIN customers c ON c.id = ae.customer_id
  LEFT JOIN klaviyo_events ke ON ke.customer_id = c.id 
    AND ke.occurred_at::date = target_date
  LEFT JOIN shopify_events se ON se.customer_id = c.id 
    AND se.occurred_at::date = target_date
  WHERE ae.date = target_date
  GROUP BY ae.platform, ae.campaign_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. FUNCTION TO POPULATE TRAFFIC SOURCE METRICS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_traffic_source_metrics_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
BEGIN
  -- Delete existing records for the target date
  DELETE FROM traffic_source_metrics_daily WHERE date = target_date;

  -- Insert from shopify_events (page views, sessions)
  INSERT INTO traffic_source_metrics_daily (
    source, utm_source, utm_medium, utm_campaign, date,
    sessions_count, page_views_count, unique_visitors_count,
    bounced_sessions_count, avg_session_duration_seconds,
    signups_count, orders_count, revenue,
    bounce_rate, signup_rate, conversion_rate
  )
  SELECT 
    COALESCE(so.source, se.event_properties->>'referrer', 'direct') as source,
    se.event_properties->>'utm_source' as utm_source,
    se.event_properties->>'utm_medium' as utm_medium,
    se.event_properties->>'utm_campaign' as utm_campaign,
    target_date,
    COUNT(DISTINCT se.session_id) as sessions_count,
    COUNT(*) FILTER (WHERE se.event_type = 'page_viewed') as page_views_count,
    COUNT(DISTINCT se.customer_id) as unique_visitors_count,
    -- Bounced sessions (single page view or < 30 seconds)
    COUNT(DISTINCT se.session_id) FILTER (
      WHERE se.session_id IN (
        SELECT session_id 
        FROM shopify_events 
        WHERE event_type = 'page_viewed' 
          AND occurred_at::date = target_date
        GROUP BY session_id 
        HAVING COUNT(*) = 1
      )
    ) as bounced_sessions_count,
    AVG(EXTRACT(EPOCH FROM (
      SELECT MAX(occurred_at) - MIN(occurred_at)
      FROM shopify_events se2
      WHERE se2.session_id = se.session_id
        AND se2.occurred_at::date = target_date
    )))::int as avg_session_duration_seconds,
    -- Signups from Klaviyo
    COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List') as signups_count,
    -- Orders
    COUNT(DISTINCT so.id) FILTER (WHERE so.financial_status = 'paid') as orders_count,
    COALESCE(SUM(so.total_price) FILTER (WHERE so.financial_status = 'paid'), 0) as revenue,
    -- Calculated metrics
    CASE 
      WHEN COUNT(DISTINCT se.session_id) > 0 
      THEN COUNT(DISTINCT se.session_id) FILTER (
        WHERE se.session_id IN (
          SELECT session_id FROM shopify_events 
          WHERE event_type = 'page_viewed' AND occurred_at::date = target_date
          GROUP BY session_id HAVING COUNT(*) = 1
        )
      )::decimal / COUNT(DISTINCT se.session_id)
      ELSE NULL 
    END as bounce_rate,
    CASE 
      WHEN COUNT(DISTINCT se.session_id) > 0 
      THEN COUNT(DISTINCT ke.id) FILTER (WHERE ke.event_type = 'Subscribed to List')::decimal / 
           COUNT(DISTINCT se.session_id)
      ELSE NULL 
    END as signup_rate,
    CASE 
      WHEN COUNT(DISTINCT se.session_id) > 0 
      THEN COUNT(DISTINCT so.id) FILTER (WHERE so.financial_status = 'paid')::decimal / 
           COUNT(DISTINCT se.session_id)
      ELSE NULL 
    END as conversion_rate
  FROM shopify_events se
  LEFT JOIN customers c ON c.id = se.customer_id
  LEFT JOIN klaviyo_events ke ON ke.customer_id = c.id 
    AND ke.occurred_at::date = target_date
  LEFT JOIN shopify_orders so ON so.customer_id = c.id 
    AND so.order_date::date = target_date
  WHERE se.occurred_at::date = target_date
  GROUP BY 
    COALESCE(so.source, se.event_properties->>'referrer', 'direct'),
    se.event_properties->>'utm_source',
    se.event_properties->>'utm_medium',
    se.event_properties->>'utm_campaign';
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. TRIGGERS FOR AUTO-UPDATE
-- ============================================================================

DROP TRIGGER IF EXISTS acquisition_metrics_daily_updated_at ON acquisition_metrics_daily;
CREATE TRIGGER acquisition_metrics_daily_updated_at 
  BEFORE UPDATE ON acquisition_metrics_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS traffic_source_metrics_daily_updated_at ON traffic_source_metrics_daily;
CREATE TRIGGER traffic_source_metrics_daily_updated_at 
  BEFORE UPDATE ON traffic_source_metrics_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 8. COMMENTS
-- ============================================================================

COMMENT ON TABLE acquisition_metrics_daily IS 'Daily aggregated acquisition metrics from advertising platforms';
COMMENT ON TABLE traffic_source_metrics_daily IS 'Daily traffic and conversion metrics by source/channel';
COMMENT ON VIEW acquisition_metrics_summary IS 'Aggregated acquisition metrics summary by platform';
COMMENT ON VIEW traffic_source_summary IS 'Traffic source performance summary';
COMMENT ON VIEW source_roi_summary IS 'Source ROI (LTV:CAC ratio) by advertising platform';

