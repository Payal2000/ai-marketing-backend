# 🚀 Deployment Guide - E-Commerce Data Warehouse

This guide will help you deploy the complete e-commerce analytics data warehouse to your own Supabase instance.

## What You'll Get

- **32 Database Tables** - Full e-commerce schema
- **44 Pre-computed Metrics** - Acquisition, Consideration, Retention, Advocacy
- **50+ SQL Functions** - On-demand metric calculations
- **15+ Materialized Views** - Fast aggregated queries
- **Automated Refresh Jobs** - Daily metric updates

## Prerequisites

- A Supabase account (free tier works)
- Node.js 18+ installed
- Git installed
- (Optional) API keys for Shopify, Klaviyo, Meta, Google Ads

---

## 🎯 Quick Start (5 minutes)

### Step 1: Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign in
2. Click **"New Project"**
3. Enter:
   - **Name**: `ecommerce-analytics` (or your choice)
   - **Database Password**: Save this securely!
   - **Region**: Choose closest to you
4. Wait 2-3 minutes for provisioning

### Step 2: Get Your Database Connection String

1. In your Supabase project dashboard, go to **Settings** (gear icon) → **Database**
2. Scroll to **Connection string** section
3. Copy the **URI** format:
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres
   ```
4. Replace `[YOUR-PASSWORD]` with your actual database password

### Step 3: Clone This Repository

```bash
git clone https://github.com/Payal2000/ai-marketing-backend.git
cd ai-marketing-backend
```

### Step 4: Apply Database Migrations

#### Option A: Using Supabase CLI (Recommended)

```bash
# Install Supabase CLI
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project (get PROJECT_REF from your dashboard URL)
supabase link --project-ref YOUR_PROJECT_REF

# Push all migrations to your database
supabase db push
```

#### Option B: Manual SQL Execution

1. Open your Supabase project dashboard
2. Go to **SQL Editor** (left sidebar)
3. Create a new query and run each file in order:

   **a) Extensions:**
   ```sql
   -- Copy/paste contents of supabase/extensions.sql
   ```

   **b) Base Schema:**
   ```sql
   -- Copy/paste contents of supabase/migrations/20260130000001_ecommerce_base.sql
   ```

   **c) Acquisition Metrics:**
   ```sql
   -- Copy/paste contents of supabase/migrations/20260130000002_acquisition_metrics.sql
   ```

   **d) Consideration Metrics:**
   ```sql
   -- Copy/paste contents of supabase/migrations/20260130000003_consideration_metrics.sql
   ```

   **e) Retention Metrics:**
   ```sql
   -- Copy/paste contents of supabase/migrations/20260130000004_retention_metrics.sql
   ```

   **f) Advocacy Metrics:**
   ```sql
   -- Copy/paste contents of supabase/migrations/20260130000005_advocacy_metrics.sql
   ```

### Step 5: Verify Installation

Run this query in the SQL Editor:

```sql
-- Check all tables exist
SELECT
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns WHERE columns.table_name = tables.table_name) as column_count
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Check materialized views
SELECT matviewname
FROM pg_matviews
WHERE schemaname = 'public'
ORDER BY matviewname;

-- Check functions exist
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_type = 'FUNCTION'
ORDER BY routine_name;
```

Expected results:
- **32+ tables** including: customers, shopify_orders, klaviyo_campaigns, meta_ad_spend, etc.
- **15+ materialized views** for each metric category
- **50+ functions** for metric calculations

---

## 📊 Generate Sample Data (Optional)

Want to test with sample data before connecting real data sources?

```bash
# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Edit .env and add your SUPABASE_DB_URL
nano .env

# Generate mock data
npm run data:mock

# Populate all metrics
npm run metrics:acquisition
npm run metrics:consideration
npm run metrics:retention
npm run metrics:advocacy

# Query sample metrics
npm run metrics:all
```

---

## 🔗 Connect Your Data Sources

### Shopify Integration

1. In Shopify Admin, go to **Apps** → **Develop apps**
2. Create a new app with these permissions:
   - `read_orders`
   - `read_products`
   - `read_customers`
3. Install the app and copy the **Access Token**
4. Use the TypeScript scripts in `scripts/` to sync data

### Klaviyo Integration

1. Go to Klaviyo **Settings** → **API Keys**
2. Create a new **Private API Key**
3. Use scripts in `scripts/` to pull campaign and email data

### Advertising Platforms

- **Meta Ads**: Set up Facebook Business API access
- **Google Ads**: Enable Google Ads API and get credentials
- **TikTok/Pinterest**: Follow platform-specific API documentation

---

## 🔄 Set Up Automated Refreshes

The data warehouse includes materialized views that should be refreshed regularly.

### Option 1: Supabase pg_cron (Built-in)

Run this in SQL Editor to set up daily refreshes:

```sql
-- Enable pg_cron extension (may need Supabase support for this)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Refresh acquisition metrics daily at 2 AM UTC
SELECT cron.schedule(
  'refresh-acquisition-metrics',
  '0 2 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_acquisition_metrics$$
);

-- Refresh consideration metrics
SELECT cron.schedule(
  'refresh-consideration-metrics',
  '0 2 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_consideration_metrics$$
);

-- Refresh retention metrics
SELECT cron.schedule(
  'refresh-retention-metrics',
  '0 2 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_retention_metrics$$
);

-- Refresh advocacy metrics
SELECT cron.schedule(
  'refresh-advocacy-metrics',
  '0 2 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_advocacy_metrics$$
);
```

### Option 2: GitHub Actions

Create `.github/workflows/refresh-metrics.yml`:

```yaml
name: Refresh Metrics

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
  workflow_dispatch:

jobs:
  refresh:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '18'
      - run: npm install
      - name: Refresh all metrics
        run: |
          npm run metrics:acquisition
          npm run metrics:consideration
          npm run metrics:retention
          npm run metrics:advocacy
        env:
          SUPABASE_DB_URL: ${{ secrets.SUPABASE_DB_URL }}
```

Add `SUPABASE_DB_URL` in **Repository Settings** → **Secrets and variables** → **Actions**.

---

## 📈 Query Your Metrics

### Using SQL Editor (Supabase Dashboard)

```sql
-- View all acquisition metrics
SELECT * FROM mv_acquisition_metrics
ORDER BY date_day DESC
LIMIT 30;

-- Get current CAC
SELECT date_day, cac_blended
FROM mv_acquisition_metrics
WHERE date_day >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date_day DESC;

-- Get customer LTV
SELECT * FROM mv_retention_metrics
WHERE date_day >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY date_day DESC;

-- Get NPS scores
SELECT * FROM mv_advocacy_metrics
WHERE date_day >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date_day DESC;
```

### Using the API (From Your App)

```typescript
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://xxxxx.supabase.co',
  'your-anon-key'
)

// Query metrics
const { data, error } = await supabase
  .from('mv_acquisition_metrics')
  .select('*')
  .order('date_day', { ascending: false })
  .limit(30)
```

---

## 🔐 Security Setup

### Row Level Security (RLS)

By default, tables are accessible to authenticated users. To restrict access:

```sql
-- Enable RLS on tables
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE shopify_orders ENABLE ROW LEVEL SECURITY;

-- Example: Allow only authenticated users to read
CREATE POLICY "Allow authenticated read access"
  ON customers
  FOR SELECT
  TO authenticated
  USING (true);
```

### API Keys

1. In Supabase dashboard, go to **Settings** → **API**
2. Copy your:
   - **Project URL**
   - **anon/public key** (for client-side)
   - **service_role key** (for server-side, keep secret!)

---

## 📁 Project Structure After Deployment

```
supabase/
├── extensions.sql                                    # PostgreSQL extensions
├── config.toml                                       # Supabase config
├── migrations/
│   ├── 20260130000001_ecommerce_base.sql            # Core tables
│   ├── 20260130000002_acquisition_metrics.sql       # CAC, ROAS, etc.
│   ├── 20260130000003_consideration_metrics.sql     # Cart, sessions, etc.
│   ├── 20260130000004_retention_metrics.sql         # LTV, churn, etc.
│   └── 20260130000005_advocacy_metrics.sql          # NPS, referrals, etc.
```

---

## 💰 Cost Estimates

### Supabase Free Tier (Generous!)
- **Database**: 500 MB storage
- **Bandwidth**: 5 GB egress
- **API Requests**: Unlimited
- **Ideal for**: Testing, small stores (<10K orders/month)

### Supabase Pro ($25/month)
- **Database**: 8 GB storage
- **Bandwidth**: 250 GB egress
- **Better performance**
- **Ideal for**: Growing stores (10K-100K orders/month)

### Supabase Team ($599/month)
- **Database**: 100 GB storage
- **Bandwidth**: 500 GB egress
- **Ideal for**: Large stores (>100K orders/month)

---

## 🐛 Troubleshooting

### "permission denied for schema public"
```sql
-- Run as postgres user
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO authenticated;
```

### "extension vector does not exist"
Contact Supabase support to enable pgvector extension.

### "relation already exists"
Migrations are idempotent (`CREATE TABLE IF NOT EXISTS`), so you can safely re-run them.

### Slow queries
```sql
-- Refresh materialized views
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_acquisition_metrics;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_consideration_metrics;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_retention_metrics;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_advocacy_metrics;
```

---

## 📚 Additional Documentation

- **[README.md](README.md)** - Project overview and metrics
- **[SETUP.md](SETUP.md)** - Local development setup
- **[db/METRICS_DOCUMENTATION.md](db/METRICS_DOCUMENTATION.md)** - Detailed metric definitions
- **[COMPREHENSIVE_SYSTEM_DOCUMENTATION.md](COMPREHENSIVE_SYSTEM_DOCUMENTATION.md)** - Full system docs

---

## ✅ Pre-Launch Checklist

Before sharing this project:

- [ ] Test all migrations apply successfully
- [ ] Generate sample data and verify metrics calculate correctly
- [ ] Set up RLS policies if needed
- [ ] Configure automated metric refreshes
- [ ] Document your API integration approach
- [ ] Add monitoring/alerting for failed jobs
- [ ] Back up your database regularly
- [ ] Test disaster recovery procedure

---

## 🤝 Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review Supabase logs in the dashboard
3. Open an issue on GitHub
4. Check [Supabase documentation](https://supabase.com/docs)

---

## 🎉 You're Done!

Your e-commerce data warehouse is now deployed. Next steps:

1. Connect your Shopify, Klaviyo, and ad platform data sources
2. Set up automated data syncing
3. Build dashboards on top of the metrics
4. Share insights with your team!

Happy analyzing! 📊
