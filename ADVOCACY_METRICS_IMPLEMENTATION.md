# Advocacy / Loyalty Metrics Implementation Summary

## ✅ What Was Implemented

### 1. **Supporting Tables** (5 new tables)

#### `referrals`
Tracks referral program:
- Referrer and referred customer relationships
- Referral codes and status (pending/completed/converted)
- Conversion tracking

#### `reviews`
Customer reviews/ratings:
- Product and order reviews
- Ratings (1-5 stars)
- Verified purchase status
- Helpful count and status

#### `ugc_submissions`
User-Generated Content:
- Submission types (photo, video, testimonial, social_post)
- Platform (Instagram, Facebook, TikTok, website)
- Approval status

#### `loyalty_enrollments`
Loyalty program:
- Customer enrollment and tier (member, silver, gold, platinum, vip)
- Points balance and total earned
- Last activity tracking

#### `nps_surveys`
Net Promoter Score surveys:
- NPS score (0-10)
- Survey type (post_purchase, periodic, transactional)
- Feedback text

### 2. **Daily Metrics Table**

#### `advocacy_metrics_daily`
Stores daily aggregated advocacy metrics:
- **NPS Metrics**: `total_nps_responses`, `promoters_count`, `passives_count`, `detractors_count`, `net_promoter_score`
- **Referral Metrics**: `total_referrals`, `referral_conversions`, `referral_conversion_rate`
- **UGC Metrics**: `total_ugc_submissions`, `ugc_approved`, `ugc_submission_rate`
- **Review Metrics**: `total_reviews`, `review_participation_rate`, `avg_review_rating`
- **Loyalty Metrics**: `loyalty_program_members`, `loyalty_program_participation_rate`, `vip_customers_count`, `vip_segment_revenue`, `vip_revenue_contribution`
- **Post-Purchase Email**: `post_purchase_emails_sent/opened/clicked`, `post_purchase_email_open_rate`, `post_purchase_email_ctr`
- **Social Engagement**: `social_engagements`, `social_engagement_rate`

### 3. **Functions** (9 functions created)

All advocacy metrics can be calculated using SQL functions:

```sql
-- Net Promoter Score (NPS)
SELECT calculate_nps('2024-01-01', '2024-12-31');

-- Referral Conversion Rate
SELECT calculate_referral_conversion_rate('2024-01-01', '2024-12-31');

-- UGC Submission Rate
SELECT calculate_ugc_submission_rate('2024-01-01', '2024-12-31');

-- Review Participation Rate
SELECT calculate_review_participation_rate('2024-01-01', '2024-12-31');

-- Loyalty Program Participation Rate
SELECT calculate_loyalty_participation_rate();

-- VIP Revenue Contribution
SELECT calculate_vip_revenue_contribution('2024-01-01', '2024-12-31');

-- Post-Purchase Email Open Rate
SELECT calculate_post_purchase_email_open_rate('2024-01-01', '2024-12-31');

-- Post-Purchase Email CTR
SELECT calculate_post_purchase_email_ctr('2024-01-01', '2024-12-31');

-- Social Engagement Rate
SELECT calculate_social_engagement_rate('2024-01-01', '2024-12-31');
```

### 4. **Materialized Views**

#### `advocacy_metrics_summary`
Aggregated metrics summary (all time):
- Average NPS, referral conversion rate, UGC submission rate
- Average review participation rate and rating
- Average loyalty participation rate
- VIP revenue contribution
- Average post-purchase email metrics
- Average social engagement rate

#### `advocacy_metrics_trends`
Daily trends view:
- Shows daily metrics with percentages formatted
- Useful for time-series analysis

#### `vip_customer_performance`
VIP customer performance:
- Revenue, orders, loyalty tier, points
- Reviews, UGC submissions, referrals count
- Sorted by revenue

### 5. **Refresh Function**

#### `refresh_advocacy_metrics_daily(target_date)`
Populates `advocacy_metrics_daily` for a specific date:
- Aggregates from `nps_surveys`, `referrals`, `reviews`, `ugc_submissions`, `loyalty_enrollments`
- Links to `customers` and `shopify_orders` for VIP calculations
- Links to `klaviyo_events` for post-purchase email metrics
- Calculates all metrics automatically

## 📊 Where Each Metric Is Stored

| Metric | Primary Storage | Query Method |
|--------|----------------|--------------|
| **Net Promoter Score (NPS)** | `advocacy_metrics_daily.net_promoter_score` | `advocacy_metrics_summary.avg_nps` or `calculate_nps()` |
| **Referral Conversion Rate** | `advocacy_metrics_daily.referral_conversion_rate` | `advocacy_metrics_summary.avg_referral_conversion_rate` or `calculate_referral_conversion_rate()` |
| **UGC Submission Rate** | `advocacy_metrics_daily.ugc_submission_rate` | `advocacy_metrics_summary.avg_ugc_submission_rate` or `calculate_ugc_submission_rate()` |
| **Review Participation Rate** | `advocacy_metrics_daily.review_participation_rate` | `advocacy_metrics_summary.avg_review_participation_rate` or `calculate_review_participation_rate()` |
| **Loyalty Program Participation Rate** | `advocacy_metrics_daily.loyalty_program_participation_rate` | `advocacy_metrics_summary.avg_loyalty_participation_rate` or `calculate_loyalty_participation_rate()` |
| **VIP Segment Revenue Contribution** | `advocacy_metrics_daily.vip_revenue_contribution` | `advocacy_metrics_summary.avg_vip_revenue_contribution` or `calculate_vip_revenue_contribution()` |
| **Post-Purchase Email Open Rate** | `advocacy_metrics_daily.post_purchase_email_open_rate` | `advocacy_metrics_summary.avg_post_purchase_email_open_rate` or `calculate_post_purchase_email_open_rate()` |
| **Post-Purchase Email CTR** | `advocacy_metrics_daily.post_purchase_email_ctr` | `advocacy_metrics_summary.avg_post_purchase_email_ctr` or `calculate_post_purchase_email_ctr()` |
| **Social Engagement Rate** | `advocacy_metrics_daily.social_engagement_rate` | `advocacy_metrics_summary.avg_social_engagement_rate` or `calculate_social_engagement_rate()` |

## 🔗 Alignment with Existing Tables

### Uses Existing Data:
- **`customers`**: `tags` (for VIP identification), `total_orders`, `total_revenue`
- **`shopify_orders`**: For VIP revenue calculations and post-purchase email timing
- **`klaviyo_events`**: For post-purchase email metrics (emails sent within 7 days after purchase)
- **`klaviyo_profiles`**: Links Klaviyo events to customers

### Integrates With:
- **Retention metrics**: VIP customers overlap with high-value customers
- **Consideration metrics**: Post-purchase email metrics align with email engagement
- **Customer lifetime metrics**: VIP revenue contribution uses LTV data

## 🚀 Usage

### Generate Mock Data (First Time)

```bash
npm run data:advocacy
```

This will generate:
- NPS surveys
- Referrals
- Reviews
- UGC submissions
- Loyalty enrollments

### Populate Metrics (Run Daily)

```bash
npm run metrics:advocacy:populate
```

This will:
- Process key dates (today, last 30 days, monthly samples)
- Populate `advocacy_metrics_daily`
- Calculate all metrics automatically

### Query All Metrics

```bash
npm run metrics:advocacy
```

Shows:
- Overall summary (all-time averages)
- VIP customer performance (top 10)
- Daily trends (last 7 days)
- Sample function calculations

### Custom Queries

```sql
-- Get NPS for last 30 days
SELECT calculate_nps(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE);

-- Get VIP customers and their advocacy
SELECT * FROM vip_customer_performance
ORDER BY total_revenue DESC
LIMIT 20;

-- Get referral performance
SELECT 
  referrer_customer_id,
  COUNT(*) as total_referrals,
  COUNT(*) FILTER (WHERE referral_status = 'converted') as conversions
FROM referrals
GROUP BY referrer_customer_id
ORDER BY conversions DESC;

-- Get top reviewers
SELECT 
  c.email,
  COUNT(r.id) as review_count,
  AVG(r.rating) as avg_rating
FROM customers c
JOIN reviews r ON r.customer_id = c.id
GROUP BY c.id, c.email
ORDER BY review_count DESC
LIMIT 10;

-- Get UGC by platform
SELECT 
  platform,
  COUNT(*) as submissions,
  COUNT(*) FILTER (WHERE status = 'approved') as approved
FROM ugc_submissions
GROUP BY platform
ORDER BY submissions DESC;
```

## 📈 Scheduled Refresh (Recommended)

Set up a cron job or scheduled Lambda to refresh metrics daily:

```sql
-- Refresh today's metrics
SELECT refresh_advocacy_metrics_daily(CURRENT_DATE);

-- Refresh last 7 days (backfill)
DO $$
DECLARE
  d date;
BEGIN
  FOR d IN SELECT generate_series(CURRENT_DATE - 7, CURRENT_DATE - 1, '1 day'::interval)::date
  LOOP
    PERFORM refresh_advocacy_metrics_daily(d);
  END LOOP;
END $$;
```

## 📝 Notes

- Metrics are **pre-calculated** for performance (no real-time computation needed)
- Daily table is **append-only** (one row per date)
- Functions allow **custom date ranges** for ad-hoc analysis
- Views provide **aggregated summaries** across all time periods
- All metrics handle **NULL values** gracefully
- **VIP identification** uses `customers.tags` array or `loyalty_enrollments.loyalty_tier = 'vip'`
- **Post-purchase emails** are identified by emails sent within 7 days after a paid order
- **Social engagement** uses UGC submissions from social platforms as proxy (can be enhanced with API integration)

## ✅ Status

All 8 advocacy/loyalty metrics are now:
- ✅ Stored in database tables
- ✅ Calculated via SQL functions  
- ✅ Available in materialized views
- ✅ Populated with mock data
- ✅ Queryable via scripts
- ✅ Aligned with existing customer, order, and Klaviyo data

## 🎯 Use Cases

1. **Measure Brand Advocacy**: Track NPS to identify promoters vs detractors
2. **Referral Program**: Monitor referral conversion rates and reward top referrers
3. **UGC Campaigns**: Track submission rates and platform performance
4. **Review Management**: Monitor review participation and ratings
5. **Loyalty Program**: Monitor participation rates and VIP revenue
6. **Post-Purchase Engagement**: Track email open/click rates after purchase
7. **Social Strategy**: Measure social engagement across platforms
8. **VIP Program**: Identify and reward high-value advocates

## 📊 NPS Calculation

Net Promoter Score = % Promoters - % Detractors

- **Promoters**: NPS score 9-10
- **Passives**: NPS score 7-8
- **Detractors**: NPS score 0-6

Score range: -100 to +100
- Positive: More promoters than detractors
- Negative: More detractors than promoters

