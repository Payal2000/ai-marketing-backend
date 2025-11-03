import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function verifyData() {
  try {
    console.log("🔍 Verifying mock data...\n");

    // Check customer metrics view
    console.log("📊 Customer Lifetime Metrics (sample):");
    const customers = await pool.query(`
      SELECT * FROM customer_lifetime_metrics 
      ORDER BY total_revenue DESC 
      LIMIT 5
    `);
    customers.rows.forEach((row, i) => {
      const revenue = parseFloat(row.total_revenue || 0);
      console.log(`   ${i + 1}. ${row.email}: ${row.total_orders} orders, $${revenue.toFixed(2)} revenue, ${row.is_repeat_customer ? 'Repeat' : 'First-time'} customer`);
    });

    // Check campaign performance
    console.log("\n📧 Campaign Performance (sample):");
    const campaigns = await pool.query(`
      SELECT name, type, recipients_count, 
             ROUND(open_rate * 100, 2) as open_rate_pct,
             ROUND(click_rate * 100, 2) as click_rate_pct,
             revenue
      FROM campaign_performance_summary 
      LIMIT 5
    `);
    campaigns.rows.forEach((row, i) => {
      const revenue = parseFloat(row.revenue || 0);
      console.log(`   ${i + 1}. ${row.name} (${row.type}): ${row.recipients_count} sent, ${row.open_rate_pct}% open, ${row.click_rate_pct}% click, $${revenue.toFixed(2)} revenue`);
    });

    // Check product performance
    console.log("\n🛍️  Product Performance (sample):");
    const products = await pool.query(`
      SELECT title, total_units_sold, total_revenue, 
             ROUND(conversion_rate * 100, 2) as conversion_rate_pct
      FROM product_performance_summary 
      ORDER BY total_revenue DESC 
      LIMIT 5
    `);
    products.rows.forEach((row, i) => {
      const revenue = parseFloat(row.total_revenue || 0);
      console.log(`   ${i + 1}. ${row.title}: ${row.total_units_sold || 0} sold, $${revenue.toFixed(2)} revenue, ${row.conversion_rate_pct || 0}% conversion`);
    });

    // Check orders by source
    console.log("\n📦 Orders by Source:");
    const ordersBySource = await pool.query(`
      SELECT source, COUNT(*) as count, SUM(total_price) as revenue
      FROM shopify_orders
      WHERE financial_status = 'paid'
      GROUP BY source
    `);
    ordersBySource.rows.forEach((row) => {
      console.log(`   ${row.source}: ${row.count} orders, $${parseFloat(row.revenue).toFixed(2)} revenue`);
    });

    // Check ad platform performance
    console.log("\n📱 Ad Platform Performance:");
    const adPerformance = await pool.query(`
      SELECT platform, 
             SUM(spend) as total_spend,
             SUM(revenue) as total_revenue,
             CASE WHEN SUM(spend) > 0 THEN SUM(revenue) / SUM(spend) ELSE 0 END as roas
      FROM ad_events
      GROUP BY platform
    `);
    adPerformance.rows.forEach((row) => {
      console.log(`   ${row.platform}: $${parseFloat(row.total_spend).toFixed(2)} spend, $${parseFloat(row.total_revenue).toFixed(2)} revenue, ROAS: ${parseFloat(row.roas).toFixed(2)}x`);
    });

    // Check churn risk customers
    console.log("\n⚠️  High Churn Risk Customers (>70% probability):");
    const churnRisk = await pool.query(`
      SELECT kp.email, 
             kpm.predicted_churn_probability,
             kpm.predicted_lifetime_value,
             kpm.predicted_next_order_date
      FROM klaviyo_predictive_metrics kpm
      JOIN klaviyo_profiles kp ON kp.id = kpm.profile_id
      WHERE kpm.predicted_churn_probability > 0.7
      ORDER BY kpm.predicted_churn_probability DESC
      LIMIT 5
    `);
    if (churnRisk.rows.length > 0) {
    churnRisk.rows.forEach((row, i) => {
      const churnProb = parseFloat(row.predicted_churn_probability || 0);
      const pltv = parseFloat(row.predicted_lifetime_value || 0);
      console.log(`   ${i + 1}. ${row.email}: ${(churnProb * 100).toFixed(1)}% churn risk, PLTV: $${pltv.toFixed(2)}`);
    });
    } else {
      console.log("   No high churn risk customers found");
    }

    await pool.end();
    console.log("\n✅ Data verification complete!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

verifyData();

