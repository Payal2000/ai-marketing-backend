import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function queryMetrics() {
  try {
    console.log("📊 Consideration Metrics\n");

    // 1. Overall Summary
    console.log("1️⃣ Overall Consideration Metrics Summary:");
    const summary = await pool.query(`
      SELECT * FROM consideration_metrics_summary
    `);
    const row = summary.rows[0];
    if (row) {
      console.log(`   Product Views: ${row.total_product_views || 0}`);
      console.log(`   Add-to-Cart Events: ${row.total_add_to_cart || 0}`);
      console.log(`   Wishlist Adds: ${row.total_wishlist_adds || 0}`);
      console.log(`   Checkout Starts: ${row.total_checkout_starts || 0}`);
      console.log();
      console.log(`   📈 Rates (Average):`);
      console.log(`      Add-to-Cart Rate: ${(parseFloat(row.avg_add_to_cart_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      View-to-Add-to-Cart Ratio: ${(parseFloat(row.avg_view_to_add_to_cart_ratio || 0) * 100).toFixed(2)}%`);
      console.log(`      Wishlist Add Rate: ${(parseFloat(row.avg_wishlist_add_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Cart Abandonment Rate: ${(parseFloat(row.avg_cart_abandonment_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Product Page Bounce Rate: ${(parseFloat(row.avg_product_page_bounce_rate || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   🕐 Session Metrics:`);
      console.log(`      Avg Pages per Session: ${parseFloat(row.avg_pages_per_session || 0).toFixed(2)}`);
      console.log(`      Avg Session Duration: ${Math.round(parseFloat(row.avg_session_duration_seconds || 0))} seconds`);
      console.log(`      Avg Scroll Depth: ${parseFloat(row.avg_scroll_depth_percent || 0).toFixed(1)}%`);
      console.log(`      Repeat Visit Rate (7d): ${(parseFloat(row.avg_repeat_visit_rate_7d || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   📧 Email Metrics (Klaviyo):`);
      console.log(`      Emails Sent: ${row.total_emails_sent || 0}`);
      console.log(`      Email Open Rate: ${(parseFloat(row.avg_email_open_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Email CTR: ${(parseFloat(row.avg_email_ctr || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   ⭐ Engagement Score: ${parseFloat(row.avg_engagement_score || 0).toFixed(2)}`);
    }
    console.log();

    // 2. Daily Trends (Last 7 days)
    console.log("2️⃣ Daily Trends (Last 7 Days):");
    const trends = await pool.query(`
      SELECT * FROM consideration_metrics_trends
      WHERE date >= CURRENT_DATE - INTERVAL '7 days'
      ORDER BY date DESC
      LIMIT 7
    `);
    trends.rows.forEach((row) => {
      console.log(`   ${row.date}:`);
      console.log(`      ATC Rate: ${(parseFloat(row.add_to_cart_rate_pct || 0)).toFixed(2)}% | ` +
                  `Cart Abandonment: ${(parseFloat(row.cart_abandonment_rate_pct || 0)).toFixed(2)}%`);
      console.log(`      Avg Pages: ${parseFloat(row.avg_pages_per_session || 0).toFixed(1)} | ` +
                  `Session Duration: ${Math.round(parseFloat(row.avg_session_duration_seconds || 0))}s`);
      console.log(`      Email Open: ${(parseFloat(row.email_open_rate_pct || 0)).toFixed(2)}% | ` +
                  `Email CTR: ${(parseFloat(row.email_ctr_pct || 0)).toFixed(2)}%`);
      console.log();
    });

    // 3. Sample Function Calls
    console.log("3️⃣ Sample Function Calculations (Last 30 Days):");
    const functions = [
      { name: "Add-to-Cart Rate", query: "SELECT calculate_add_to_cart_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "View-to-Add-to-Cart Ratio", query: "SELECT calculate_view_to_add_to_cart_ratio(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Wishlist Add Rate", query: "SELECT calculate_wishlist_add_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Cart Abandonment Rate", query: "SELECT calculate_cart_abandonment_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Product Page Bounce Rate", query: "SELECT calculate_product_page_bounce_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Email Open Rate", query: "SELECT calculate_email_open_rate(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Email CTR", query: "SELECT calculate_email_ctr(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Repeat Visit Rate (7d)", query: "SELECT calculate_repeat_visit_rate_7d(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" },
      { name: "Engagement Score", query: "SELECT calculate_engagement_score(CURRENT_DATE - INTERVAL '30 days', CURRENT_DATE) as value" }
    ];

    for (const func of functions) {
      try {
        const result = await pool.query(func.query);
        const value = result.rows[0]?.value;
        if (value !== null && value !== undefined) {
          if (func.name.includes("Rate") || func.name.includes("Ratio") || func.name.includes("CTR")) {
            console.log(`   ${func.name}: ${(parseFloat(value) * 100).toFixed(2)}%`);
          } else {
            console.log(`   ${func.name}: ${parseFloat(value).toFixed(2)}`);
          }
        }
      } catch (error: any) {
        // Skip errors
      }
    }

    await pool.end();
    console.log("\n✅ All consideration metrics queried!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

queryMetrics();

