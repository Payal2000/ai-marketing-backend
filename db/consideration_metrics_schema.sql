-- ============================================================================
-- CONSIDERATION METRICS IMPLEMENTATION
-- Pre-computed metrics for intent, engagement, and drop-offs
-- ============================================================================

-- ============================================================================
-- 1. CONSIDERATION METRICS DAILY AGGREGATION TABLE
-- ============================================================================

DROP TABLE IF EXISTS consideration_metrics_daily CASCADE;
CREATE TABLE consideration_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  -- Product Engagement
  total_product_views int DEFAULT 0,
  total_add_to_cart int DEFAULT 0,
  total_wishlist_adds int DEFAULT 0,
  total_checkout_starts int DEFAULT 0,
  total_checkout_completions int DEFAULT 0,
  -- Calculated Metrics (stored for performance)
  add_to_cart_rate decimal(5,4), -- Add-to-Cart Rate
  view_to_add_to_cart_ratio decimal(5,4), -- View-to-Add-to-Cart Ratio
  wishlist_add_rate decimal(5,4), -- Wishlist add rate
  cart_abandonment_rate decimal(5,4), -- Cart abandonment rate (pre-checkout)
  product_page_bounce_rate decimal(5,4), -- Product page bounce rate
  -- Session Metrics
  total_sessions int DEFAULT 0,
  total_page_views int DEFAULT 0,
  avg_pages_per_session decimal(5,2), -- Product View Depth
  avg_session_duration_seconds int DEFAULT 0, -- Time on site / session duration
  avg_scroll_depth_percent decimal(5,2), -- Scroll depth %
  sessions_with_repeat_visits_7d int DEFAULT 0, -- Sessions with repeat visits in 7 days
  repeat_visit_rate_7d decimal(5,4), -- % of sessions with repeat visits in 7 days
  -- Email Engagement (from Klaviyo)
  total_emails_sent int DEFAULT 0,
  total_emails_opened int DEFAULT 0,
  total_emails_clicked int DEFAULT 0,
  email_open_rate decimal(5,4), -- Email open rate
  email_ctr decimal(5,4), -- Email click-through rate
  -- Engagement Score (weighted)
  engagement_score decimal(10,4), -- Weighted engagement score
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(date)
);

CREATE INDEX IF NOT EXISTS consideration_metrics_daily_date_idx ON consideration_metrics_daily(date);

-- ============================================================================
-- 2. SESSION ENGAGEMENT METRICS TABLE
-- ============================================================================

DROP TABLE IF EXISTS session_engagement_daily CASCADE;
CREATE TABLE session_engagement_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  session_id text NOT NULL,
  customer_id uuid,
  -- Session Metrics
  page_views_count int DEFAULT 0,
  product_views_count int DEFAULT 0,
  add_to_cart_count int DEFAULT 0,
  wishlist_add_count int DEFAULT 0,
  checkout_started boolean DEFAULT false,
  checkout_completed boolean DEFAULT false,
  -- Engagement Metrics
  session_duration_seconds int DEFAULT 0,
  avg_scroll_depth_percent decimal(5,2),
  bounce boolean DEFAULT false,
  is_product_page_bounce boolean DEFAULT false,
  -- Repeat Visit Tracking
  has_repeat_visit_7d boolean DEFAULT false,
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS session_engagement_daily_date_idx ON session_engagement_daily(date);
CREATE INDEX IF NOT EXISTS session_engagement_daily_session_idx ON session_engagement_daily(session_id);
CREATE INDEX IF NOT EXISTS session_engagement_daily_customer_idx ON session_engagement_daily(customer_id) WHERE customer_id IS NOT NULL;

-- ============================================================================
-- 3. FUNCTIONS FOR CALCULATING METRICS
-- ============================================================================

-- Function: Calculate Add-to-Cart Rate
CREATE OR REPLACE FUNCTION calculate_add_to_cart_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT se.session_id) FILTER (WHERE se.event_type = 'add_to_cart')::decimal / 
      NULLIF(COUNT(DISTINCT se.session_id) FILTER (WHERE se.event_type = 'product_viewed'), 0),
      0
    )
  FROM shopify_events se
  WHERE se.occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate View-to-Add-to-Cart Ratio
CREATE OR REPLACE FUNCTION calculate_view_to_add_to_cart_ratio(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE se.event_type = 'add_to_cart')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE se.event_type = 'product_viewed'), 0),
      0
    )
  FROM shopify_events se
  WHERE se.occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Product View Depth (avg pages per session)
CREATE OR REPLACE FUNCTION calculate_product_view_depth(
  start_date date,
  end_date date
)
RETURNS decimal(5,2) AS $$
  SELECT 
    COALESCE(
      AVG(page_count)::decimal,
      0
    )
  FROM (
    SELECT 
      session_id,
      COUNT(*) as page_count
    FROM shopify_events
    WHERE event_type = 'page_viewed'
      AND occurred_at::date BETWEEN start_date AND end_date
      AND session_id IS NOT NULL
    GROUP BY session_id
  ) session_pages;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Average Session Duration
CREATE OR REPLACE FUNCTION calculate_avg_session_duration(
  start_date date,
  end_date date
)
RETURNS int AS $$
  SELECT 
    COALESCE(
      AVG(EXTRACT(EPOCH FROM (max_time - min_time)))::int,
      0
    )
  FROM (
    SELECT 
      session_id,
      MIN(occurred_at) as min_time,
      MAX(occurred_at) as max_time
    FROM shopify_events
    WHERE occurred_at::date BETWEEN start_date AND end_date
      AND session_id IS NOT NULL
    GROUP BY session_id
  ) session_durations;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Average Scroll Depth
CREATE OR REPLACE FUNCTION calculate_avg_scroll_depth(
  start_date date,
  end_date date
)
RETURNS decimal(5,2) AS $$
  SELECT 
    COALESCE(
      AVG((event_properties->>'scroll_depth')::decimal),
      0
    )
  FROM shopify_events
  WHERE event_type = 'page_viewed'
    AND event_properties->>'scroll_depth' IS NOT NULL
    AND occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Wishlist Add Rate
CREATE OR REPLACE FUNCTION calculate_wishlist_add_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT se.session_id) FILTER (WHERE se.event_type = 'add_to_wishlist')::decimal / 
      NULLIF(COUNT(DISTINCT se.session_id) FILTER (WHERE se.event_type IN ('product_viewed', 'page_viewed')), 0),
      0
    )
  FROM shopify_events se
  WHERE se.occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Cart Abandonment Rate (pre-checkout)
CREATE OR REPLACE FUNCTION calculate_cart_abandonment_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  WITH cart_stats AS (
    SELECT 
      COUNT(DISTINCT se1.session_id) FILTER (WHERE se1.event_type = 'add_to_cart') as carts_started,
      COUNT(DISTINCT se2.session_id) FILTER (WHERE se2.event_type = 'checkout_started') as checkouts_started
    FROM shopify_events se1
    LEFT JOIN shopify_events se2 ON se2.session_id = se1.session_id 
      AND se2.event_type = 'checkout_started'
      AND se2.occurred_at::date BETWEEN start_date AND end_date
    WHERE se1.event_type = 'add_to_cart'
      AND se1.occurred_at::date BETWEEN start_date AND end_date
  )
  SELECT 
    COALESCE(
      (carts_started - checkouts_started)::decimal / NULLIF(carts_started, 0),
      0
    )
  FROM cart_stats;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Product Page Bounce Rate
CREATE OR REPLACE FUNCTION calculate_product_page_bounce_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  WITH product_sessions AS (
    SELECT 
      session_id,
      COUNT(*) as page_views,
      MIN(occurred_at) as first_view,
      MAX(occurred_at) as last_view
    FROM shopify_events
    WHERE event_type = 'product_viewed'
      AND occurred_at::date BETWEEN start_date AND end_date
      AND session_id IS NOT NULL
    GROUP BY session_id
  )
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE page_views = 1 OR EXTRACT(EPOCH FROM (last_view - first_view)) < 30)::decimal / 
      NULLIF(COUNT(*), 0),
      0
    )
  FROM product_sessions;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Email Open Rate (from Klaviyo)
CREATE OR REPLACE FUNCTION calculate_email_open_rate(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE event_type = 'Opened Email')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE event_type = 'Sent Email'), 0),
      0
    )
  FROM klaviyo_events
  WHERE occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Email Click-Through Rate (from Klaviyo)
CREATE OR REPLACE FUNCTION calculate_email_ctr(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE event_type = 'Clicked Email')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE event_type = 'Opened Email'), 0),
      0
    )
  FROM klaviyo_events
  WHERE occurred_at::date BETWEEN start_date AND end_date;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Repeat Visit Rate (7 days)
CREATE OR REPLACE FUNCTION calculate_repeat_visit_rate_7d(
  start_date date,
  end_date date
)
RETURNS decimal(5,4) AS $$
  WITH session_first_visit AS (
    SELECT 
      session_id,
      customer_id,
      MIN(occurred_at)::date as first_visit_date
    FROM shopify_events
    WHERE occurred_at::date BETWEEN start_date AND end_date
      AND customer_id IS NOT NULL
      AND session_id IS NOT NULL
    GROUP BY session_id, customer_id
  ),
  repeat_visits AS (
    SELECT DISTINCT s1.session_id
    FROM session_first_visit s1
    WHERE EXISTS (
      SELECT 1 
      FROM shopify_events se2 
      WHERE se2.customer_id = s1.customer_id
        AND se2.session_id != s1.session_id
        AND se2.occurred_at::date BETWEEN s1.first_visit_date AND s1.first_visit_date + INTERVAL '7 days'
    )
  )
  SELECT 
    COALESCE(
      (SELECT COUNT(*) FROM repeat_visits)::decimal / 
      NULLIF((SELECT COUNT(*) FROM session_first_visit), 0),
      0
    );
$$ LANGUAGE sql STABLE;

-- Function: Calculate Engagement Score (weighted)
CREATE OR REPLACE FUNCTION calculate_engagement_score(
  start_date date,
  end_date date
)
RETURNS decimal(10,4) AS $$
  WITH site_metrics AS (
    SELECT 
      COUNT(DISTINCT session_id) FILTER (WHERE event_type IN ('product_viewed', 'add_to_cart')) as engaged_sessions,
      AVG(EXTRACT(EPOCH FROM (max_time - min_time))) as avg_duration
    FROM (
      SELECT 
        session_id,
        event_type,
        MIN(occurred_at) as min_time,
        MAX(occurred_at) as max_time
      FROM shopify_events
      WHERE occurred_at::date BETWEEN start_date AND end_date
        AND session_id IS NOT NULL
      GROUP BY session_id, event_type
    ) session_stats
  ),
  email_metrics AS (
    SELECT 
      COUNT(*) FILTER (WHERE event_type = 'Sent Email') as emails_sent,
      COUNT(*) FILTER (WHERE event_type = 'Opened Email') as emails_opened,
      COUNT(*) FILTER (WHERE event_type = 'Clicked Email') as emails_clicked
    FROM klaviyo_events
    WHERE occurred_at::date BETWEEN start_date AND end_date
  ),
  cart_events AS (
    SELECT COUNT(*) as add_to_carts
    FROM shopify_events
    WHERE occurred_at::date BETWEEN start_date AND end_date
      AND event_type = 'add_to_cart'
  )
  SELECT 
    COALESCE(
      ((sm.engaged_sessions * 0.3 + COALESCE(sm.avg_duration, 0) * 0.2 + COALESCE(ce.add_to_carts, 0) * 0.2) * 0.7 +
       (COALESCE(em.emails_opened::decimal / NULLIF(em.emails_sent, 0), 0) * 0.2 +
        COALESCE(em.emails_clicked::decimal / NULLIF(em.emails_opened, 0), 0) * 0.1) * 0.3),
      0
    )
  FROM site_metrics sm, email_metrics em, cart_events ce;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 4. MATERIALIZED VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Consideration Metrics Summary (All Time)
CREATE OR REPLACE VIEW consideration_metrics_summary AS
SELECT 
  SUM(total_product_views) as total_product_views,
  SUM(total_add_to_cart) as total_add_to_cart,
  SUM(total_wishlist_adds) as total_wishlist_adds,
  SUM(total_checkout_starts) as total_checkout_starts,
  SUM(total_checkout_completions) as total_checkout_completions,
  -- Aggregated rates
  AVG(add_to_cart_rate) as avg_add_to_cart_rate,
  AVG(view_to_add_to_cart_ratio) as avg_view_to_add_to_cart_ratio,
  AVG(wishlist_add_rate) as avg_wishlist_add_rate,
  AVG(cart_abandonment_rate) as avg_cart_abandonment_rate,
  AVG(product_page_bounce_rate) as avg_product_page_bounce_rate,
  -- Session metrics
  SUM(total_sessions) as total_sessions,
  SUM(total_page_views) as total_page_views,
  AVG(avg_pages_per_session) as avg_pages_per_session,
  AVG(avg_session_duration_seconds) as avg_session_duration_seconds,
  AVG(avg_scroll_depth_percent) as avg_scroll_depth_percent,
  AVG(repeat_visit_rate_7d) as avg_repeat_visit_rate_7d,
  -- Email metrics
  SUM(total_emails_sent) as total_emails_sent,
  SUM(total_emails_opened) as total_emails_opened,
  SUM(total_emails_clicked) as total_emails_clicked,
  AVG(email_open_rate) as avg_email_open_rate,
  AVG(email_ctr) as avg_email_ctr,
  -- Engagement score
  AVG(engagement_score) as avg_engagement_score
FROM consideration_metrics_daily;

-- View: Daily Consideration Trends
CREATE OR REPLACE VIEW consideration_metrics_trends AS
SELECT 
  date,
  total_product_views,
  total_add_to_cart,
  add_to_cart_rate * 100 as add_to_cart_rate_pct,
  view_to_add_to_cart_ratio * 100 as view_to_add_to_cart_ratio_pct,
  avg_pages_per_session,
  avg_session_duration_seconds,
  cart_abandonment_rate * 100 as cart_abandonment_rate_pct,
  product_page_bounce_rate * 100 as product_page_bounce_rate_pct,
  email_open_rate * 100 as email_open_rate_pct,
  email_ctr * 100 as email_ctr_pct,
  engagement_score
FROM consideration_metrics_daily
ORDER BY date DESC;

-- ============================================================================
-- 5. FUNCTION TO POPULATE DAILY CONSIDERATION METRICS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_consideration_metrics_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
DECLARE
  v_total_product_views int;
  v_total_add_to_cart int;
  v_total_wishlist_adds int;
  v_total_checkout_starts int;
  v_total_checkout_completions int;
  v_total_sessions int;
  v_total_page_views int;
  v_total_emails_sent int;
  v_total_emails_opened int;
  v_total_emails_clicked int;
  v_add_to_cart_sessions int;
  v_product_view_sessions int;
  v_wishlist_sessions int;
BEGIN
  -- Delete existing records for the target date
  DELETE FROM consideration_metrics_daily WHERE date = target_date;

  -- Get Shopify event counts
  SELECT 
    COUNT(*) FILTER (WHERE event_type = 'product_viewed'),
    COUNT(*) FILTER (WHERE event_type = 'add_to_cart'),
    COUNT(*) FILTER (WHERE event_type = 'add_to_wishlist'),
    COUNT(*) FILTER (WHERE event_type = 'checkout_started'),
    COUNT(*) FILTER (WHERE event_type = 'checkout_completed'),
    COUNT(DISTINCT session_id),
    COUNT(*) FILTER (WHERE event_type = 'page_viewed')
  INTO 
    v_total_product_views,
    v_total_add_to_cart,
    v_total_wishlist_adds,
    v_total_checkout_starts,
    v_total_checkout_completions,
    v_total_sessions,
    v_total_page_views
  FROM shopify_events
  WHERE occurred_at::date = target_date;

  -- Get Klaviyo email counts
  SELECT 
    COUNT(*) FILTER (WHERE event_type = 'Sent Email'),
    COUNT(*) FILTER (WHERE event_type = 'Opened Email'),
    COUNT(*) FILTER (WHERE event_type = 'Clicked Email')
  INTO 
    v_total_emails_sent,
    v_total_emails_opened,
    v_total_emails_clicked
  FROM klaviyo_events
  WHERE occurred_at::date = target_date;

  -- Get session-level counts
  SELECT COUNT(DISTINCT session_id) INTO v_add_to_cart_sessions
  FROM shopify_events WHERE occurred_at::date = target_date AND event_type = 'add_to_cart';
  
  SELECT COUNT(DISTINCT session_id) INTO v_product_view_sessions
  FROM shopify_events WHERE occurred_at::date = target_date AND event_type = 'product_viewed';
  
  SELECT COUNT(DISTINCT session_id) INTO v_wishlist_sessions
  FROM shopify_events WHERE occurred_at::date = target_date AND event_type = 'add_to_wishlist';

  -- Insert aggregated metrics
  INSERT INTO consideration_metrics_daily (
    date,
    total_product_views,
    total_add_to_cart,
    total_wishlist_adds,
    total_checkout_starts,
    total_checkout_completions,
    add_to_cart_rate,
    view_to_add_to_cart_ratio,
    wishlist_add_rate,
    cart_abandonment_rate,
    product_page_bounce_rate,
    total_sessions,
    total_page_views,
    avg_pages_per_session,
    avg_session_duration_seconds,
    avg_scroll_depth_percent,
    sessions_with_repeat_visits_7d,
    repeat_visit_rate_7d,
    total_emails_sent,
    total_emails_opened,
    total_emails_clicked,
    email_open_rate,
    email_ctr,
    engagement_score
  )
  SELECT 
    target_date,
    COALESCE(v_total_product_views, 0),
    COALESCE(v_total_add_to_cart, 0),
    COALESCE(v_total_wishlist_adds, 0),
    COALESCE(v_total_checkout_starts, 0),
    COALESCE(v_total_checkout_completions, 0),
    -- Calculated rates using variables
    CASE 
      WHEN v_product_view_sessions > 0
      THEN v_add_to_cart_sessions::decimal / v_product_view_sessions
      ELSE NULL
    END as add_to_cart_rate,
    CASE 
      WHEN v_total_product_views > 0
      THEN v_total_add_to_cart::decimal / v_total_product_views
      ELSE NULL
    END as view_to_add_to_cart_ratio,
    CASE 
      WHEN v_total_sessions > 0
      THEN v_wishlist_sessions::decimal / v_total_sessions
      ELSE NULL
    END as wishlist_add_rate,
    -- Cart abandonment rate
    CASE 
      WHEN v_total_add_to_cart > 0
      THEN (v_total_add_to_cart - v_total_checkout_starts)::decimal / v_total_add_to_cart
      ELSE NULL
    END as cart_abandonment_rate,
    -- Product page bounce rate
    (
      SELECT 
        CASE 
          WHEN COUNT(*) > 0
          THEN COUNT(*) FILTER (
            WHERE page_views = 1 OR duration_seconds < 30
          )::decimal / COUNT(*)
          ELSE NULL
        END
      FROM (
        SELECT 
          session_id,
          COUNT(*) as page_views,
          EXTRACT(EPOCH FROM (MAX(occurred_at) - MIN(occurred_at)))::int as duration_seconds
        FROM shopify_events
        WHERE event_type = 'product_viewed'
          AND occurred_at::date = target_date
          AND session_id IS NOT NULL
        GROUP BY session_id
      ) product_sessions
    ) as product_page_bounce_rate,
    -- Session metrics
    COALESCE(v_total_sessions, 0),
    COALESCE(v_total_page_views, 0),
    -- Avg pages per session
    (
      SELECT AVG(page_count)::decimal
      FROM (
        SELECT session_id, COUNT(*) as page_count
        FROM shopify_events
        WHERE event_type = 'page_viewed'
          AND occurred_at::date = target_date
          AND session_id IS NOT NULL
        GROUP BY session_id
      ) session_pages
    ) as avg_pages_per_session,
    -- Avg session duration
    (
      SELECT AVG(EXTRACT(EPOCH FROM (max_time - min_time)))::int
      FROM (
        SELECT 
          session_id,
          MIN(occurred_at) as min_time,
          MAX(occurred_at) as max_time
        FROM shopify_events
        WHERE occurred_at::date = target_date
          AND session_id IS NOT NULL
        GROUP BY session_id
      ) session_durations
    ) as avg_session_duration_seconds,
    -- Avg scroll depth
    (
      SELECT AVG((event_properties->>'scroll_depth')::decimal)
      FROM shopify_events
      WHERE event_type = 'page_viewed'
        AND event_properties->>'scroll_depth' IS NOT NULL
        AND occurred_at::date = target_date
    ) as avg_scroll_depth_percent,
    -- Repeat visits 7d
    (
      SELECT COUNT(DISTINCT s1.session_id)
      FROM shopify_events s1
      WHERE s1.occurred_at::date = target_date
        AND s1.customer_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM shopify_events s2
          WHERE s2.customer_id = s1.customer_id
            AND s2.session_id != s1.session_id
            AND s2.occurred_at::date BETWEEN s1.occurred_at::date AND s1.occurred_at::date + INTERVAL '7 days'
        )
    ) as sessions_with_repeat_visits_7d,
    -- Repeat visit rate (calculated separately)
    (
      SELECT 
        CASE 
          WHEN COUNT(DISTINCT s1.session_id) > 0
          THEN COUNT(DISTINCT s1.session_id)::decimal / NULLIF(
            (SELECT COUNT(DISTINCT session_id) FROM shopify_events WHERE occurred_at::date = target_date AND customer_id IS NOT NULL),
            0
          )
          ELSE NULL
        END
      FROM shopify_events s1
      WHERE s1.occurred_at::date = target_date
        AND s1.customer_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM shopify_events s2
          WHERE s2.customer_id = s1.customer_id
            AND s2.session_id != s1.session_id
            AND s2.occurred_at::date BETWEEN s1.occurred_at::date AND s1.occurred_at::date + INTERVAL '7 days'
        )
    ) as repeat_visit_rate_7d,
    -- Email metrics from Klaviyo
    COALESCE(v_total_emails_sent, 0),
    COALESCE(v_total_emails_opened, 0),
    COALESCE(v_total_emails_clicked, 0),
    -- Email open rate
    CASE 
      WHEN v_total_emails_sent > 0
      THEN v_total_emails_opened::decimal / v_total_emails_sent
      ELSE NULL
    END as email_open_rate,
    -- Email CTR
    CASE 
      WHEN v_total_emails_opened > 0
      THEN v_total_emails_clicked::decimal / v_total_emails_opened
      ELSE NULL
    END as email_ctr,
    -- Engagement score (simplified calculation)
    (
      (COALESCE((SELECT COUNT(DISTINCT session_id) FROM shopify_events WHERE occurred_at::date = target_date AND event_type IN ('product_viewed', 'add_to_cart')), 0) * 0.3 +
       COALESCE((SELECT AVG(EXTRACT(EPOCH FROM (max_time - min_time))) FROM (
         SELECT session_id, MIN(occurred_at) as min_time, MAX(occurred_at) as max_time
         FROM shopify_events WHERE occurred_at::date = target_date AND session_id IS NOT NULL GROUP BY session_id
       ) session_durations), 0) * 0.2 +
       COALESCE(v_total_add_to_cart, 0) * 0.2) * 0.7 +
      (COALESCE(v_total_emails_opened, 0)::decimal / NULLIF(v_total_emails_sent, 0) * 0.2 +
       COALESCE(v_total_emails_clicked, 0)::decimal / NULLIF(v_total_emails_opened, 0) * 0.1) * 0.3
    ) as engagement_score
  FROM (SELECT 1) dummy;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. FUNCTION TO POPULATE SESSION ENGAGEMENT DAILY
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_session_engagement_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
BEGIN
  -- Delete existing records for the target date
  DELETE FROM session_engagement_daily WHERE date = target_date;

  -- Insert session-level metrics
  INSERT INTO session_engagement_daily (
    date,
    session_id,
    customer_id,
    page_views_count,
    product_views_count,
    add_to_cart_count,
    wishlist_add_count,
    checkout_started,
    checkout_completed,
    session_duration_seconds,
    avg_scroll_depth_percent,
    bounce,
    is_product_page_bounce,
    has_repeat_visit_7d
  )
  SELECT 
    target_date,
    se.session_id,
    se.customer_id,
    COUNT(*) FILTER (WHERE se.event_type = 'page_viewed') as page_views_count,
    COUNT(*) FILTER (WHERE se.event_type = 'product_viewed') as product_views_count,
    COUNT(*) FILTER (WHERE se.event_type = 'add_to_cart') as add_to_cart_count,
    COUNT(*) FILTER (WHERE se.event_type = 'add_to_wishlist') as wishlist_add_count,
    COUNT(*) FILTER (WHERE se.event_type = 'checkout_started') > 0 as checkout_started,
    COUNT(*) FILTER (WHERE se.event_type = 'checkout_completed') > 0 as checkout_completed,
    -- Session duration
    EXTRACT(EPOCH FROM (MAX(se.occurred_at) - MIN(se.occurred_at)))::int as session_duration_seconds,
    -- Average scroll depth
    AVG((se.event_properties->>'scroll_depth')::decimal) as avg_scroll_depth_percent,
    -- Bounce (single page view or < 30 seconds)
    CASE 
      WHEN COUNT(*) FILTER (WHERE se.event_type = 'page_viewed') = 1 
         OR EXTRACT(EPOCH FROM (MAX(se.occurred_at) - MIN(se.occurred_at))) < 30 
      THEN true 
      ELSE false 
    END as bounce,
    -- Product page bounce (only product_viewed and session < 30 seconds)
    CASE 
      WHEN COUNT(*) FILTER (WHERE se.event_type = 'product_viewed') > 0
        AND COUNT(*) FILTER (WHERE se.event_type = 'page_viewed') = 1
        AND EXTRACT(EPOCH FROM (MAX(se.occurred_at) - MIN(se.occurred_at))) < 30
      THEN true
      ELSE false
    END as is_product_page_bounce,
    -- Repeat visit in 7 days
    CASE 
      WHEN se.customer_id IS NOT NULL AND EXISTS (
        SELECT 1 
        FROM shopify_events se2 
        WHERE se2.customer_id = se.customer_id
          AND se2.session_id != se.session_id
          AND se2.occurred_at::date BETWEEN target_date AND target_date + INTERVAL '7 days'
      ) THEN true
      ELSE false
    END as has_repeat_visit_7d
  FROM shopify_events se
  WHERE se.occurred_at::date = target_date
    AND se.session_id IS NOT NULL
  GROUP BY se.session_id, se.customer_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 7. TRIGGERS FOR AUTO-UPDATE
-- ============================================================================

DROP TRIGGER IF EXISTS consideration_metrics_daily_updated_at ON consideration_metrics_daily;
CREATE TRIGGER consideration_metrics_daily_updated_at 
  BEFORE UPDATE ON consideration_metrics_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS session_engagement_daily_updated_at ON session_engagement_daily;
CREATE TRIGGER session_engagement_daily_updated_at 
  BEFORE UPDATE ON session_engagement_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 7. COMMENTS
-- ============================================================================

COMMENT ON TABLE consideration_metrics_daily IS 'Daily aggregated consideration metrics (intent, engagement, drop-offs)';
COMMENT ON TABLE session_engagement_daily IS 'Daily session-level engagement metrics';
COMMENT ON FUNCTION refresh_session_engagement_daily IS 'Populates session_engagement_daily with session-level metrics for a specific date';
COMMENT ON VIEW consideration_metrics_summary IS 'Aggregated consideration metrics summary (all time)';
COMMENT ON VIEW consideration_metrics_trends IS 'Daily consideration metrics trends';

