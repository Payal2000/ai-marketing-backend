# Comprehensive E-Commerce Data Warehouse Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [Complete Database Schema](#complete-database-schema)
3. [All Metrics Implemented](#all-metrics-implemented)
4. [How Metrics Connect](#how-metrics-connect)
5. [Data Flow Architecture](#data-flow-architecture)
6. [Query Examples](#query-examples)
7. [Scripts and Automation](#scripts-and-automation)
8. [Deployment and Usage](#deployment-and-usage)

---

## System Overview

### What We Built
A comprehensive PostgreSQL data warehouse for e-commerce analytics with:
- **Base e-commerce schema** integrating Shopify, Klaviyo, and Advertising platforms
- **4 metric categories** (Acquisition, Consideration, Retention, Advocacy) covering the complete customer lifecycle
- **32 database tables** (all populated with data)
- **50+ SQL functions** for calculating metrics on-demand
- **15+ materialized views** for fast aggregated queries
- **Automated daily refresh functions** for pre-computed metrics
- **TypeScript scripts** for data generation, population, and querying

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    BASE E-COMMERCE SCHEMA                    │
│  (customers, orders, products, events, campaigns, ads)     │
│                   20 Core Tables                             │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                    │
        ▼                  ▼                    ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ ACQUISITION  │  │ CONSIDERATION│  │  RETENTION   │
│   METRICS    │  │   METRICS    │  │   METRICS    │
│  2 Tables    │  │  2 Tables    │  │  2 Tables    │
│  11 Functions│  │  11 Functions│  │  11 Functions│
│  3 Views     │  │  2 Views     │  │  3 Views     │
└──────────────┘  └──────────────┘  └──────────────┘
        │                  │                    │
        └──────────────────┼──────────────────┘
                           │
                           ▼
                  ┌──────────────┐
                  │   ADVOCACY   │
                  │   METRICS    │
                  │  6 Tables    │
                  │  9 Functions │
                  │  3 Views     │
                  └──────────────┘
```

---

## Complete Database Schema

### Base E-Commerce Schema (`db/ecommerce_schema.sql`)

#### 1. Customer & Identity Layer
- **`customers`** (20 rows) - Unified customer master table
  - Links Shopify, Klaviyo, and other systems
  - Stores: `total_orders`, `total_revenue`, `average_order_value`, `first_order_date`, `last_order_date`, `tags`
  - **Key for**: All metric calculations across all categories

- **`customer_addresses`** (34 rows) - Shipping/billing addresses
  - Links to: `customers.id`

#### 2. Shopify Commerce Layer
- **`shopify_orders`** (63 rows) - All orders
  - Fields: `order_date`, `total_price`, `financial_status`, `source`, `customer_id`
  - **Key for**: Revenue calculations, retention metrics, VIP revenue

- **`shopify_order_line_items`** (172 rows) - Order line items
  - Links to: `shopify_orders.id`, `shopify_products.id`

- **`shopify_products`** (10 rows) - Product catalog
  - Fields: `title`, `handle`, `price`, `tags`

- **`shopify_product_variants`** (35 rows) - Product variants
  - Links to: `shopify_products.id`

- **`shopify_events`** (189 rows) - Behavioral tracking events
  - Fields: `event_type`, `customer_id`, `session_id`, `event_properties` (JSONB with UTMs)
  - Event types: `page_viewed`, `product_viewed`, `add_to_cart`, `checkout_started`, `checkout_completed`
  - **Key for**: Consideration metrics, session tracking, traffic source analysis

#### 3. Klaviyo Marketing Layer
- **`klaviyo_profiles`** (20 rows) - Unified customer profiles
  - Links to: `customers.id` via `klaviyo_profile_id`

- **`klaviyo_campaigns`** (6 rows) - Email/SMS campaigns
  - Fields: `name`, `type`, `sent_count`, `delivered_count`, `unique_opens_count`, `unique_clicks_count`

- **`klaviyo_flows`** (4 rows) - Automation flows
  - Fields: `name`, `trigger_type`, `status`

- **`klaviyo_flow_steps`** (17 rows) - Flow step metrics
  - Links to: `klaviyo_flows.id`

- **`klaviyo_events`** (100 rows) - Email/SMS events
  - Event types: `Sent Email`, `Opened Email`, `Clicked Email`, `Subscribed to List`, `Placed Order`
  - Links to: `klaviyo_profiles.id`, `klaviyo_campaigns.id`
  - **Key for**: Email metrics across all categories

- **`klaviyo_lists`** (4 rows) - Email lists
- **`klaviyo_segments`** (4 rows) - Dynamic segments
- **`klaviyo_profile_lists`** (5 rows) - Profile-list memberships
- **`klaviyo_predictive_metrics`** (20 rows) - AI predictions
  - Fields: `predicted_next_order_date`, `predicted_churn_probability`, `predicted_lifetime_value`, `email_engagement_probability`
  - **Key for**: Retention metrics (reorder probability, churn prediction)

#### 4. Advertising Layer
- **`ad_events`** (30 rows) - Advertising platform events
  - Fields: `platform`, `campaign_id`, `spend`, `impressions`, `clicks`, `conversions`, `revenue`, `customer_id`, `order_id`
  - **Key for**: Acquisition metrics (CAC, CTR, ROAS, LTV:CAC)

#### 5. Analytics & Aggregation Layer (Base)
- **`customer_metrics_daily`** (392 rows) - Daily customer metrics
  - Pre-aggregated: `orders_count`, `revenue`, `products_viewed_count`, `cart_adds_count`

- **`campaign_performance_daily`** (6 rows) - Daily campaign metrics
  - Links to: `klaviyo_campaigns.id`

- **`product_performance_daily`** (327 rows) - Daily product metrics
  - Links to: `shopify_products.id`

---

### Acquisition Metrics Schema (`db/acquisition_metrics_schema.sql`)

#### Tables
- **`acquisition_metrics_daily`** (30 rows)
  - Aggregates: `ad_events` by platform/campaign/date
  - Metrics: `cac`, `cpc`, `cpm`, `ctr`, `cvr`, `roas`, `cost_per_signup`, `bounce_rate`, `session_to_signup_ratio`

- **`traffic_source_metrics_daily`** (182 rows)
  - Aggregates: `shopify_events` by source/UTM/date
  - Metrics: `sessions_count`, `signups_count`, `orders_count`, `revenue`, `bounce_rate`, `signup_rate`, `conversion_rate`

#### Functions (11)
1. `calculate_cac(platform, start_date, end_date)` - Customer Acquisition Cost
2. `calculate_ctr(platform, campaign_id, start_date, end_date)` - Click-Through Rate
3. `calculate_cvr(platform, start_date, end_date)` - Conversion Rate
4. `calculate_cost_per_signup(platform, start_date, end_date)` - Cost per Signup
5. `calculate_session_to_signup_ratio(start_date, end_date)` - Session-to-Signup Ratio
6. `calculate_bounce_rate(start_date, end_date)` - Bounce Rate
7. `calculate_ltv_cac_ratio(platform)` - LTV:CAC Ratio
8. `refresh_acquisition_metrics_daily(date)` - Refresh daily metrics
9. `refresh_traffic_source_metrics_daily(date)` - Refresh traffic metrics

#### Views (3)
- `acquisition_metrics_summary` - Platform-level aggregations (all time)
- `traffic_source_summary` - Traffic source performance summary
- `source_roi_summary` - LTV:CAC ratios by platform

---

### Consideration Metrics Schema (`db/consideration_metrics_schema.sql`)

#### Tables
- **`consideration_metrics_daily`** (660 rows)
  - Aggregates: `shopify_events` + `klaviyo_events` by date
  - Metrics: `add_to_cart_rate`, `view_to_add_to_cart_ratio`, `wishlist_add_rate`, `cart_abandonment_rate`, `product_page_bounce_rate`, `avg_pages_per_session`, `avg_session_duration_seconds`, `avg_scroll_depth_percent`, `repeat_visit_rate_7d`, `email_open_rate`, `email_ctr`, `engagement_score`

- **`session_engagement_daily`** (120 rows)
  - Session-level metrics: `page_views_count`, `product_views_count`, `add_to_cart_count`, `session_duration_seconds`, `bounce`, `is_product_page_bounce`, `has_repeat_visit_7d`

#### Functions (11)
1. `calculate_add_to_cart_rate(start_date, end_date)` - Add-to-Cart Rate
2. `calculate_view_to_add_to_cart_ratio(start_date, end_date)` - View-to-Add-to-Cart Ratio
3. `calculate_product_view_depth(start_date, end_date)` - Avg Pages per Session
4. `calculate_avg_session_duration(start_date, end_date)` - Session Duration
5. `calculate_avg_scroll_depth(start_date, end_date)` - Scroll Depth %
6. `calculate_wishlist_add_rate(start_date, end_date)` - Wishlist Add Rate
7. `calculate_cart_abandonment_rate(start_date, end_date)` - Cart Abandonment Rate
8. `calculate_product_page_bounce_rate(start_date, end_date)` - Product Page Bounce Rate
9. `calculate_email_open_rate(start_date, end_date)` - Email Open Rate (Klaviyo)
10. `calculate_email_ctr(start_date, end_date)` - Email Click-Through Rate
11. `calculate_repeat_visit_rate_7d(start_date, end_date)` - Repeat Visit Rate (7 days)
12. `calculate_engagement_score(start_date, end_date)` - Weighted Engagement Score
13. `refresh_consideration_metrics_daily(date)` - Refresh daily metrics
14. `refresh_session_engagement_daily(date)` - Refresh session metrics

#### Views (2)
- `consideration_metrics_summary` - All-time aggregations
- `consideration_metrics_trends` - Daily trends

---

### Retention Metrics Schema (`db/retention_metrics_schema.sql`)

#### Tables
- **`retention_metrics_daily`** (53 rows)
  - Aggregates: `customers` + `shopify_orders` + `klaviyo_predictive_metrics` by date
  - Metrics: `repeat_purchase_rate`, `active_customer_rate_30d/60d/90d`, `churn_rate_30d/60d/90d`, `avg_days_between_purchases`, `avg_ltv`, `avg_reorder_probability`, `avg_churn_probability`, `avg_predicted_ltv`, `engagement_decay_rate`, `winback_email_open_rate`, `subscription_retention_rate`, `avg_replenishment_accuracy_days`, `avg_ltv_cac_ratio`

- **`customer_retention_cohorts`** (20 rows)
  - Customer-level retention data by cohort (first order month)
  - Fields: `cohort_date`, `is_active_30d/60d/90d`, `is_churned_30d/60d/90d`, `is_repeat_customer`, `predicted_next_order_date`, `predicted_churn_probability`, `predicted_ltv`, `avg_days_between_orders`

#### Functions (11)
1. `calculate_repeat_purchase_rate(start_date, end_date)` - Repeat Purchase Rate
2. `calculate_avg_days_between_purchases(start_date, end_date)` - Time Between Purchases
3. `calculate_active_customer_rate(days_active)` - Active Customer % (X days)
4. `calculate_churn_rate(days_inactive)` - Churn Rate (% inactive after X days)
5. `calculate_avg_ltv(start_date, end_date)` - Average Customer Lifetime Value
6. `calculate_avg_reorder_probability()` - Reorder Probability (Klaviyo)
7. `calculate_subscription_retention_rate(start_date, end_date)` - Subscription Retention Rate
8. `calculate_engagement_decay_rate(start_date, end_date)` - Email Inactivity Trend
9. `calculate_winback_email_open_rate(start_date, end_date)` - Winback Email Open Rate
10. `calculate_replenishment_accuracy()` - Replenishment Timing Accuracy
11. `calculate_avg_ltv_cac_ratio()` - Average LTV:CAC Ratio
12. `refresh_retention_metrics_daily(date)` - Refresh daily metrics
13. `refresh_customer_retention_cohorts(date)` - Refresh cohorts

#### Views (3)
- `retention_metrics_summary` - All-time aggregations
- `customer_retention_cohorts_summary` - Cohort-level retention
- `retention_metrics_trends` - Daily trends

---

### Advocacy Metrics Schema (`db/advocacy_metrics_schema.sql`)

#### Supporting Tables
- **`referrals`** (10 rows) - Referral program tracking
  - Fields: `referrer_customer_id`, `referred_customer_id`, `referral_code`, `referral_status`, `conversion_date`

- **`reviews`** (30 rows) - Customer reviews/ratings
  - Fields: `customer_id`, `order_id`, `product_id`, `rating`, `review_text`, `is_verified_purchase`, `status`

- **`ugc_submissions`** (12 rows) - User-Generated Content
  - Fields: `customer_id`, `submission_type`, `platform`, `status`

- **`loyalty_enrollments`** (20 rows) - Loyalty program enrollments
  - Fields: `customer_id`, `loyalty_tier`, `points_balance`, `total_points_earned`, `enrollment_date`

- **`nps_surveys`** (15 rows) - NPS survey responses
  - Fields: `customer_id`, `order_id`, `nps_score`, `feedback_text`, `survey_type`, `survey_date`

#### Daily Metrics Table
- **`advocacy_metrics_daily`** (52 rows)
  - Aggregates: All advocacy tables + `customers` + `shopify_orders` + `klaviyo_events` by date
  - Metrics: `net_promoter_score`, `referral_conversion_rate`, `ugc_submission_rate`, `review_participation_rate`, `loyalty_program_participation_rate`, `vip_revenue_contribution`, `post_purchase_email_open_rate`, `post_purchase_email_ctr`, `social_engagement_rate`

#### Functions (9)
1. `calculate_nps(start_date, end_date)` - Net Promoter Score
2. `calculate_referral_conversion_rate(start_date, end_date)` - Referral Conversion Rate
3. `calculate_ugc_submission_rate(start_date, end_date)` - UGC Submission Rate
4. `calculate_review_participation_rate(start_date, end_date)` - Review Participation Rate
5. `calculate_loyalty_participation_rate()` - Loyalty Program Participation Rate
6. `calculate_vip_revenue_contribution(start_date, end_date)` - VIP Revenue Contribution
7. `calculate_post_purchase_email_open_rate(start_date, end_date)` - Post-Purchase Email Open Rate
8. `calculate_post_purchase_email_ctr(start_date, end_date)` - Post-Purchase Email CTR
9. `calculate_social_engagement_rate(start_date, end_date)` - Social Engagement Rate
10. `refresh_advocacy_metrics_daily(date)` - Refresh daily metrics

#### Views (3)
- `advocacy_metrics_summary` - All-time aggregations
- `advocacy_metrics_trends` - Daily trends
- `vip_customer_performance` - VIP customer performance and advocacy metrics

---

## All Metrics Implemented

### Total: 44 Metrics Across 4 Categories

#### 1. ACQUISITION METRICS (13 metrics)
**Goal**: Measure traffic efficiency and acquisition cost

1. **Customer Acquisition Cost (CAC)** - Cost to acquire a customer
2. **Click-Through Rate (CTR)** - Percentage of impressions that result in clicks
3. **Conversion Rate (CVR)** - Percentage of clicks that result in conversions
4. **Cost per Click (CPC)** - Average cost per click
5. **Cost per Impression (CPM)** - Cost per 1,000 impressions
6. **Return on Ad Spend (ROAS)** - Revenue generated per dollar spent
7. **Traffic by Source/Channel** - Sessions and engagement by traffic source
8. **New Users / First-Time Visitors** - Count of new customers acquired
9. **Email Sign-up Rate** - Percentage of sessions that result in email signups
10. **Cost per Signup / Lead** - Cost to acquire each email signup
11. **Session-to-Signup Ratio** - Ratio of sessions to email signups
12. **Bounce Rate** - Percentage of single-page sessions
13. **Source ROI (LTV:CAC ratio by channel)** - Lifetime value to acquisition cost ratio

#### 2. CONSIDERATION METRICS (12 metrics)
**Goal**: Identify intent, engagement, and drop-offs before purchase

1. **Add-to-Cart Rate** - Percentage of visitors who add items to cart
2. **View-to-Add-to-Cart Ratio** - Ratio of product views to add-to-cart events
3. **Product View Depth** - Average pages per session
4. **Time on Site / Session Duration** - Average session duration in seconds
5. **Scroll Depth %** - Average percentage of page scrolled
6. **Wishlist Add Rate** - Percentage of visitors who add to wishlist
7. **Cart Abandonment Rate** - Percentage of carts that don't reach checkout
8. **Product Page Bounce Rate** - Percentage of single-page visits on product pages
9. **Email Open Rate** - Percentage of emails opened (from Klaviyo)
10. **Email Click-Through Rate** - Percentage of opened emails that are clicked
11. **Engagement Score** - Weighted score across site + email engagement
12. **% of Sessions with Repeat Visits in 7 Days** - Repeat visitor rate

#### 3. RETENTION METRICS (11 metrics)
**Goal**: Measure loyalty, repeat behavior, and churn risk

1. **Repeat Purchase Rate** - Percentage of customers who purchase more than once
2. **Time Between Purchases (Days)** - Average days between orders for repeat customers
3. **Customer Lifetime Value (LTV)** - Total revenue generated by a customer
4. **Active Customer %** - Percentage of customers who purchased in last X days (30/60/90)
5. **Churn Rate** - Percentage of customers inactive after X days (30/60/90)
6. **Reorder Probability** - Klaviyo's predicted likelihood of next order
7. **Subscription Retention Rate** - Percentage of subscription customers retained
8. **Engagement Decay Rate** - Email inactivity trend (declining engagement)
9. **Winback Email Open Rate** - Open rate for re-engagement campaigns
10. **Replenishment Timing Accuracy** - Accuracy of predicted vs actual reorder timing
11. **CLV:CAC Ratio** - Customer lifetime value to acquisition cost ratio

#### 4. ADVOCACY / LOYALTY METRICS (8 metrics)
**Goal**: Identify brand promoters and referral opportunities

1. **Net Promoter Score (NPS)** - Promoter score minus detractor score (-100 to +100)
2. **Referral Conversion Rate** - Percentage of referrals that convert to customers
3. **UGC Submission Rate** - Percentage of customers who submit user-generated content
4. **Review Participation Rate** - Percentage of customers who leave reviews
5. **Loyalty Program Participation Rate** - Percentage of customers enrolled in loyalty program
6. **VIP Segment Revenue Contribution** - Percentage of total revenue from VIP customers
7. **Post-Purchase Email Open/Click Rate** - Email engagement after purchase
8. **Social Engagement Rate** - Percentage of customers engaging on social platforms

---

## How Metrics Connect

### The Customer Journey Connection

```
ACQUISITION → CONSIDERATION → RETENTION → ADVOCACY
    ↓              ↓              ↓            ↓
```

### 1. Acquisition → Consideration Flow

**Data Flow:**
```
ad_events (impressions, clicks, conversions)
    ↓ (customer_id, order_id)
shopify_events (page_viewed, product_viewed, add_to_cart)
    ↓ (session_id, customer_id)
consideration_metrics_daily (add_to_cart_rate, session_duration)
```

**Connection Points:**
- `ad_events.customer_id` → `customers.id` → `shopify_events.customer_id`
- `ad_events.order_id` → `shopify_orders.id`
- `ad_events.platform` → `traffic_source_metrics_daily.source` (via UTM tracking)
- Traffic from ads → `shopify_events.event_properties->>'referrer'` → `traffic_source_metrics_daily`

**Shared Metrics:**
- Bounce rate: Calculated in both `acquisition_metrics_daily` and `consideration_metrics_daily`
- Session data: `acquisition_metrics_daily.sessions_count` ↔ `consideration_metrics_daily.total_sessions`
- Signup rate: `acquisition_metrics_daily.email_signups_count` → `consideration_metrics_daily` (email engagement)

---

### 2. Consideration → Retention Flow

**Data Flow:**
```
shopify_events (add_to_cart, checkout_started, checkout_completed)
    ↓ (customer_id, order_id)
shopify_orders (paid orders)
    ↓ (customer_id)
customers (total_orders++, total_revenue+=)
    ↓
retention_metrics_daily (repeat_purchase_rate, ltv)
```

**Connection Points:**
- `consideration_metrics_daily.cart_abandonment_rate` → Affects `retention_metrics_daily` (high abandonment = lower retention potential)
- `shopify_events.session_id` + `customer_id` → Identifies repeat visitors → `retention_metrics_daily.repeat_visit_rate_7d`
- `consideration_metrics_daily.email_open_rate` → `retention_metrics_daily.engagement_decay_rate`
- `consideration_metrics_daily.engagement_score` → Correlates with `retention_metrics_daily.avg_reorder_probability`

**Shared Metrics:**
- Email engagement: Both track email metrics but from different perspectives
  - Consideration: General email engagement
  - Retention: Engagement decay and winback campaigns
- Session data: `consideration_metrics_daily.total_sessions` → `retention_metrics_daily` (identifies active customers)

---

### 3. Retention → Advocacy Flow

**Data Flow:**
```
customers (total_orders > 1, total_revenue, tags)
    ↓
loyalty_enrollments (loyalty_tier = 'vip')
    ↓
advocacy_metrics_daily (vip_revenue_contribution, nps)
```

**Connection Points:**
- `retention_metrics_daily.repeat_purchase_rate` → `advocacy_metrics_daily` (repeat customers more likely to be advocates)
- `retention_metrics_daily.avg_ltv` → `advocacy_metrics_daily.vip_revenue_contribution`
- `customers.tags` @> 'VIP' → `advocacy_metrics_daily.vip_customers_count`
- `retention_metrics_daily.avg_reorder_probability` → Correlates with `advocacy_metrics_daily.referral_conversion_rate`
- `retention_metrics_daily.avg_churn_probability` → Used to identify customers for winback (advocacy)

**Shared Metrics:**
- VIP identification: `customers.tags` or `loyalty_enrollments.loyalty_tier = 'vip'`
- Revenue: `retention_metrics_daily.total_ltv` → `advocacy_metrics_daily.vip_segment_revenue`

---

### 4. Acquisition → Retention → Advocacy (Complete Cycle)

**The Value Chain:**
```
acquisition_metrics_daily.cac (Cost to acquire)
    ↓
customers.total_revenue (LTV from retention)
    ↓
retention_metrics_daily.avg_ltv_cac_ratio
    ↓
advocacy_metrics_daily.vip_revenue_contribution
```

**Key Connection: LTV:CAC Ratio**
- **Acquisition** calculates: `CAC` from `ad_events.spend` / `customers` acquired
- **Retention** calculates: `LTV` from `customers.total_revenue`
- **Both** calculate: `LTV:CAC ratio` = `LTV / CAC`
- **Advocacy** uses: VIP revenue contribution (which is LTV-based)

---

### Cross-Category Connection Matrix

| Metric Category | Shares Data With | Connection Type |
|----------------|------------------|-----------------|
| **Acquisition** | Consideration | Traffic sources, sessions, bounce rates |
| **Acquisition** | Retention | Customer acquisition (CAC) → LTV calculation |
| **Acquisition** | Advocacy | New customers → Future advocates |
| **Consideration** | Retention | Engagement → Retention likelihood |
| **Consideration** | Advocacy | High engagement → Advocacy potential |
| **Retention** | Advocacy | Repeat customers → VIP → Advocates |

---

### Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    EXTERNAL DATA SOURCES                      │
│  Shopify API | Klaviyo API | Ad Platforms (Meta/Google/etc)   │
└──────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────┐
│                    BASE E-COMMERCE SCHEMA                     │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  customers (CORE IDENTITY HUB)                      │   │
│  │  • Links all systems via customer_id               │   │
│  │  • Stores: total_orders, total_revenue, tags         │   │
│  └─────────────────────────────────────────────────────┘   │
│            │              │              │                  │
│            ├──────────────┼──────────────┤                  │
│            │              │              │                  │
│    ┌───────▼──────┐ ┌─────▼──────┐ ┌────▼──────┐          │
│    │ shopify_     │ │ klaviyo_   │ │ ad_events │          │
│    │ orders       │ │ profiles   │ │           │          │
│    │ • Revenue    │ │ • Email     │ │ • Spend   │          │
│    │ • Orders     │ │ • Events    │ │ • CAC     │          │
│    └──────────────┘ └────────────┘ └───────────┘          │
│            │              │              │                  │
│    ┌───────▼──────────────┼──────────────▼──────┐          │
│    │ shopify_events      │                      │          │
│    │ • Behavioral events │                      │          │
│    │ • Session tracking │                      │          │
│    │ • UTM tracking     │                      │          │
│    └─────────────────────┴──────────────────────┘          │
└──────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                    │
        ▼                  ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  ACQUISITION      │  │  CONSIDERATION  │  │  RETENTION      │
│  METRICS          │  │  METRICS        │  │  METRICS        │
│                   │  │                  │  │                  │
│  Reads From:      │  │  Reads From:    │  │  Reads From:    │
│  • ad_events      │  │  • shopify_     │  │  • customers    │
│  • customers      │  │    events       │  │  • shopify_     │
│  • shopify_events │  │  • klaviyo_     │  │    orders       │
│  • klaviyo_events │  │    events       │  │  • klaviyo_      │
│                   │  │  • customers    │  │    predictive_  │
│  Calculates:      │  │                  │  │    metrics      │
│  • CAC            │  │  Calculates:   │  │                  │
│  • CTR            │  │  • Add-to-Cart │  │  Calculates:     │
│  • ROAS           │  │  • Bounce Rate │  │  • Repeat Rate  │
│  • LTV:CAC        │  │  • Session     │  │  • Churn Rate   │
│                   │  │    Depth       │  │  • LTV          │
│  Writes To:       │  │  • Email CTR   │  │  • Replenishment│
│  • acquisition_   │  │                  │  │                  │
│    metrics_daily  │  │  Writes To:    │  │  Writes To:      │
│  • traffic_source_│  │  • consideration│  │  • retention_    │
│    metrics_daily  │  │    _metrics_    │  │    metrics_daily │
│                   │  │    daily        │  │  • customer_     │
│                   │  │  • session_     │  │    retention_    │
│                   │  │    engagement_  │  │    cohorts       │
│                   │  │    daily        │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
                           │
                           ▼
                  ┌──────────────────┐
                  │  ADVOCACY         │
                  │  METRICS          │
                  │                   │
                  │  Reads From:      │
                  │  • customers      │
                  │  • reviews       │
                  │  • referrals     │
                  │  • ugc_submissions│
                  │  • loyalty_       │
                  │    enrollments   │
                  │  • nps_surveys   │
                  │  • shopify_orders│
                  │  • klaviyo_events│
                  │                   │
                  │  Calculates:      │
                  │  • NPS           │
                  │  • Referral Rate │
                  │  • VIP Revenue   │
                  │  • Post-Purchase │
                  │    Email Metrics │
                  │                   │
                  │  Writes To:       │
                  │  • advocacy_      │
                  │    metrics_daily  │
                  └──────────────────┘
```

---

### Key Connection Points Explained

#### 1. Customer ID (Primary Universal Link)
**All metrics connect through `customers.id`:**

```
customers.id
    ├──→ ad_events.customer_id (Acquisition)
    ├──→ shopify_events.customer_id (Consideration)
    ├──→ shopify_orders.customer_id (Retention)
    ├──→ klaviyo_profiles.customer_id (All email metrics)
    ├──→ reviews.customer_id (Advocacy)
    ├──→ referrals.referrer_customer_id (Advocacy)
    ├──→ ugc_submissions.customer_id (Advocacy)
    ├──→ loyalty_enrollments.customer_id (Advocacy)
    └──→ nps_surveys.customer_id (Advocacy)
```

**Why it matters**: Single source of truth for customer identity across all systems.

---

#### 2. Order ID (Revenue Connection)
**Revenue flows through orders:**

```
shopify_orders.id
    ├──→ ad_events.order_id (Acquisition attribution)
    ├──→ shopify_events.order_id (Consideration events)
    ├──→ customers.total_revenue (Retention LTV)
    ├──→ reviews.order_id (Advocacy reviews)
    └──→ nps_surveys.order_id (Advocacy NPS)
```

**Why it matters**: Links acquisition cost to revenue, tracks post-purchase behavior.

---

#### 3. Session ID (Behavioral Connection)
**Sessions track user behavior:**

```
shopify_events.session_id
    ├──→ traffic_source_metrics_daily (Acquisition)
    ├──→ session_engagement_daily (Consideration)
    ├──→ consideration_metrics_daily.total_sessions
    └──→ retention_metrics_daily.repeat_visit_rate_7d
         (same customer, different sessions)
```

**Why it matters**: Tracks user journey, identifies repeat visitors, measures engagement.

---

#### 4. Klaviyo Profile ID (Email Connection)
**Email engagement across all categories:**

```
customers.klaviyo_profile_id
    ↓
klaviyo_profiles.id
    ├──→ klaviyo_events.profile_id
    │       ├──→ Acquisition: Email signup rate
    │       ├──→ Consideration: Email open/click rate
    │       ├──→ Retention: Engagement decay, winback
    │       └──→ Advocacy: Post-purchase email metrics
    │
    └──→ klaviyo_predictive_metrics.profile_id
            └──→ Retention: Reorder probability, churn prediction
```

**Why it matters**: Email is the common thread connecting all customer lifecycle stages.

---

#### 5. Date (Temporal Connection)
**All daily metrics use `date` for time-series analysis:**

```
date
    ├──→ acquisition_metrics_daily.date
    ├──→ consideration_metrics_daily.date
    ├──→ retention_metrics_daily.date
    └──→ advocacy_metrics_daily.date
```

**Why it matters**: Enables trend analysis, cohort comparisons, and historical analysis.

---

### Metric Dependency Chain

```
LEVEL 1: BASE METRICS (from raw data)
├── ad_events (spend, clicks, impressions, conversions)
├── shopify_events (page views, cart adds, checkouts)
├── shopify_orders (revenue, orders, customer_id)
└── klaviyo_events (email opens, clicks, signups)

LEVEL 2: CALCULATED METRICS (from base metrics)
├── Acquisition: CAC, CTR, ROAS
├── Consideration: Add-to-Cart Rate, Bounce Rate, Session Duration
├── Retention: Repeat Purchase Rate, LTV, Churn Rate
└── Advocacy: NPS, Referral Rate, VIP Revenue

LEVEL 3: COMPOSITE METRICS (from multiple categories)
├── LTV:CAC Ratio (Acquisition CAC + Retention LTV)
├── Engagement Score (Consideration + Retention email metrics)
├── VIP Revenue Contribution (Retention LTV + Advocacy VIP identification)
└── Source ROI (Acquisition + Retention + Advocacy)
```

---

### Complete Relationship Map

```
┌─────────────────────────────────────────────────────────────┐
│                    customers (CORE)                          │
│  • id (UUID) - Primary key for all connections              │
│  • total_orders, total_revenue, tags                         │
└─────────────────────────────────────────────────────────────┘
         │
         ├──────────────────────────────────────────────┐
         │                                              │
         ▼                                              ▼
┌────────────────────┐                    ┌────────────────────┐
│ shopify_orders      │                    │ klaviyo_profiles   │
│ • customer_id       │                    │ • customer_id      │
│ • total_price       │                    │ • id               │
│ • order_date        │                    └────────────────────┘
└────────────────────┘                              │
         │                                          │
         ├──────────────────────────┐              │
         │                          │              │
         ▼                          ▼              ▼
┌────────────────────┐    ┌────────────────────┐  ┌────────────────────┐
│ shopify_events      │    │ ad_events          │  │ klaviyo_events     │
│ • customer_id       │    │ • customer_id      │  │ • profile_id       │
│ • order_id          │    │ • order_id         │  │ • campaign_id      │
│ • session_id        │    │ • platform         │  │ • event_type       │
│ • event_type        │    │ • spend, revenue   │  │ • occurred_at      │
│ • event_properties  │    └────────────────────┘  └────────────────────┘
└────────────────────┘              │                      │
         │                          │                      │
         │                          │                      │
    ┌────┴──────────────────────────┼──────────────────────┘
    │                               │
    ▼                               ▼
┌─────────────────────────────────────────────────────────────┐
│              ACQUISITION METRICS SCHEMA                     │
│  • acquisition_metrics_daily                                │
│  • traffic_source_metrics_daily                              │
└─────────────────────────────────────────────────────────────┘
    │                               │
    ▼                               ▼
┌─────────────────────────────────────────────────────────────┐
│            CONSIDERATION METRICS SCHEMA                      │
│  • consideration_metrics_daily                                │
│  • session_engagement_daily                                  │
└─────────────────────────────────────────────────────────────┘
    │                               │
    ▼                               ▼
┌─────────────────────────────────────────────────────────────┐
│              RETENTION METRICS SCHEMA                       │
│  • retention_metrics_daily                                   │
│  • customer_retention_cohorts                                │
└─────────────────────────────────────────────────────────────┘
    │                               │
    └───────────────┬───────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│              ADVOCACY METRICS SCHEMA                        │
│  • advocacy_metrics_daily                                    │
│  • referrals, reviews, ugc_submissions                       │
│  • loyalty_enrollments, nps_surveys                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Query Examples: Cross-Category Analysis

### 1. Complete Customer Journey Analysis
**From acquisition → consideration → retention → advocacy**

```sql
SELECT 
  c.email,
  c.total_orders,
  c.total_revenue as ltv,
  
  -- Acquisition Metrics
  (SELECT SUM(ae.spend) FROM ad_events ae WHERE ae.customer_id = c.id) as acquisition_cost,
  (SELECT COUNT(*) FROM ad_events ae WHERE ae.customer_id = c.id AND ae.event_type = 'conversion') as ad_conversions,
  
  -- Consideration Metrics
  (SELECT COUNT(*) FROM shopify_events se WHERE se.customer_id = c.id AND se.event_type = 'add_to_cart') as cart_adds,
  (SELECT AVG(EXTRACT(EPOCH FROM (MAX(occurred_at) - MIN(occurred_at))))
   FROM shopify_events WHERE customer_id = c.id AND session_id IS NOT NULL
   GROUP BY session_id) as avg_session_duration,
  
  -- Retention Metrics
  CASE WHEN c.total_orders > 1 THEN true ELSE false END as is_repeat_customer,
  (SELECT AVG(predicted_churn_probability) 
   FROM klaviyo_predictive_metrics kpm
   JOIN klaviyo_profiles kp ON kp.id = kpm.profile_id
   WHERE kp.customer_id = c.id) as churn_probability,
  
  -- Advocacy Metrics
  (SELECT COUNT(*) FROM reviews WHERE customer_id = c.id) as reviews_count,
  (SELECT COUNT(*) FROM referrals WHERE referrer_customer_id = c.id) as referrals_made,
  (SELECT loyalty_tier FROM loyalty_enrollments WHERE customer_id = c.id) as loyalty_tier
  
FROM customers c
WHERE c.total_orders > 0
ORDER BY c.total_revenue DESC;
```

---

### 2. LTV:CAC by Acquisition Channel
**Connect acquisition cost to retention value**

```sql
SELECT 
  ae.platform,
  COUNT(DISTINCT ae.customer_id) as customers_acquired,
  SUM(ae.spend) as total_spend,
  SUM(ae.spend) / COUNT(DISTINCT ae.customer_id) as cac,
  
  -- From Retention Metrics
  AVG(c.total_revenue) as avg_ltv,
  AVG(c.total_revenue) / (SUM(ae.spend) / COUNT(DISTINCT ae.customer_id)) as ltv_cac_ratio,
  
  -- From Consideration Metrics (engagement quality)
  (SELECT AVG(avg_session_duration_seconds) 
   FROM consideration_metrics_daily cmd
   JOIN shopify_events se ON se.customer_id = c.id
   WHERE se.occurred_at::date = cmd.date) as avg_engagement,
  
  -- From Advocacy Metrics (advocate potential)
  (SELECT COUNT(*) FROM reviews WHERE customer_id = c.id) as avg_reviews_per_customer
  
FROM ad_events ae
JOIN customers c ON c.id = ae.customer_id
WHERE ae.event_type IN ('conversion', 'purchase')
GROUP BY ae.platform
ORDER BY ltv_cac_ratio DESC;
```

---

### 3. Engagement Score Across All Categories
**Combine consideration engagement with retention and advocacy**

```sql
WITH customer_engagement AS (
  SELECT 
    c.id,
    c.email,
    c.total_orders,
    c.total_revenue,
    
    -- Consideration Engagement
    (SELECT COUNT(*) FROM shopify_events 
     WHERE customer_id = c.id 
     AND event_type IN ('product_viewed', 'add_to_cart')) as engagement_events,
    
    (SELECT AVG(avg_session_duration_seconds) 
     FROM consideration_metrics_daily cmd
     JOIN shopify_events se ON se.customer_id = c.id
     WHERE se.occurred_at::date = cmd.date) as avg_session_duration,
    
    -- Retention Engagement
    (SELECT AVG(email_engagement_probability) 
     FROM klaviyo_predictive_metrics kpm
     JOIN klaviyo_profiles kp ON kp.id = kpm.profile_id
     WHERE kp.customer_id = c.id) as email_engagement_prob,
    
    -- Advocacy Engagement
    (SELECT COUNT(*) FROM reviews WHERE customer_id = c.id) as reviews,
    (SELECT COUNT(*) FROM ugc_submissions WHERE customer_id = c.id) as ugc_count,
    (SELECT COUNT(*) FROM referrals WHERE referrer_customer_id = c.id) as referrals
    
  FROM customers c
  WHERE c.total_orders > 0
)
SELECT 
  *,
  -- Weighted Engagement Score
  (engagement_events * 0.3 + 
   COALESCE(avg_session_duration, 0) * 0.2 + 
   COALESCE(email_engagement_prob, 0) * 100 * 0.2 +
   reviews * 0.1 +
   ugc_count * 0.1 +
   referrals * 0.1) as total_engagement_score
FROM customer_engagement
ORDER BY total_engagement_score DESC;
```

---

### 4. Customer Lifecycle Health Score
**Complete health check across all categories**

```sql
SELECT 
  c.email,
  c.total_orders,
  c.total_revenue,
  
  -- Acquisition Health
  CASE 
    WHEN EXISTS (SELECT 1 FROM ad_events WHERE customer_id = c.id) 
    THEN 'Acquired via Ads'
    ELSE 'Organic'
  END as acquisition_source,
  
  -- Consideration Health
  (SELECT AVG(add_to_cart_rate) 
   FROM consideration_metrics_daily cmd
   JOIN shopify_events se ON se.customer_id = c.id
   WHERE se.occurred_at::date = cmd.date) as avg_add_to_cart_rate,
  
  -- Retention Health
  CASE 
    WHEN c.total_orders > 1 THEN 'Repeat Customer'
    WHEN c.last_order_date >= CURRENT_DATE - INTERVAL '30 days' THEN 'Active'
    WHEN c.last_order_date >= CURRENT_DATE - INTERVAL '90 days' THEN 'At Risk'
    ELSE 'Churned'
  END as retention_status,
  
  -- Advocacy Health
  CASE 
    WHEN EXISTS (SELECT 1 FROM loyalty_enrollments WHERE customer_id = c.id AND loyalty_tier = 'vip')
      OR c.tags @> ARRAY['VIP']
    THEN 'VIP Advocate'
    WHEN EXISTS (SELECT 1 FROM reviews WHERE customer_id = c.id)
      OR EXISTS (SELECT 1 FROM referrals WHERE referrer_customer_id = c.id)
    THEN 'Advocate'
    ELSE 'Regular Customer'
  END as advocacy_status,
  
  -- Overall Health Score
  (CASE WHEN c.total_orders > 1 THEN 30 ELSE 10 END +
   CASE WHEN c.last_order_date >= CURRENT_DATE - INTERVAL '30 days' THEN 30 ELSE 0 END +
   CASE WHEN EXISTS (SELECT 1 FROM reviews WHERE customer_id = c.id) THEN 20 ELSE 0 END +
   CASE WHEN EXISTS (SELECT 1 FROM referrals WHERE referrer_customer_id = c.id) THEN 20 ELSE 0 END) as health_score
  
FROM customers c
WHERE c.total_orders > 0
ORDER BY health_score DESC, c.total_revenue DESC;
```

---

### 5. Revenue Attribution Across Categories
**Track revenue from acquisition through advocacy**

```sql
SELECT 
  -- Acquisition Attribution
  ae.platform as acquisition_channel,
  SUM(ae.spend) as acquisition_cost,
  COUNT(DISTINCT ae.customer_id) as customers_acquired,
  
  -- Consideration Attribution (via traffic source)
  (SELECT COUNT(DISTINCT session_id) 
   FROM shopify_events se
   WHERE se.customer_id = ae.customer_id
   AND se.event_properties->>'referrer' LIKE '%' || ae.platform || '%') as sessions_from_ads,
  
  -- Retention Attribution
  SUM(c.total_revenue) as total_ltv_from_channel,
  AVG(c.total_revenue) as avg_ltv_per_customer,
  
  -- Advocacy Attribution
  (SELECT SUM(so.total_price)
   FROM shopify_orders so
   JOIN customers c2 ON c2.id = so.customer_id
   WHERE c2.id IN (SELECT referred_customer_id FROM referrals WHERE referrer_customer_id = c.id)
   AND so.financial_status = 'paid') as referral_revenue,
   
  -- Final ROI
  (SUM(c.total_revenue) / NULLIF(SUM(ae.spend), 0)) as channel_roi
  
FROM ad_events ae
JOIN customers c ON c.id = ae.customer_id
WHERE ae.event_type IN ('conversion', 'purchase')
GROUP BY ae.platform
ORDER BY channel_roi DESC;
```

---

## Scripts and Automation

### Schema Deployment Scripts
- `scripts/run-schema.ts` - Deploy base e-commerce schema
- `scripts/run-acquisition-schema.ts` - Deploy acquisition metrics
- `scripts/run-consideration-schema.ts` - Deploy consideration metrics
- `scripts/run-retention-schema.ts` - Deploy retention metrics
- `scripts/run-advocacy-schema.ts` - Deploy advocacy metrics

**Usage:**
```bash
npm run schema:run          # Base schema
npm run schema:acquisition  # Acquisition metrics
npm run schema:consideration # Consideration metrics
npm run schema:retention     # Retention metrics
npm run schema:advocacy      # Advocacy metrics
```

### Data Generation Scripts
- `scripts/generate-mock-data.ts` - Generate base e-commerce mock data
- `scripts/generate-advocacy-mock-data.ts` - Generate advocacy-specific mock data

**Usage:**
```bash
npm run data:mock      # Generate base data
npm run data:advocacy   # Generate advocacy data
```

### Metrics Population Scripts
- `scripts/populate-acquisition-metrics.ts` - Populate acquisition metrics
- `scripts/populate-consideration-metrics.ts` - Populate consideration metrics
- `scripts/populate-retention-metrics.ts` - Populate retention metrics
- `scripts/populate-advocacy-metrics.ts` - Populate advocacy metrics

**Usage:**
```bash
npm run metrics:populate              # Acquisition
npm run metrics:consideration:populate # Consideration
npm run metrics:retention:populate     # Retention
npm run metrics:advocacy:populate       # Advocacy
```

### Query Scripts
- `scripts/query-acquisition-metrics.ts` - Query acquisition metrics
- `scripts/query-all-acquisition-metrics.ts` - Comprehensive acquisition queries
- `scripts/query-consideration-metrics.ts` - Query consideration metrics
- `scripts/query-retention-metrics.ts` - Query retention metrics
- `scripts/query-advocacy-metrics.ts` - Query advocacy metrics

**Usage:**
```bash
npm run metrics:acquisition    # Acquisition
npm run metrics:all           # All acquisition (detailed)
npm run metrics:consideration # Consideration
npm run metrics:retention      # Retention
npm run metrics:advocacy       # Advocacy
```

### Utility Scripts
- `scripts/test-db-connection.ts` - Test database connection
- `scripts/verify-data.ts` - Verify data population
- `scripts/check-empty-tables.ts` - Check for empty tables
- `scripts/fill-empty-tables.ts` - Fill empty tables

---

## Deployment and Usage

### Initial Setup

1. **Deploy Base Schema**
   ```bash
   npm run schema:run
   ```

2. **Generate Mock Data**
   ```bash
   npm run data:mock
   npm run data:advocacy
   ```

3. **Deploy All Metric Schemas**
   ```bash
   npm run schema:acquisition
   npm run schema:consideration
   npm run schema:retention
   npm run schema:advocacy
   ```

4. **Populate All Metrics**
   ```bash
   npm run metrics:populate
   npm run metrics:consideration:populate
   npm run metrics:retention:populate
   npm run metrics:advocacy:populate
   ```

5. **Verify Everything**
   ```bash
   npm run data:check
   ```

### Daily Refresh (Recommended)

Set up a cron job or scheduled Lambda to refresh metrics daily:

```sql
-- Refresh all metrics for yesterday
SELECT refresh_acquisition_metrics_daily(CURRENT_DATE - 1);
SELECT refresh_traffic_source_metrics_daily(CURRENT_DATE - 1);
SELECT refresh_consideration_metrics_daily(CURRENT_DATE - 1);
SELECT refresh_session_engagement_daily(CURRENT_DATE - 1);
SELECT refresh_retention_metrics_daily(CURRENT_DATE - 1);
SELECT refresh_customer_retention_cohorts(CURRENT_DATE - 1);
SELECT refresh_advocacy_metrics_daily(CURRENT_DATE - 1);
```

### Querying Metrics

**Individual Categories:**
```bash
npm run metrics:acquisition    # Acquisition metrics
npm run metrics:consideration   # Consideration metrics
npm run metrics:retention       # Retention metrics
npm run metrics:advocacy        # Advocacy metrics
```

**Custom SQL Queries:**
```sql
-- Get all metrics for a customer
SELECT 
  c.email,
  -- Acquisition
  (SELECT calculate_cac('meta', c.first_order_date, CURRENT_DATE)) as cac,
  -- Consideration
  (SELECT calculate_add_to_cart_rate(c.first_order_date, CURRENT_DATE)) as atc_rate,
  -- Retention
  c.total_revenue as ltv,
  (SELECT calculate_repeat_purchase_rate()) as repeat_rate,
  -- Advocacy
  (SELECT calculate_nps()) as nps,
  (SELECT COUNT(*) FROM reviews WHERE customer_id = c.id) as reviews
FROM customers c
WHERE c.total_orders > 0;
```

---

## Summary Statistics

### Database Objects Created

**Total Tables**: 32
- Base schema: 20 tables
- Acquisition metrics: 2 tables
- Consideration metrics: 2 tables
- Retention metrics: 2 tables
- Advocacy metrics: 6 tables

**Total Functions**: 50+
- Base schema: 4 functions
- Acquisition metrics: 11 functions
- Consideration metrics: 11 functions
- Retention metrics: 11 functions
- Advocacy metrics: 9 functions
- Refresh functions: 7 functions

**Total Views**: 15+
- Base schema: 3 views
- Acquisition metrics: 3 views
- Consideration metrics: 2 views
- Retention metrics: 3 views
- Advocacy metrics: 3 views

**Total Metrics**: 44 metrics across 4 categories

### Scripts Created: 25+
- Schema deployment: 5 scripts
- Data generation: 2 scripts
- Metrics population: 4 scripts
- Metrics querying: 5 scripts
- Utilities: 6+ scripts

### Data Currently Populated
- **All 32 tables** have data
- **Daily metrics** populated for key dates
- **Customer cohorts** populated
- **All functions** tested and working

---

## Metric Relationships Summary

### The Complete Customer Lifecycle

```
1. ACQUISITION (How customers find you)
   └──> Metrics: CAC, CTR, ROAS, Traffic Sources
   
2. CONSIDERATION (How customers engage)
   └──> Metrics: Add-to-Cart, Session Duration, Email Engagement
   
3. RETENTION (How customers stay)
   └──> Metrics: Repeat Purchase, LTV, Churn Rate
   
4. ADVOCACY (How customers promote)
   └──> Metrics: NPS, Referrals, Reviews, VIP Revenue
```

### Key Cross-Category Relationships

1. **Acquisition → Retention**: CAC connects to LTV (LTV:CAC ratio)
2. **Consideration → Retention**: Engagement predicts retention
3. **Retention → Advocacy**: Repeat customers become advocates
4. **All → Revenue**: All metrics ultimately connect to revenue

---

## Conclusion

This system provides a **complete e-commerce analytics foundation** with:
- ✅ **44 metrics** covering the entire customer lifecycle
- ✅ **32 tables** properly normalized and populated
- ✅ **50+ functions** for flexible metric calculations
- ✅ **15+ views** for fast aggregated queries
- ✅ **Complete data flow** from acquisition to advocacy
- ✅ **Automated refresh** functions for daily updates
- ✅ **Comprehensive documentation** for all metrics

All metrics are **properly connected** through shared customer IDs, order IDs, session IDs, and dates, enabling comprehensive cross-category analysis and reporting.

