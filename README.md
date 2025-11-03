# AI Marketing Backend - E-Commerce Data Warehouse

A comprehensive PostgreSQL data warehouse for e-commerce analytics with **44 metrics across 4 categories** covering the complete customer lifecycle from acquisition to advocacy.

[![TypeScript](https://img.shields.io/badge/TypeScript-5.6-blue)](https://www.typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Node.js-20.x-green)](https://nodejs.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-blue)](https://www.postgresql.org/)
[![Serverless](https://img.shields.io/badge/Serverless-Framework-orange)](https://www.serverless.com/)

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Metrics Categories](#metrics-categories)
- [Project Structure](#project-structure)
- [Documentation](#documentation)
- [Scripts](#scripts)
- [Deployment](#deployment)
- [Contributing](#contributing)

## 🎯 Overview

This project provides a complete e-commerce analytics data warehouse that integrates:
- **Shopify** - Order data, products, customer data, store events
- **Klaviyo** - Email marketing, campaigns, flows, predictive analytics
- **Advertising Platforms** - Meta, Google, TikTok, Pinterest (ad spend, conversions, ROAS)

The system pre-computes and stores **44 key metrics** across 4 categories:
1. **Acquisition Metrics** - How customers find you (CAC, CTR, ROAS, etc.)
2. **Consideration Metrics** - How customers engage (Add-to-Cart, Session Duration, etc.)
3. **Retention Metrics** - How customers stay (Repeat Purchase, LTV, Churn, etc.)
4. **Advocacy Metrics** - How customers promote (NPS, Referrals, Reviews, etc.)

## ✨ Features

- ✅ **32 Database Tables** - Fully normalized schema with proper relationships
- ✅ **50+ SQL Functions** - On-demand metric calculations
- ✅ **15+ Materialized Views** - Fast aggregated queries
- ✅ **Automated Daily Refresh** - Pre-computed metrics for performance
- ✅ **Complete Customer Journey** - Track from first touch to advocacy
- ✅ **Cross-Category Analysis** - Metrics connected across all categories
- ✅ **TypeScript Scripts** - Data generation, population, and querying
- ✅ **Serverless Ready** - AWS Lambda deployment configuration

## 🏗️ Architecture

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
                  └──────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Node.js 20.x or higher
- PostgreSQL 15+ (or Supabase)
- npm or yarn

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Payal2000/ai-marketing-backend.git
   cd ai-marketing-backend
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your credentials
   ```

4. **Test database connection**
   ```bash
   npm run test:db
   ```

5. **Deploy base schema**
   ```bash
   npm run schema:run
   ```

6. **Generate mock data**
   ```bash
   npm run data:mock
   npm run data:advocacy
   ```

7. **Deploy metric schemas**
   ```bash
   npm run schema:acquisition
   npm run schema:consideration
   npm run schema:retention
   npm run schema:advocacy
   ```

8. **Populate metrics**
   ```bash
   npm run metrics:populate
   npm run metrics:consideration:populate
   npm run metrics:retention:populate
   npm run metrics:advocacy:populate
   ```

9. **Query metrics**
   ```bash
   npm run metrics:acquisition
   npm run metrics:consideration
   npm run metrics:retention
   npm run metrics:advocacy
   ```

## 📊 Metrics Categories

### 1. Acquisition Metrics (13 metrics)
Measure traffic efficiency and acquisition cost.

- Customer Acquisition Cost (CAC)
- Click-Through Rate (CTR)
- Conversion Rate (CVR)
- Cost per Click (CPC)
- Cost per Impression (CPM)
- Return on Ad Spend (ROAS)
- Traffic by Source/Channel
- New Users / First-Time Visitors
- Email Sign-up Rate
- Cost per Signup / Lead
- Session-to-Signup Ratio
- Bounce Rate
- Source ROI (LTV:CAC ratio by channel)

### 2. Consideration Metrics (12 metrics)
Identify intent, engagement, and drop-offs before purchase.

- Add-to-Cart Rate
- View-to-Add-to-Cart Ratio
- Product View Depth (avg pages per session)
- Time on Site / Session Duration
- Scroll Depth %
- Wishlist Add Rate
- Cart Abandonment Rate (pre-checkout)
- Product Page Bounce Rate
- Email Open Rate (from Klaviyo)
- Email Click-Through Rate
- Engagement Score (weighted across site + email)
- % of Sessions with Repeat Visits in 7 Days

### 3. Retention Metrics (11 metrics)
Measure loyalty, repeat behavior, and churn risk.

- Repeat Purchase Rate
- Time Between Purchases (Days)
- Customer Lifetime Value (LTV)
- Active Customer % (purchased in last X days)
- Churn Rate (% inactive after X days)
- Reorder Probability (Klaviyo prediction)
- Subscription Retention Rate (if applicable)
- Engagement Decay Rate (email inactivity trend)
- Winback Email Open Rate
- Replenishment Timing Accuracy
- CLV:CAC Ratio

### 4. Advocacy / Loyalty Metrics (8 metrics)
Identify brand promoters and referral opportunities.

- Net Promoter Score (NPS)
- Referral Conversion Rate
- UGC Submission Rate
- Review Participation Rate
- Loyalty Program Participation Rate
- VIP Segment Revenue Contribution
- Post-Purchase Email Open/Click Rate
- Social Engagement Rate (if integrated later)

## 📁 Project Structure

```
ai-marketing-backend/
├── db/                          # Database schemas
│   ├── ecommerce_schema.sql     # Base e-commerce schema
│   ├── acquisition_metrics_schema.sql
│   ├── consideration_metrics_schema.sql
│   ├── retention_metrics_schema.sql
│   ├── advocacy_metrics_schema.sql
│   └── README.md                # Database documentation
├── scripts/                      # TypeScript scripts
│   ├── run-*-schema.ts          # Schema deployment
│   ├── generate-*-data.ts      # Data generation
│   ├── populate-*-metrics.ts   # Metrics population
│   └── query-*-metrics.ts      # Metrics querying
├── functions/                   # AWS Lambda functions
│   └── poller/                  # Email polling Lambda
├── src/                         # Source code
│   ├── clients/                 # API clients (Gmail, OpenAI, DB)
│   ├── rag/                     # RAG implementation
│   └── utils/                   # Utilities
├── infra/                       # Infrastructure configs
├── COMPREHENSIVE_SYSTEM_DOCUMENTATION.md  # Complete docs
├── SETUP.md                     # Setup instructions
└── package.json
```

## 📚 Documentation

- **[COMPREHENSIVE_SYSTEM_DOCUMENTATION.md](./COMPREHENSIVE_SYSTEM_DOCUMENTATION.md)** - Complete system documentation with all metrics, connections, and query examples
- **[SETUP.md](./SETUP.md)** - Detailed setup instructions
- **[db/README.md](./db/README.md)** - Database schema documentation
- **[db/METRICS_DOCUMENTATION.md](./db/METRICS_DOCUMENTATION.md)** - Detailed metrics documentation

### Implementation Docs

- [Acquisition Metrics](./ACQUISITION_METRICS_IMPLEMENTATION.md)
- [Consideration Metrics](./CONSIDERATION_METRICS_IMPLEMENTATION.md)
- [Retention Metrics](./RETENTION_METRICS_IMPLEMENTATION.md)
- [Advocacy Metrics](./ADVOCACY_METRICS_IMPLEMENTATION.md)

## 🛠️ Scripts

### Schema Deployment
```bash
npm run schema:run          # Base e-commerce schema
npm run schema:acquisition  # Acquisition metrics
npm run schema:consideration # Consideration metrics
npm run schema:retention     # Retention metrics
npm run schema:advocacy      # Advocacy metrics
```

### Data Generation
```bash
npm run data:mock          # Generate base mock data
npm run data:advocacy       # Generate advocacy mock data
npm run data:verify         # Verify data population
npm run data:check          # Check for empty tables
npm run data:fill           # Fill empty tables
```

### Metrics Population
```bash
npm run metrics:populate              # Acquisition metrics
npm run metrics:consideration:populate # Consideration metrics
npm run metrics:retention:populate     # Retention metrics
npm run metrics:advocacy:populate       # Advocacy metrics
```

### Metrics Querying
```bash
npm run metrics:acquisition    # Query acquisition metrics
npm run metrics:all           # All acquisition metrics (detailed)
npm run metrics:consideration # Query consideration metrics
npm run metrics:retention      # Query retention metrics
npm run metrics:advocacy       # Query advocacy metrics
```

### Utilities
```bash
npm run test:db              # Test database connection
npm run start:local          # Run Lambda locally
npm run build                 # Build for deployment
npm run deploy                # Deploy to AWS
```

## 🚢 Deployment

### AWS Lambda Deployment

1. **Configure AWS credentials**
   ```bash
   aws configure
   ```

2. **Set environment variables in `.env`**
   - Gmail OAuth credentials
   - OpenAI API key
   - Supabase database URL

3. **Deploy**
   ```bash
   npm run deploy
   ```

For detailed deployment instructions, see [SETUP.md](./SETUP.md).

## 📈 Usage Examples

### Query All Metrics for a Customer

```sql
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
  (SELECT calculate_nps()) as nps
FROM customers c
WHERE c.total_orders > 0;
```

### Cross-Category Analysis

See [COMPREHENSIVE_SYSTEM_DOCUMENTATION.md](./COMPREHENSIVE_SYSTEM_DOCUMENTATION.md) for complete query examples.

## 🔗 Key Connections

All metrics connect through:
- **Customer ID** - Primary universal link
- **Order ID** - Revenue connection
- **Session ID** - Behavioral connection
- **Klaviyo Profile ID** - Email connection
- **Date** - Temporal connection

## 📊 Database Statistics

- **32 Tables** - All populated with data
- **50+ Functions** - For metric calculations
- **15+ Views** - For fast aggregated queries
- **44 Metrics** - Across 4 categories

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is private and proprietary.

## 🔗 Links

- [GitHub Repository](https://github.com/Payal2000/ai-marketing-backend)
- [Comprehensive Documentation](./COMPREHENSIVE_SYSTEM_DOCUMENTATION.md)
- [Setup Guide](./SETUP.md)



