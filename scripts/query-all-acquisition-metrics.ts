import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function queryAllMetrics() {
  try {
    console.log("📊 All Acquisition Metrics\n");

    // 1. Acquisition Metrics Summary by Platform
    console.log("1️⃣ Acquisition Metrics Summary by Platform:");
    const summary = await pool.query(`
      SELECT * FROM acquisition_metrics_summary
      ORDER BY total_revenue DESC
    `);
    summary.rows.forEach((row, i) => {
      const cpc = parseFloat(row.avg_cpc || 0);
      const ctr = parseFloat(row.avg_ctr || 0) * 100;
      const roas = parseFloat(row.avg_roas || 0);
      const cac = parseFloat(row.avg_cac || 0);
      console.log(`   ${i + 1}. ${row.platform}:`);
      console.log(`      Spend: $${parseFloat(row.total_spend || 0).toFixed(2)} | Revenue: $${parseFloat(row.total_revenue || 0).toFixed(2)}`);
      console.log(`      CPC: $${cpc.toFixed(2)} | CTR: ${ctr.toFixed(2)}% | ROAS: ${roas.toFixed(2)}x`);
      console.log(`      CAC: $${cac.toFixed(2)} | New Customers: ${row.total_new_customers}`);
      console.log();
    });

    // 2. Traffic Source Performance
    console.log("2️⃣ Traffic Source Performance:");
    const traffic = await pool.query(`
      SELECT * FROM traffic_source_summary
      ORDER BY total_revenue DESC
      LIMIT 10
    `);
    traffic.rows.forEach((row, i) => {
      const bounceRate = parseFloat(row.avg_bounce_rate || 0) * 100;
      const signupRate = parseFloat(row.avg_signup_rate || 0) * 100;
      const conversionRate = parseFloat(row.avg_conversion_rate || 0) * 100;
      console.log(`   ${i + 1}. ${row.source} (${row.utm_source}/${row.utm_medium}):`);
      console.log(`      Sessions: ${row.total_sessions} | Signups: ${row.total_signups} | Orders: ${row.total_orders}`);
      console.log(`      Revenue: $${parseFloat(row.total_revenue || 0).toFixed(2)}`);
      console.log(`      Bounce: ${bounceRate.toFixed(1)}% | Signup: ${signupRate.toFixed(2)}% | Conversion: ${conversionRate.toFixed(2)}%`);
      console.log();
    });

    // 3. Source ROI (LTV:CAC)
    console.log("3️⃣ Source ROI (LTV:CAC Ratio) by Platform:");
    const roi = await pool.query(`
      SELECT * FROM source_roi_summary
      ORDER BY ltv_cac_ratio DESC
    `);
    if (roi.rows.length > 0) {
      roi.rows.forEach((row) => {
        const cac = parseFloat(row.cac || 0);
        const ltv = parseFloat(row.avg_ltv || 0);
        const ratio = parseFloat(row.ltv_cac_ratio || 0);
        console.log(`   ${row.platform}:`);
        console.log(`      CAC: $${cac.toFixed(2)} | Avg LTV: $${ltv.toFixed(2)} | Ratio: ${ratio.toFixed(2)}x`);
        console.log(`      Customers Acquired: ${row.customers_acquired}`);
        console.log();
      });
    } else {
      console.log("   No data (link customers to ad_events)\n");
    }

    // 4. Daily Metrics (Last 7 days)
    console.log("4️⃣ Daily Metrics (Last 7 Days):");
    const daily = await pool.query(`
      SELECT 
        date,
        platform,
        total_spend,
        total_clicks,
        total_conversions,
        total_revenue,
        ROUND(cpc::numeric, 2) as cpc,
        ROUND(ctr::numeric * 100, 2) as ctr_pct,
        ROUND(roas::numeric, 2) as roas
      FROM acquisition_metrics_daily
      WHERE date >= CURRENT_DATE - INTERVAL '7 days'
      ORDER BY date DESC, platform
    `);
    daily.rows.forEach((row) => {
      console.log(`   ${row.date} | ${row.platform}: Spend=$${parseFloat(row.total_spend || 0).toFixed(2)}, Clicks=${row.total_clicks}, ROAS=${parseFloat(row.roas || 0).toFixed(2)}x`);
    });

    await pool.end();
    console.log("\n✅ All metrics queried!");
    console.log("\n💡 Tip: Use functions like calculate_cac('meta', '2024-01-01', '2024-12-31') for custom date ranges");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

queryAllMetrics();

