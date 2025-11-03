import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function queryMetrics() {
  try {
    console.log("📊 Retention Metrics\n");

    // 1. Overall Summary
    console.log("1️⃣ Overall Retention Metrics Summary:");
    const summary = await pool.query(`
      SELECT * FROM retention_metrics_summary
    `);
    const row = summary.rows[0];
    if (row) {
      console.log(`   Total Customers (All Time): ${row.total_customers_all_time || 0}`);
      console.log();
      console.log(`   📈 Repeat & Retention:`);
      console.log(`      Repeat Purchase Rate: ${(parseFloat(row.avg_repeat_purchase_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Active Customer Rate (30d): ${(parseFloat(row.avg_active_customer_rate_30d || 0) * 100).toFixed(2)}%`);
      console.log(`      Active Customer Rate (60d): ${(parseFloat(row.avg_active_customer_rate_60d || 0) * 100).toFixed(2)}%`);
      console.log(`      Active Customer Rate (90d): ${(parseFloat(row.avg_active_customer_rate_90d || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   ⚠️  Churn Rates:`);
      console.log(`      Churn Rate (30d): ${(parseFloat(row.avg_churn_rate_30d || 0) * 100).toFixed(2)}%`);
      console.log(`      Churn Rate (60d): ${(parseFloat(row.avg_churn_rate_60d || 0) * 100).toFixed(2)}%`);
      console.log(`      Churn Rate (90d): ${(parseFloat(row.avg_churn_rate_90d || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   ⏱️  Time Between Purchases:`);
      console.log(`      Avg Days Between Purchases: ${parseFloat(row.avg_days_between_purchases || 0).toFixed(1)} days`);
      console.log(`      Median Days Between Purchases: ${parseFloat(row.avg_median_days_between_purchases || 0).toFixed(1)} days`);
      console.log();
      console.log(`   💰 Customer Lifetime Value:`);
      console.log(`      Avg LTV: $${parseFloat(row.avg_ltv || 0).toFixed(2)}`);
      console.log(`      Median LTV: $${parseFloat(row.avg_median_ltv || 0).toFixed(2)}`);
      console.log(`      Total LTV: $${parseFloat(row.total_ltv_all_time || 0).toFixed(2)}`);
      console.log();
      console.log(`   🔮 Klaviyo Predictions:`);
      console.log(`      Avg Reorder Probability: ${(parseFloat(row.avg_reorder_probability || 0) * 100).toFixed(2)}%`);
      console.log(`      Avg Churn Probability: ${(parseFloat(row.avg_churn_probability || 0) * 100).toFixed(2)}%`);
      console.log(`      Avg Predicted LTV: $${parseFloat(row.avg_predicted_ltv || 0).toFixed(2)}`);
      console.log();
      console.log(`   📧 Email Engagement:`);
      console.log(`      Avg Email Engagement Probability: ${(parseFloat(row.avg_email_engagement_probability || 0) * 100).toFixed(2)}%`);
      console.log(`      Engagement Decay Rate: ${parseFloat(row.avg_engagement_decay_rate || 0).toFixed(4)}`);
      console.log(`      Winback Email Open Rate: ${(parseFloat(row.avg_winback_email_open_rate || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   📦 Other Metrics:`);
      console.log(`      Subscription Retention Rate: ${(parseFloat(row.avg_subscription_retention_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Replenishment Accuracy: ${parseFloat(row.avg_replenishment_accuracy_days || 0).toFixed(1)} days`);
      console.log(`      Avg LTV:CAC Ratio: ${parseFloat(row.avg_ltv_cac_ratio || 0).toFixed(2)}x`);
    }
    console.log();

    // 2. Cohort Summary
    console.log("2️⃣ Customer Retention Cohorts Summary (Last 5 Cohorts):");
    const cohorts = await pool.query(`
      SELECT * FROM customer_retention_cohorts_summary
      ORDER BY cohort_date DESC
      LIMIT 5
    `);
    cohorts.rows.forEach((row) => {
      const retention_30d = row.cohort_size > 0 ? (row.active_30d / row.cohort_size * 100).toFixed(1) : '0.0';
      const retention_90d = row.cohort_size > 0 ? (row.active_90d / row.cohort_size * 100).toFixed(1) : '0.0';
      console.log(`   ${row.cohort_date}: Cohort Size: ${row.cohort_size}`);
      console.log(`      Active 30d: ${row.active_30d} (${retention_30d}%) | Active 90d: ${row.active_90d} (${retention_90d}%)`);
      console.log(`      Churned 30d: ${row.churned_30d} | Churned 90d: ${row.churned_90d}`);
      console.log(`      Avg Orders: ${parseFloat(row.avg_orders_per_customer || 0).toFixed(1)} | Avg Revenue: $${parseFloat(row.avg_revenue_per_customer || 0).toFixed(2)}`);
      console.log();
    });

    // 3. Daily Trends (Last 7 days)
    console.log("3️⃣ Daily Retention Trends (Last 7 Days):");
    const trends = await pool.query(`
      SELECT * FROM retention_metrics_trends
      WHERE date >= CURRENT_DATE - INTERVAL '7 days'
      ORDER BY date DESC
      LIMIT 7
    `);
    if (trends.rows.length > 0) {
      trends.rows.forEach((row) => {
        console.log(`   ${row.date}:`);
        console.log(`      Repeat Purchase: ${(parseFloat(row.repeat_purchase_rate_pct || 0)).toFixed(2)}% | Active (30d): ${(parseFloat(row.active_customer_rate_30d_pct || 0)).toFixed(2)}%`);
        console.log(`      Churn (30d): ${(parseFloat(row.churn_rate_30d_pct || 0)).toFixed(2)}% | Avg LTV: $${parseFloat(row.avg_ltv || 0).toFixed(2)}`);
        console.log(`      Reorder Prob: ${(parseFloat(row.avg_reorder_probability_pct || 0)).toFixed(2)}% | LTV:CAC: ${parseFloat(row.avg_ltv_cac_ratio || 0).toFixed(2)}x`);
        console.log();
      });
    } else {
      console.log("   No recent data available\n");
    }

    // 4. Sample Function Calls
    console.log("4️⃣ Sample Function Calculations (Current):");
    const functions = [
      { name: "Repeat Purchase Rate", query: "SELECT calculate_repeat_purchase_rate() as value" },
      { name: "Avg Days Between Purchases", query: "SELECT calculate_avg_days_between_purchases() as value" },
      { name: "Active Customer Rate (30d)", query: "SELECT calculate_active_customer_rate(30) as value" },
      { name: "Active Customer Rate (60d)", query: "SELECT calculate_active_customer_rate(60) as value" },
      { name: "Churn Rate (30d)", query: "SELECT calculate_churn_rate(30) as value" },
      { name: "Churn Rate (90d)", query: "SELECT calculate_churn_rate(90) as value" },
      { name: "Avg LTV", query: "SELECT calculate_avg_ltv() as value" },
      { name: "Avg Reorder Probability", query: "SELECT calculate_avg_reorder_probability() as value" },
      { name: "Subscription Retention Rate", query: "SELECT calculate_subscription_retention_rate() as value" },
      { name: "Winback Email Open Rate", query: "SELECT calculate_winback_email_open_rate() as value" },
      { name: "Replenishment Accuracy", query: "SELECT calculate_replenishment_accuracy() as value" },
      { name: "Avg LTV:CAC Ratio", query: "SELECT calculate_avg_ltv_cac_ratio() as value" }
    ];

    for (const func of functions) {
      try {
        const result = await pool.query(func.query);
        const value = result.rows[0]?.value;
        if (value !== null && value !== undefined) {
          if (func.name.includes("Rate") || func.name.includes("Probability")) {
            console.log(`   ${func.name}: ${(parseFloat(value) * 100).toFixed(2)}%`);
          } else if (func.name.includes("Days")) {
            console.log(`   ${func.name}: ${parseFloat(value).toFixed(1)} days`);
          } else if (func.name.includes("LTV") && !func.name.includes("Ratio")) {
            console.log(`   ${func.name}: $${parseFloat(value).toFixed(2)}`);
          } else {
            console.log(`   ${func.name}: ${parseFloat(value).toFixed(2)}`);
          }
        }
      } catch (error: any) {
        // Skip errors
      }
    }

    await pool.end();
    console.log("\n✅ All retention metrics queried!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

queryMetrics();

