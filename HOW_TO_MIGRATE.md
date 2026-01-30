# How to Migrate This Project to Your Own Supabase

This guide walks you through deploying the complete e-commerce data warehouse to your own Supabase instance, including the schema and all sample data.

## 📋 What You'll Get

- **32 database tables** - Complete e-commerce schema
- **2,662 rows of sample data** - Real customers, orders, products, metrics
- **44 pre-computed metrics** - Acquisition, Consideration, Retention, Advocacy
- **Ready-to-query data warehouse** - Start analyzing immediately

---

## 🚀 Quick Start (5 Minutes)

### Prerequisites

- A [Supabase](https://supabase.com) account (free tier works!)
- [Node.js 18+](https://nodejs.org/) installed
- [Git](https://git-scm.com/) installed

### Step 1: Clone the Repository

```bash
git clone https://github.com/Payal2000/ai-marketing-backend.git
cd ai-marketing-backend
git checkout data
```

### Step 2: Install Dependencies

```bash
npm install
```

This will install all required packages including TypeScript, PostgreSQL client, and deployment tools.

### Step 3: Create Your Supabase Project

1. Go to [supabase.com/dashboard](https://supabase.com/dashboard)
2. Click **"New Project"**
3. Fill in the details:
   - **Name**: Your project name (e.g., "ecommerce-analytics")
   - **Database Password**: Create a strong password (save this!)
   - **Region**: Choose the closest region to you
4. Click **"Create new project"**
5. Wait 2-3 minutes for provisioning

### Step 4: Get Your Database Credentials

1. In your Supabase dashboard, click **Settings** (gear icon)
2. Go to **Database** in the left menu
3. Scroll to **Connection string** section
4. Copy the **URI** format connection string (looks like this):
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.xxxxx.supabase.co:5432/postgres
   ```
5. Replace `[YOUR-PASSWORD]` with your actual database password

### Step 5: Configure Your Environment

```bash
# Copy the example environment file
cp .env.example .env

# Edit the .env file
nano .env
# Or use your favorite editor: code .env, vim .env, etc.
```

Update these lines in `.env`:

```env
# Replace with your actual connection string
SUPABASE_DB_URL=postgresql://postgres:YOUR_PASSWORD@db.YOUR_PROJECT_REF.supabase.co:5432/postgres

# Replace with your project URL
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co

# Replace with your keys (from Supabase Dashboard > Settings > API)
SUPABASE_ANON_KEY=your-anon-key-here
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
```

**Where to find these:**
- **Project URL & API Keys**: Supabase Dashboard → Settings → API
- **Database URL**: Supabase Dashboard → Settings → Database → Connection string

### Step 6: Deploy the Database Schema

```bash
npm run deploy:supabase
```

This will:
- Connect to your Supabase database
- Install required PostgreSQL extensions (pgcrypto, vector, pg_trgm)
- Create all 32 tables
- Set up indexes and relationships
- Create SQL functions for metrics
- Create materialized views

**Expected output:**
```
🚀 Starting deployment to Supabase...
🔌 Testing database connection...
✅ Connected successfully!
📦 Installing extensions...
✅ Extensions installed
📝 Found 5 migrations:
   1. 20260130000001_ecommerce_base.sql
   2. 20260130000002_acquisition_metrics.sql
   3. 20260130000003_consideration_metrics.sql
   4. 20260130000004_retention_metrics.sql
   5. 20260130000005_advocacy_metrics.sql
⏳ Applying migrations...
✅ All migrations applied successfully!
```

### Step 7: Import the Sample Data

```bash
npm run data:import
```

This will:
- Load 2,662 rows of sample data
- Populate all tables with realistic e-commerce data
- Refresh materialized views

**Expected output:**
```
🚀 Starting data import to Supabase...
🔌 Connecting to database...
✅ Connected!
📖 Reading data file...
✅ Loaded 1564.75 KB
⏳ Importing data (this may take a while)...
✅ Import complete!

📊 Total rows imported: 2662
🎉 Data import successful!
```

---

## ✅ Verify Your Migration

### Check in Supabase Dashboard

1. Go to your Supabase dashboard
2. Click **Table Editor** (database icon in left menu)
3. You should see all 32 tables
4. Click on `customers` - you should see 20 customers
5. Click on `shopify_orders` - you should see 63 orders

### Query Sample Data

Run these queries in the **SQL Editor**:

```sql
-- View all tables
SELECT table_name,
       (SELECT COUNT(*) FROM information_schema.columns
        WHERE columns.table_name = tables.table_name) as columns
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Check customer count
SELECT COUNT(*) as customer_count FROM customers;

-- Check order count
SELECT COUNT(*) as order_count FROM shopify_orders;

-- View acquisition metrics
SELECT * FROM mv_acquisition_metrics
ORDER BY date_day DESC
LIMIT 10;

-- View recent orders
SELECT
  o.order_number,
  c.email,
  o.total_price,
  o.order_date
FROM shopify_orders o
JOIN customers c ON o.customer_id = c.id
ORDER BY o.order_date DESC
LIMIT 10;
```

---

## 📊 Explore Your Data

### Using the TypeScript Scripts

The project includes several scripts to query metrics:

```bash
# Query all acquisition metrics
npm run metrics:acquisition

# Query consideration metrics
npm run metrics:consideration

# Query retention metrics
npm run metrics:retention

# Query advocacy metrics
npm run metrics:advocacy

# Query all metrics at once
npm run metrics:all
```

### Sample Queries You Can Run

**Customer Analysis:**
```sql
SELECT
  COUNT(*) as total_customers,
  AVG(total_revenue) as avg_customer_value,
  SUM(total_revenue) as total_revenue
FROM customers;
```

**Product Performance:**
```sql
SELECT
  p.title,
  COUNT(DISTINCT oli.order_id) as orders,
  SUM(oli.quantity) as units_sold,
  SUM(oli.total_price) as revenue
FROM shopify_products p
JOIN shopify_product_variants pv ON p.id = pv.product_id
JOIN shopify_order_line_items oli ON pv.id = oli.variant_id
GROUP BY p.id, p.title
ORDER BY revenue DESC;
```

**Daily Metrics:**
```sql
SELECT
  date_day,
  cac_blended,
  roas_blended,
  revenue,
  orders
FROM mv_acquisition_metrics
WHERE date_day >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY date_day DESC;
```

---

## 🔄 Generate Additional Data (Optional)

If you want more sample data:

```bash
# Generate mock data for all tables
npm run data:mock

# Populate metrics with new calculations
npm run metrics:acquisition
npm run metrics:consideration
npm run metrics:retention
npm run metrics:advocacy
```

---

## 🐛 Troubleshooting

### "SUPABASE_DB_URL not found"

**Problem:** Environment variables not loaded

**Solution:**
1. Make sure you created the `.env` file
2. Verify it's in the root directory
3. Check that `SUPABASE_DB_URL` is set correctly

### "Connection refused" or "timeout"

**Problem:** Database connection issues

**Solution:**
1. Verify your database password is correct
2. Check the project reference in the URL
3. Make sure your Supabase project is running (not paused)
4. Try removing `?sslmode=require` from the connection string

### "Permission denied" or "relation does not exist"

**Problem:** Schema not deployed

**Solution:**
1. Run `npm run deploy:supabase` first
2. Check Supabase logs for errors
3. Verify you have admin permissions on the database

### "extension vector does not exist"

**Problem:** pgvector extension not available

**Solution:**
1. Contact Supabase support to enable pgvector
2. Or comment out vector-related code in migrations

### Data import fails with constraint errors

**Problem:** Data already exists or schema mismatch

**Solution:**
1. Drop all tables and re-run: `npm run deploy:supabase`
2. Or manually truncate tables before import

---

## 📚 Next Steps

Once your migration is complete:

1. **Connect Your Data Sources**
   - Integrate with Shopify API
   - Connect Klaviyo for email marketing
   - Link advertising platforms (Meta, Google, TikTok)

2. **Build Dashboards**
   - Use Supabase's built-in charts
   - Connect to Metabase, Grafana, or Tableau
   - Build custom dashboards with your framework

3. **Set Up Automated Refreshes**
   - Configure pg_cron for daily metric updates
   - Set up GitHub Actions for data syncing
   - Schedule ETL jobs

4. **Customize the Schema**
   - Add your own tables
   - Create custom metrics
   - Modify existing calculations

5. **Deploy to Production**
   - Set up staging and production databases
   - Configure backups
   - Enable Row Level Security (RLS)
   - Set up monitoring

---

## 🔐 Security Best Practices

Before going to production:

- [ ] Never commit `.env` file to git
- [ ] Use environment variables for all secrets
- [ ] Enable Row Level Security (RLS) on tables
- [ ] Restrict database access to specific IPs
- [ ] Use the `anon` key for client-side access only
- [ ] Keep `service_role` key secret (server-side only)
- [ ] Enable database backups in Supabase dashboard
- [ ] Set up SSL/TLS for all connections
- [ ] Monitor for unusual database activity

---

## 💰 Cost Estimates

### Supabase Free Tier
- Database: 500 MB storage
- Bandwidth: 5 GB egress
- API Requests: Unlimited
- **Cost:** $0/month
- **Good for:** Testing, small projects

### Supabase Pro
- Database: 8 GB storage
- Bandwidth: 250 GB egress
- Better performance
- **Cost:** $25/month
- **Good for:** Growing applications

### Supabase Team
- Database: 100 GB+ storage
- Bandwidth: 500 GB+ egress
- Enterprise features
- **Cost:** $599/month
- **Good for:** Production applications

---

## 🆘 Need Help?

- **Documentation:** [Full project docs](./COMPREHENSIVE_SYSTEM_DOCUMENTATION.md)
- **Deployment Guide:** [DEPLOYMENT.md](./DEPLOYMENT.md)
- **Metrics Guide:** [db/METRICS_DOCUMENTATION.md](./db/METRICS_DOCUMENTATION.md)
- **GitHub Issues:** [Report a problem](https://github.com/Payal2000/ai-marketing-backend/issues)
- **Supabase Docs:** [supabase.com/docs](https://supabase.com/docs)

---

## 🎉 Success!

You now have a fully functional e-commerce data warehouse running on Supabase!

Your database includes:
- ✅ Complete schema with 32 tables
- ✅ Sample data (2,662 rows)
- ✅ Pre-computed metrics
- ✅ Working SQL functions
- ✅ Materialized views for fast queries

Start exploring your data and building amazing analytics! 🚀
