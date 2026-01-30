-- ============================================================================
-- ADVOCACY / LOYALTY METRICS IMPLEMENTATION
-- Pre-computed metrics for brand promoters and referral opportunities
-- Aligned with existing customers, shopify_orders, and klaviyo data
-- ============================================================================

-- ============================================================================
-- 1. SUPPORTING TABLES FOR ADVOCACY METRICS
-- ============================================================================

-- Referrals table (tracks referral program)
DROP TABLE IF EXISTS referrals CASCADE;
CREATE TABLE referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  referred_customer_id uuid REFERENCES customers(id) ON DELETE SET NULL,
  referral_code text,
  referral_status text DEFAULT 'pending', -- 'pending' | 'completed' | 'converted'
  referred_email text,
  conversion_date date,
  reward_granted boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS referrals_referrer_idx ON referrals(referrer_customer_id);
CREATE INDEX IF NOT EXISTS referrals_referred_idx ON referrals(referred_customer_id) WHERE referred_customer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS referrals_status_idx ON referrals(referral_status);

-- Reviews table (customer reviews/ratings)
DROP TABLE IF EXISTS reviews CASCADE;
CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  order_id uuid REFERENCES shopify_orders(id) ON DELETE SET NULL,
  product_id uuid REFERENCES shopify_products(id) ON DELETE SET NULL,
  rating int CHECK (rating >= 1 AND rating <= 5),
  review_text text,
  is_verified_purchase boolean DEFAULT false,
  helpful_count int DEFAULT 0,
  status text DEFAULT 'published', -- 'pending' | 'published' | 'rejected'
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS reviews_customer_idx ON reviews(customer_id);
CREATE INDEX IF NOT EXISTS reviews_product_idx ON reviews(product_id) WHERE product_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS reviews_rating_idx ON reviews(rating);

-- UGC Submissions table (User-Generated Content)
DROP TABLE IF EXISTS ugc_submissions CASCADE;
CREATE TABLE ugc_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  submission_type text NOT NULL, -- 'photo' | 'video' | 'testimonial' | 'social_post'
  content_url text,
  platform text, -- 'instagram' | 'facebook' | 'tiktok' | 'website' | 'email'
  campaign_id text,
  status text DEFAULT 'pending', -- 'pending' | 'approved' | 'rejected' | 'featured'
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ugc_submissions_customer_idx ON ugc_submissions(customer_id);
CREATE INDEX IF NOT EXISTS ugc_submissions_type_idx ON ugc_submissions(submission_type);
CREATE INDEX IF NOT EXISTS ugc_submissions_status_idx ON ugc_submissions(status);

-- Loyalty Program Enrollments
DROP TABLE IF EXISTS loyalty_enrollments CASCADE;
CREATE TABLE loyalty_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  loyalty_tier text DEFAULT 'member', -- 'member' | 'silver' | 'gold' | 'platinum' | 'vip'
  points_balance int DEFAULT 0,
  total_points_earned int DEFAULT 0,
  enrollment_date date NOT NULL,
  last_activity_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id)
);

CREATE INDEX IF NOT EXISTS loyalty_enrollments_customer_idx ON loyalty_enrollments(customer_id);
CREATE INDEX IF NOT EXISTS loyalty_enrollments_tier_idx ON loyalty_enrollments(loyalty_tier);

-- NPS Surveys (Net Promoter Score)
DROP TABLE IF EXISTS nps_surveys CASCADE;
CREATE TABLE nps_surveys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  order_id uuid REFERENCES shopify_orders(id) ON DELETE SET NULL,
  nps_score int CHECK (nps_score >= 0 AND nps_score <= 10),
  feedback_text text,
  survey_type text DEFAULT 'post_purchase', -- 'post_purchase' | 'periodic' | 'transactional'
  survey_date date NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nps_surveys_customer_idx ON nps_surveys(customer_id);
CREATE INDEX IF NOT EXISTS nps_surveys_score_idx ON nps_surveys(nps_score);
CREATE INDEX IF NOT EXISTS nps_surveys_date_idx ON nps_surveys(survey_date);

-- ============================================================================
-- 2. ADVOCACY METRICS DAILY AGGREGATION TABLE
-- ============================================================================

DROP TABLE IF EXISTS advocacy_metrics_daily CASCADE;
CREATE TABLE advocacy_metrics_daily (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  date date NOT NULL,
  -- NPS Metrics
  total_nps_responses int DEFAULT 0,
  promoters_count int DEFAULT 0, -- Score 9-10
  passives_count int DEFAULT 0, -- Score 7-8
  detractors_count int DEFAULT 0, -- Score 0-6
  net_promoter_score decimal(5,2), -- Calculated: % Promoters - % Detractors
  -- Referral Metrics
  total_referrals int DEFAULT 0,
  referral_conversions int DEFAULT 0,
  referral_conversion_rate decimal(5,4), -- Referral Conversion Rate
  -- UGC Metrics
  total_ugc_submissions int DEFAULT 0,
  ugc_approved int DEFAULT 0,
  ugc_submission_rate decimal(5,4), -- UGC submission rate
  -- Review Metrics
  total_reviews int DEFAULT 0,
  review_participation_rate decimal(5,4), -- Review participation rate
  avg_review_rating decimal(3,2),
  -- Loyalty Metrics
  loyalty_program_members int DEFAULT 0,
  loyalty_program_participation_rate decimal(5,4), -- Loyalty program participation rate
  vip_customers_count int DEFAULT 0,
  vip_segment_revenue decimal(12,2) DEFAULT 0,
  vip_revenue_contribution decimal(5,4), -- VIP segment revenue contribution (%)
  -- Post-Purchase Email Metrics
  post_purchase_emails_sent int DEFAULT 0,
  post_purchase_emails_opened int DEFAULT 0,
  post_purchase_emails_clicked int DEFAULT 0,
  post_purchase_email_open_rate decimal(5,4), -- Post-purchase email open rate
  post_purchase_email_ctr decimal(5,4), -- Post-purchase email click-through rate
  -- Social Engagement (if integrated)
  social_engagements int DEFAULT 0,
  social_engagement_rate decimal(5,4), -- Social engagement rate
  -- Created/Updated
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(date)
);

CREATE INDEX IF NOT EXISTS advocacy_metrics_daily_date_idx ON advocacy_metrics_daily(date);

-- ============================================================================
-- 3. FUNCTIONS FOR CALCULATING METRICS
-- ============================================================================

-- Function: Calculate Net Promoter Score (NPS)
CREATE OR REPLACE FUNCTION calculate_nps(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,2) AS $$
  WITH nps_data AS (
    SELECT 
      COUNT(*) FILTER (WHERE nps_score >= 9) as promoters,
      COUNT(*) FILTER (WHERE nps_score >= 7 AND nps_score <= 8) as passives,
      COUNT(*) FILTER (WHERE nps_score <= 6) as detractors,
      COUNT(*) as total
    FROM nps_surveys
    WHERE (start_date IS NULL OR survey_date >= start_date)
      AND (end_date IS NULL OR survey_date <= end_date)
      AND nps_score IS NOT NULL
  )
  SELECT 
    COALESCE(
      ((promoters::decimal / NULLIF(total, 0) * 100) - 
       (detractors::decimal / NULLIF(total, 0) * 100)),
      0
    )
  FROM nps_data;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Referral Conversion Rate
CREATE OR REPLACE FUNCTION calculate_referral_conversion_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE referral_status = 'converted')::decimal / 
      NULLIF(COUNT(*), 0),
      0
    )
  FROM referrals
  WHERE (start_date IS NULL OR created_at::date >= start_date)
    AND (end_date IS NULL OR created_at::date <= end_date);
$$ LANGUAGE sql STABLE;

-- Function: Calculate UGC Submission Rate
CREATE OR REPLACE FUNCTION calculate_ugc_submission_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT ugc.customer_id)::decimal / 
      NULLIF(COUNT(DISTINCT c.id) FILTER (WHERE c.total_orders > 0), 0),
      0
    )
  FROM customers c
  LEFT JOIN ugc_submissions ugc ON ugc.customer_id = c.id
    AND (start_date IS NULL OR ugc.created_at::date >= start_date)
    AND (end_date IS NULL OR ugc.created_at::date <= end_date)
  WHERE c.total_orders > 0;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Review Participation Rate
CREATE OR REPLACE FUNCTION calculate_review_participation_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT r.customer_id)::decimal / 
      NULLIF(COUNT(DISTINCT c.id) FILTER (WHERE c.total_orders > 0), 0),
      0
    )
  FROM customers c
  LEFT JOIN reviews r ON r.customer_id = c.id
    AND (start_date IS NULL OR r.created_at::date >= start_date)
    AND (end_date IS NULL OR r.created_at::date <= end_date)
  WHERE c.total_orders > 0;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Loyalty Program Participation Rate
CREATE OR REPLACE FUNCTION calculate_loyalty_participation_rate()
RETURNS decimal(5,4) AS $$
  SELECT 
    COALESCE(
      COUNT(DISTINCT le.customer_id)::decimal / 
      NULLIF(COUNT(DISTINCT c.id) FILTER (WHERE c.total_orders > 0), 0),
      0
    )
  FROM customers c
  LEFT JOIN loyalty_enrollments le ON le.customer_id = c.id
  WHERE c.total_orders > 0;
$$ LANGUAGE sql STABLE;

-- Function: Calculate VIP Segment Revenue Contribution
CREATE OR REPLACE FUNCTION calculate_vip_revenue_contribution(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  WITH total_revenue AS (
    SELECT SUM(total_price) as total
    FROM shopify_orders
    WHERE financial_status = 'paid'
      AND (start_date IS NULL OR order_date::date >= start_date)
      AND (end_date IS NULL OR order_date::date <= end_date)
  ),
  vip_revenue AS (
    SELECT SUM(so.total_price) as vip_total
    FROM shopify_orders so
    JOIN customers c ON c.id = so.customer_id
    WHERE so.financial_status = 'paid'
      AND (c.tags @> ARRAY['VIP'] OR c.tags @> ARRAY['vip'] OR 
           EXISTS (SELECT 1 FROM loyalty_enrollments le WHERE le.customer_id = c.id AND le.loyalty_tier = 'vip'))
      AND (start_date IS NULL OR so.order_date::date >= start_date)
      AND (end_date IS NULL OR so.order_date::date <= end_date)
  )
  SELECT 
    COALESCE(
      vip_total::decimal / NULLIF(total, 0),
      0
    )
  FROM total_revenue, vip_revenue;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Post-Purchase Email Open Rate
CREATE OR REPLACE FUNCTION calculate_post_purchase_email_open_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  WITH post_purchase_emails AS (
    SELECT DISTINCT
      ke.id,
      ke.event_type,
      so.order_date::date as purchase_date
    FROM klaviyo_events ke
    JOIN klaviyo_profiles kp ON kp.id = ke.profile_id
    JOIN customers c ON c.id = kp.customer_id
    JOIN shopify_orders so ON so.customer_id = c.id
      AND so.order_date < ke.occurred_at
      AND so.order_date >= ke.occurred_at - INTERVAL '7 days'
    WHERE ke.event_type IN ('Sent Email', 'Opened Email', 'Clicked Email')
      AND (start_date IS NULL OR ke.occurred_at::date >= start_date)
      AND (end_date IS NULL OR ke.occurred_at::date <= end_date)
      AND so.financial_status = 'paid'
  )
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE event_type = 'Opened Email')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE event_type = 'Sent Email'), 0),
      0
    )
  FROM post_purchase_emails;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Post-Purchase Email CTR
CREATE OR REPLACE FUNCTION calculate_post_purchase_email_ctr(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  WITH post_purchase_emails AS (
    SELECT DISTINCT
      ke.id,
      ke.event_type,
      so.order_date::date as purchase_date
    FROM klaviyo_events ke
    JOIN klaviyo_profiles kp ON kp.id = ke.profile_id
    JOIN customers c ON c.id = kp.customer_id
    JOIN shopify_orders so ON so.customer_id = c.id
      AND so.order_date < ke.occurred_at
      AND so.order_date >= ke.occurred_at - INTERVAL '7 days'
    WHERE ke.event_type IN ('Opened Email', 'Clicked Email')
      AND (start_date IS NULL OR ke.occurred_at::date >= start_date)
      AND (end_date IS NULL OR ke.occurred_at::date <= end_date)
      AND so.financial_status = 'paid'
  )
  SELECT 
    COALESCE(
      COUNT(*) FILTER (WHERE event_type = 'Clicked Email')::decimal / 
      NULLIF(COUNT(*) FILTER (WHERE event_type = 'Opened Email'), 0),
      0
    )
  FROM post_purchase_emails;
$$ LANGUAGE sql STABLE;

-- Function: Calculate Social Engagement Rate
CREATE OR REPLACE FUNCTION calculate_social_engagement_rate(
  start_date date DEFAULT NULL,
  end_date date DEFAULT NULL
)
RETURNS decimal(5,4) AS $$
  -- For MVP: Use UGC submissions as proxy for social engagement
  -- In production, this would integrate with social media APIs
  SELECT 
    COALESCE(
      COUNT(DISTINCT ugc.customer_id)::decimal / 
      NULLIF(COUNT(DISTINCT c.id) FILTER (WHERE c.total_orders > 0), 0),
      0
    )
  FROM customers c
  LEFT JOIN ugc_submissions ugc ON ugc.customer_id = c.id
    AND ugc.platform IN ('instagram', 'facebook', 'tiktok', 'twitter')
    AND (start_date IS NULL OR ugc.created_at::date >= start_date)
    AND (end_date IS NULL OR ugc.created_at::date <= end_date)
  WHERE c.total_orders > 0;
$$ LANGUAGE sql STABLE;

-- ============================================================================
-- 4. MATERIALIZED VIEWS FOR COMMON QUERIES
-- ============================================================================

-- View: Advocacy Metrics Summary (All Time)
CREATE OR REPLACE VIEW advocacy_metrics_summary AS
SELECT 
  SUM(total_nps_responses) as total_nps_responses,
  AVG(net_promoter_score) as avg_nps,
  SUM(total_referrals) as total_referrals,
  AVG(referral_conversion_rate) as avg_referral_conversion_rate,
  SUM(total_ugc_submissions) as total_ugc_submissions,
  AVG(ugc_submission_rate) as avg_ugc_submission_rate,
  SUM(total_reviews) as total_reviews,
  AVG(review_participation_rate) as avg_review_participation_rate,
  AVG(avg_review_rating) as avg_review_rating,
  AVG(loyalty_program_participation_rate) as avg_loyalty_participation_rate,
  SUM(vip_segment_revenue) as total_vip_revenue,
  AVG(vip_revenue_contribution) as avg_vip_revenue_contribution,
  SUM(post_purchase_emails_sent) as total_post_purchase_emails_sent,
  AVG(post_purchase_email_open_rate) as avg_post_purchase_email_open_rate,
  AVG(post_purchase_email_ctr) as avg_post_purchase_email_ctr,
  AVG(social_engagement_rate) as avg_social_engagement_rate
FROM advocacy_metrics_daily;

-- View: Daily Advocacy Trends
CREATE OR REPLACE VIEW advocacy_metrics_trends AS
SELECT 
  date,
  total_nps_responses,
  net_promoter_score,
  referral_conversion_rate * 100 as referral_conversion_rate_pct,
  ugc_submission_rate * 100 as ugc_submission_rate_pct,
  review_participation_rate * 100 as review_participation_rate_pct,
  avg_review_rating,
  loyalty_program_participation_rate * 100 as loyalty_participation_rate_pct,
  vip_revenue_contribution * 100 as vip_revenue_contribution_pct,
  post_purchase_email_open_rate * 100 as post_purchase_email_open_rate_pct,
  post_purchase_email_ctr * 100 as post_purchase_email_ctr_pct,
  social_engagement_rate * 100 as social_engagement_rate_pct
FROM advocacy_metrics_daily
ORDER BY date DESC;

-- View: VIP Customer Performance
CREATE OR REPLACE VIEW vip_customer_performance AS
SELECT 
  c.id as customer_id,
  c.email,
  c.total_orders,
  c.total_revenue,
  c.average_order_value,
  le.loyalty_tier,
  le.points_balance,
  COUNT(DISTINCT r.id) as reviews_count,
  COUNT(DISTINCT ugc.id) as ugc_submissions_count,
  COUNT(DISTINCT ref.id) as referrals_count,
  COUNT(DISTINCT ref2.id) FILTER (WHERE ref2.referral_status = 'converted') as referral_conversions
FROM customers c
LEFT JOIN loyalty_enrollments le ON le.customer_id = c.id
LEFT JOIN reviews r ON r.customer_id = c.id
LEFT JOIN ugc_submissions ugc ON ugc.customer_id = c.id
LEFT JOIN referrals ref ON ref.referrer_customer_id = c.id
LEFT JOIN referrals ref2 ON ref2.referrer_customer_id = c.id
WHERE c.tags @> ARRAY['VIP'] OR c.tags @> ARRAY['vip'] OR le.loyalty_tier = 'vip'
GROUP BY c.id, c.email, c.total_orders, c.total_revenue, c.average_order_value, le.loyalty_tier, le.points_balance
ORDER BY c.total_revenue DESC;

-- ============================================================================
-- 5. FUNCTION TO POPULATE DAILY ADVOCACY METRICS
-- ============================================================================

CREATE OR REPLACE FUNCTION refresh_advocacy_metrics_daily(target_date date DEFAULT CURRENT_DATE)
RETURNS void AS $$
DECLARE
  v_total_customers int;
  v_vip_customers int;
  v_total_revenue decimal(12,2);
BEGIN
  -- Delete existing records for the target date
  DELETE FROM advocacy_metrics_daily WHERE date = target_date;

  -- Get customer counts
  SELECT 
    COUNT(*) FILTER (WHERE total_orders > 0),
    COUNT(*) FILTER (
      WHERE total_orders > 0 
        AND (tags @> ARRAY['VIP'] OR tags @> ARRAY['vip'] 
             OR EXISTS (SELECT 1 FROM loyalty_enrollments le WHERE le.customer_id = customers.id AND le.loyalty_tier = 'vip'))
    ),
    SUM(total_revenue) FILTER (
      WHERE tags @> ARRAY['VIP'] OR tags @> ARRAY['vip']
        OR EXISTS (SELECT 1 FROM loyalty_enrollments le WHERE le.customer_id = customers.id AND le.loyalty_tier = 'vip')
    )
  INTO 
    v_total_customers,
    v_vip_customers,
    v_total_revenue
  FROM customers;

  -- Get total revenue
  SELECT SUM(total_price)
  INTO v_total_revenue
  FROM shopify_orders
  WHERE financial_status = 'paid'
    AND order_date::date <= target_date;

  -- Insert aggregated metrics
  INSERT INTO advocacy_metrics_daily (
    date,
    total_nps_responses,
    promoters_count,
    passives_count,
    detractors_count,
    net_promoter_score,
    total_referrals,
    referral_conversions,
    referral_conversion_rate,
    total_ugc_submissions,
    ugc_approved,
    ugc_submission_rate,
    total_reviews,
    review_participation_rate,
    avg_review_rating,
    loyalty_program_members,
    loyalty_program_participation_rate,
    vip_customers_count,
    vip_segment_revenue,
    vip_revenue_contribution,
    post_purchase_emails_sent,
    post_purchase_emails_opened,
    post_purchase_emails_clicked,
    post_purchase_email_open_rate,
    post_purchase_email_ctr,
    social_engagements,
    social_engagement_rate
  )
  SELECT 
    target_date,
    -- NPS Metrics
    (SELECT COUNT(*) FROM nps_surveys WHERE survey_date <= target_date),
    (SELECT COUNT(*) FROM nps_surveys WHERE survey_date <= target_date AND nps_score >= 9),
    (SELECT COUNT(*) FROM nps_surveys WHERE survey_date <= target_date AND nps_score >= 7 AND nps_score <= 8),
    (SELECT COUNT(*) FROM nps_surveys WHERE survey_date <= target_date AND nps_score <= 6),
    (SELECT calculate_nps(NULL, target_date)),
    -- Referral Metrics
    (SELECT COUNT(*) FROM referrals WHERE created_at::date <= target_date),
    (SELECT COUNT(*) FROM referrals WHERE referral_status = 'converted' AND created_at::date <= target_date),
    (SELECT calculate_referral_conversion_rate(NULL, target_date)),
    -- UGC Metrics
    (SELECT COUNT(*) FROM ugc_submissions WHERE created_at::date <= target_date),
    (SELECT COUNT(*) FROM ugc_submissions WHERE status = 'approved' AND created_at::date <= target_date),
    (SELECT calculate_ugc_submission_rate(NULL, target_date)),
    -- Review Metrics
    (SELECT COUNT(*) FROM reviews WHERE created_at::date <= target_date),
    (SELECT calculate_review_participation_rate(NULL, target_date)),
    (SELECT AVG(rating) FROM reviews WHERE created_at::date <= target_date),
    -- Loyalty Metrics
    (SELECT COUNT(*) FROM loyalty_enrollments),
    (SELECT calculate_loyalty_participation_rate()),
    COALESCE(v_vip_customers, 0),
    (SELECT SUM(total_price) 
     FROM shopify_orders so
     JOIN customers c ON c.id = so.customer_id
     WHERE so.financial_status = 'paid'
       AND so.order_date::date <= target_date
       AND (c.tags @> ARRAY['VIP'] OR c.tags @> ARRAY['vip']
            OR EXISTS (SELECT 1 FROM loyalty_enrollments le WHERE le.customer_id = c.id AND le.loyalty_tier = 'vip'))
    ),
    (SELECT calculate_vip_revenue_contribution(NULL, target_date)),
    -- Post-Purchase Email Metrics
    (
      SELECT COUNT(DISTINCT ke.id)
      FROM klaviyo_events ke
      JOIN klaviyo_profiles kp ON kp.id = ke.profile_id
      JOIN customers c ON c.id = kp.customer_id
      JOIN shopify_orders so ON so.customer_id = c.id
        AND so.order_date < ke.occurred_at
        AND so.order_date >= ke.occurred_at - INTERVAL '7 days'
      WHERE ke.event_type = 'Sent Email'
        AND ke.occurred_at::date <= target_date
        AND so.financial_status = 'paid'
    ),
    (
      SELECT COUNT(DISTINCT ke.id)
      FROM klaviyo_events ke
      JOIN klaviyo_profiles kp ON kp.id = ke.profile_id
      JOIN customers c ON c.id = kp.customer_id
      JOIN shopify_orders so ON so.customer_id = c.id
        AND so.order_date < ke.occurred_at
        AND so.order_date >= ke.occurred_at - INTERVAL '7 days'
      WHERE ke.event_type = 'Opened Email'
        AND ke.occurred_at::date <= target_date
        AND so.financial_status = 'paid'
    ),
    (
      SELECT COUNT(DISTINCT ke.id)
      FROM klaviyo_events ke
      JOIN klaviyo_profiles kp ON kp.id = ke.profile_id
      JOIN customers c ON c.id = kp.customer_id
      JOIN shopify_orders so ON so.customer_id = c.id
        AND so.order_date < ke.occurred_at
        AND so.order_date >= ke.occurred_at - INTERVAL '7 days'
      WHERE ke.event_type = 'Clicked Email'
        AND ke.occurred_at::date <= target_date
        AND so.financial_status = 'paid'
    ),
    (SELECT calculate_post_purchase_email_open_rate(NULL, target_date)),
    (SELECT calculate_post_purchase_email_ctr(NULL, target_date)),
    -- Social Engagement
    (SELECT COUNT(*) FROM ugc_submissions 
     WHERE platform IN ('instagram', 'facebook', 'tiktok', 'twitter') 
       AND created_at::date <= target_date),
    (SELECT calculate_social_engagement_rate(NULL, target_date))
  FROM (SELECT 1) dummy;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 6. TRIGGERS FOR AUTO-UPDATE
-- ============================================================================

DROP TRIGGER IF EXISTS advocacy_metrics_daily_updated_at ON advocacy_metrics_daily;
CREATE TRIGGER advocacy_metrics_daily_updated_at 
  BEFORE UPDATE ON advocacy_metrics_daily
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS referrals_updated_at ON referrals;
CREATE TRIGGER referrals_updated_at 
  BEFORE UPDATE ON referrals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS reviews_updated_at ON reviews;
CREATE TRIGGER reviews_updated_at 
  BEFORE UPDATE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS ugc_submissions_updated_at ON ugc_submissions;
CREATE TRIGGER ugc_submissions_updated_at 
  BEFORE UPDATE ON ugc_submissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS loyalty_enrollments_updated_at ON loyalty_enrollments;
CREATE TRIGGER loyalty_enrollments_updated_at 
  BEFORE UPDATE ON loyalty_enrollments
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- 7. COMMENTS
-- ============================================================================

COMMENT ON TABLE advocacy_metrics_daily IS 'Daily aggregated advocacy/loyalty metrics (NPS, referrals, UGC, reviews, loyalty)';
COMMENT ON TABLE referrals IS 'Customer referral program tracking';
COMMENT ON TABLE reviews IS 'Customer product/order reviews';
COMMENT ON TABLE ugc_submissions IS 'User-generated content submissions';
COMMENT ON TABLE loyalty_enrollments IS 'Loyalty program enrollments and points';
COMMENT ON TABLE nps_surveys IS 'Net Promoter Score survey responses';
COMMENT ON VIEW advocacy_metrics_summary IS 'Aggregated advocacy metrics summary (all time)';
COMMENT ON VIEW advocacy_metrics_trends IS 'Daily advocacy metrics trends';
COMMENT ON VIEW vip_customer_performance IS 'VIP customer performance and advocacy metrics';

