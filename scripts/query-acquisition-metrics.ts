import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function queryAcquisitionMetrics() {
  try {
    console.log("📊 Acquisition Metrics from Database\n");

    // 1. CAC by Platform
    console.log("1️⃣ Customer Acquisition Cost (CAC) by Platform:");
    const cac = await pool.query(`
      SELECT 
        platform,
        SUM(spend) / NULLIF(COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL), 0) as cac
      FROM ad_events
      WHERE event_type = 'conversion' OR event_type = 'purchase'
      GROUP BY platform
    `);
    cac.rows.forEach(row => {
      const cacValue = parseFloat(row.cac || 0);
      console.log(`   ${row.platform}: $${cacValue.toFixed(2)}`);
    });

    // 2. CTR by Platform
    console.log("\n2️⃣ Click-Through Rate (CTR) by Platform:");
    const ctr = await pool.query(`
      SELECT 
        platform,
        ROUND(SUM(clicks)::decimal / NULLIF(SUM(impressions), 0) * 100, 2) as ctr_percentage
      FROM ad_events
      WHERE impressions > 0
      GROUP BY platform
    `);
    ctr.rows.forEach(row => {
      console.log(`   ${row.platform}: ${row.ctr_percentage || 0}%`);
    });

    // 3. CPC by Platform
    console.log("\n3️⃣ Cost per Click (CPC) by Platform:");
    const cpc = await pool.query(`
      SELECT 
        platform,
        ROUND(SUM(spend) / NULLIF(SUM(clicks), 0), 2) as cpc
      FROM ad_events
      WHERE clicks > 0
      GROUP BY platform
    `);
    cpc.rows.forEach(row => {
      const cpcValue = parseFloat(row.cpc || 0);
      console.log(`   ${row.platform}: $${cpcValue.toFixed(2)}`);
    });

    // 4. CPM by Platform
    console.log("\n4️⃣ Cost per Impression (CPM) by Platform:");
    const cpm = await pool.query(`
      SELECT 
        platform,
        ROUND(SUM(spend) / NULLIF(SUM(impressions), 0) * 1000, 2) as cpm
      FROM ad_events
      WHERE impressions > 0
      GROUP BY platform
    `);
    cpm.rows.forEach(row => {
      const cpmValue = parseFloat(row.cpm || 0);
      console.log(`   ${row.platform}: $${cpmValue.toFixed(2)}`);
    });

    // 5. ROAS by Platform
    console.log("\n5️⃣ Return on Ad Spend (ROAS) by Platform:");
    const roas = await pool.query(`
      SELECT 
        platform,
        ROUND(SUM(revenue) / NULLIF(SUM(spend), 0), 2) as roas
      FROM ad_events
      WHERE spend > 0
      GROUP BY platform
    `);
    roas.rows.forEach(row => {
      const roasValue = parseFloat(row.roas || 0);
      console.log(`   ${row.platform}: ${roasValue.toFixed(2)}x`);
    });

    // 6. Traffic by Source (Orders)
    console.log("\n6️⃣ Traffic by Source (Order Source):");
    const traffic = await pool.query(`
      SELECT 
        source,
        COUNT(*) as order_count,
        SUM(total_price) as revenue
      FROM shopify_orders
      WHERE financial_status = 'paid'
      GROUP BY source
    `);
    traffic.rows.forEach(row => {
      const revenue = parseFloat(row.revenue || 0);
      console.log(`   ${row.source}: ${row.order_count} orders, $${revenue.toFixed(2)} revenue`);
    });

    // 7. New vs Returning Customers
    console.log("\n7️⃣ New Users / First-Time Visitors:");
    const newUsers = await pool.query(`
      SELECT 
        COUNT(*) FILTER (WHERE is_first_time_customer = true) as new_customers,
        COUNT(*) FILTER (WHERE is_first_time_customer = false) as returning_customers,
        COUNT(*) as total_customers
      FROM customers
    `);
    const stats = newUsers.rows[0];
    console.log(`   New Customers: ${stats.new_customers}`);
    console.log(`   Returning Customers: ${stats.returning_customers}`);
    console.log(`   Total Customers: ${stats.total_customers}`);

    // 8. Source ROI (LTV:CAC Ratio)
    console.log("\n8️⃣ Source ROI (LTV:CAC Ratio) by Platform:");
    const sourceROI = await pool.query(`
      WITH channel_cac AS (
        SELECT 
          platform,
          SUM(spend) / NULLIF(COUNT(DISTINCT customer_id) FILTER (WHERE customer_id IS NOT NULL), 0) as cac
        FROM ad_events
        WHERE event_type IN ('conversion', 'purchase')
        GROUP BY platform
      ),
      channel_ltv AS (
        SELECT 
          ae.platform,
          AVG(c.total_revenue) as avg_ltv
        FROM ad_events ae
        JOIN customers c ON c.id = ae.customer_id
        WHERE ae.customer_id IS NOT NULL
        GROUP BY ae.platform
      )
      SELECT 
        cc.platform,
        ROUND(cc.cac, 2) as cac,
        ROUND(cl.avg_ltv, 2) as avg_ltv,
        ROUND(cl.avg_ltv / NULLIF(cc.cac, 0), 2) as ltv_cac_ratio
      FROM channel_cac cc
      JOIN channel_ltv cl ON cl.platform = cc.platform
      ORDER BY ltv_cac_ratio DESC
    `);
    if (sourceROI.rows.length > 0) {
      sourceROI.rows.forEach(row => {
        const cac = parseFloat(row.cac || 0);
        const ltv = parseFloat(row.avg_ltv || 0);
        const ratio = parseFloat(row.ltv_cac_ratio || 0);
        console.log(`   ${row.platform}: CAC=$${cac.toFixed(2)}, LTV=$${ltv.toFixed(2)}, Ratio=${ratio.toFixed(2)}x`);
      });
    } else {
      console.log("   No data available (need customers linked to ad_events)");
    }

    await pool.end();
    console.log("\n✅ Acquisition metrics query complete!");
    console.log("\n📖 See db/ACQUISITION_METRICS.md for detailed storage locations and calculations");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

queryAcquisitionMetrics();

