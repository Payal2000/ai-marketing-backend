import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function queryMetrics() {
  try {
    console.log("📊 Advocacy / Loyalty Metrics\n");

    // 1. Overall Summary
    console.log("1️⃣ Overall Advocacy Metrics Summary:");
    const summary = await pool.query(`
      SELECT * FROM advocacy_metrics_summary
    `);
    const row = summary.rows[0];
    if (row) {
      console.log(`   📈 Net Promoter Score (NPS):`);
      console.log(`      Total Responses: ${row.total_nps_responses || 0}`);
      console.log(`      Average NPS: ${parseFloat(row.avg_nps || 0).toFixed(1)}`);
      console.log();
      console.log(`   🔗 Referrals:`);
      console.log(`      Total Referrals: ${row.total_referrals || 0}`);
      console.log(`      Referral Conversion Rate: ${(parseFloat(row.avg_referral_conversion_rate || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   📸 UGC & Reviews:`);
      console.log(`      UGC Submissions: ${row.total_ugc_submissions || 0}`);
      console.log(`      UGC Submission Rate: ${(parseFloat(row.avg_ugc_submission_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Total Reviews: ${row.total_reviews || 0}`);
      console.log(`      Review Participation Rate: ${(parseFloat(row.avg_review_participation_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      Average Review Rating: ${parseFloat(row.avg_review_rating || 0).toFixed(2)}/5.0`);
      console.log();
      console.log(`   💎 Loyalty Program:`);
      console.log(`      Participation Rate: ${(parseFloat(row.avg_loyalty_participation_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      VIP Revenue Contribution: ${(parseFloat(row.avg_vip_revenue_contribution || 0) * 100).toFixed(2)}%`);
      console.log(`      Total VIP Revenue: $${parseFloat(row.total_vip_revenue || 0).toFixed(2)}`);
      console.log();
      console.log(`   📧 Post-Purchase Email:`);
      console.log(`      Emails Sent: ${row.total_post_purchase_emails_sent || 0}`);
      console.log(`      Open Rate: ${(parseFloat(row.avg_post_purchase_email_open_rate || 0) * 100).toFixed(2)}%`);
      console.log(`      CTR: ${(parseFloat(row.avg_post_purchase_email_ctr || 0) * 100).toFixed(2)}%`);
      console.log();
      console.log(`   📱 Social Engagement:`);
      console.log(`      Social Engagement Rate: ${(parseFloat(row.avg_social_engagement_rate || 0) * 100).toFixed(2)}%`);
    }
    console.log();

    // 2. VIP Customer Performance
    console.log("2️⃣ VIP Customer Performance (Top 10):");
    const vipPerformance = await pool.query(`
      SELECT * FROM vip_customer_performance
      ORDER BY total_revenue DESC
      LIMIT 10
    `);
    if (vipPerformance.rows.length > 0) {
      vipPerformance.rows.forEach((vip, i) => {
        console.log(`   ${i + 1}. ${vip.email}:`);
        console.log(`      Revenue: $${parseFloat(vip.total_revenue || 0).toFixed(2)} | Orders: ${vip.total_orders}`);
        console.log(`      Tier: ${vip.loyalty_tier || 'N/A'} | Points: ${vip.points_balance || 0}`);
        console.log(`      Reviews: ${vip.reviews_count || 0} | UGC: ${vip.ugc_submissions_count || 0} | Referrals: ${vip.referrals_count || 0}`);
        console.log();
      });
    } else {
      console.log("   No VIP customers found\n");
    }

    // 3. Daily Trends (Last 7 days)
    console.log("3️⃣ Daily Advocacy Trends (Last 7 Days):");
    const trends = await pool.query(`
      SELECT * FROM advocacy_metrics_trends
      WHERE date >= CURRENT_DATE - INTERVAL '7 days'
      ORDER BY date DESC
      LIMIT 7
    `);
    if (trends.rows.length > 0) {
      trends.rows.forEach((row) => {
        console.log(`   ${row.date}:`);
        console.log(`      NPS: ${parseFloat(row.net_promoter_score || 0).toFixed(1)} | Referral Conv: ${(parseFloat(row.referral_conversion_rate_pct || 0)).toFixed(2)}%`);
        console.log(`      UGC Rate: ${(parseFloat(row.ugc_submission_rate_pct || 0)).toFixed(2)}% | Review Rate: ${(parseFloat(row.review_participation_rate_pct || 0)).toFixed(2)}%`);
        console.log(`      Post-Purchase Open: ${(parseFloat(row.post_purchase_email_open_rate_pct || 0)).toFixed(2)}%`);
        console.log();
      });
    } else {
      console.log("   No recent data available\n");
    }

    // 4. Sample Function Calls
    console.log("4️⃣ Sample Function Calculations (Current):");
    const functions = [
      { name: "Net Promoter Score (NPS)", query: "SELECT calculate_nps() as value" },
      { name: "Referral Conversion Rate", query: "SELECT calculate_referral_conversion_rate() as value" },
      { name: "UGC Submission Rate", query: "SELECT calculate_ugc_submission_rate() as value" },
      { name: "Review Participation Rate", query: "SELECT calculate_review_participation_rate() as value" },
      { name: "Loyalty Program Participation Rate", query: "SELECT calculate_loyalty_participation_rate() as value" },
      { name: "VIP Revenue Contribution", query: "SELECT calculate_vip_revenue_contribution() as value" },
      { name: "Post-Purchase Email Open Rate", query: "SELECT calculate_post_purchase_email_open_rate() as value" },
      { name: "Post-Purchase Email CTR", query: "SELECT calculate_post_purchase_email_ctr() as value" },
      { name: "Social Engagement Rate", query: "SELECT calculate_social_engagement_rate() as value" }
    ];

    for (const func of functions) {
      try {
        const result = await pool.query(func.query);
        const value = result.rows[0]?.value;
        if (value !== null && value !== undefined) {
          if (func.name.includes("Rate") || func.name.includes("CTR") || func.name.includes("Participation")) {
            console.log(`   ${func.name}: ${(parseFloat(value) * 100).toFixed(2)}%`);
          } else if (func.name.includes("NPS")) {
            console.log(`   ${func.name}: ${parseFloat(value).toFixed(1)}`);
          } else if (func.name.includes("Contribution")) {
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
    console.log("\n✅ All advocacy metrics queried!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

queryMetrics();

