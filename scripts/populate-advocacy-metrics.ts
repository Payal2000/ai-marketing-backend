import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function populateMetrics() {
  try {
    console.log("🔄 Populating advocacy metrics...\n");

    // First, generate mock data for advocacy tables if needed
    console.log("📊 Checking if advocacy data exists...");
    
    const npsCount = await pool.query(`SELECT COUNT(*) as count FROM nps_surveys`);
    const referralsCount = await pool.query(`SELECT COUNT(*) as count FROM referrals`);
    const reviewsCount = await pool.query(`SELECT COUNT(*) as count FROM reviews`);
    const ugcCount = await pool.query(`SELECT COUNT(*) as count FROM ugc_submissions`);
    const loyaltyCount = await pool.query(`SELECT COUNT(*) as count FROM loyalty_enrollments`);

    console.log(`   NPS Surveys: ${npsCount.rows[0].count}`);
    console.log(`   Referrals: ${referralsCount.rows[0].count}`);
    console.log(`   Reviews: ${reviewsCount.rows[0].count}`);
    console.log(`   UGC Submissions: ${ugcCount.rows[0].count}`);
    console.log(`   Loyalty Enrollments: ${loyaltyCount.rows[0].count}\n`);

    // Get date range from existing orders for populating daily metrics
    const dateRange = await pool.query(`
      SELECT MIN(order_date::date) as min_date, MAX(order_date::date) as max_date
      FROM shopify_orders
    `);
    
    if (!dateRange.rows[0].min_date) {
      console.log("⚠️  No shopify_orders found. Run data:mock first.");
      await pool.end();
      process.exit(0);
    }

    const minDate = new Date(dateRange.rows[0].min_date);
    const maxDate = new Date(dateRange.rows[0].max_date);
    
    console.log(`📅 Processing dates from ${minDate.toISOString().split('T')[0]} to ${maxDate.toISOString().split('T')[0]}\n`);

    // Populate advocacy_metrics_daily for key dates
    let processedDates = 0;
    const today = new Date();
    const datesToProcess: string[] = [];
    
    // Add today and last 30 days
    for (let i = 0; i <= 30; i++) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      datesToProcess.push(d.toISOString().split('T')[0]);
    }
    
    // Add sample monthly dates from history
    const monthlyDates: string[] = [];
    for (let d = new Date(minDate); d < new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000); d.setMonth(d.getMonth() + 1)) {
      d.setDate(15);
      monthlyDates.push(d.toISOString().split('T')[0]);
    }
    
    // Combine and remove duplicates
    const allDates = [...datesToProcess, ...monthlyDates];
    const uniqueDates = [...new Set(allDates)].sort();
    
    console.log(`   Processing ${uniqueDates.length} dates...\n`);
    
    for (const dateStr of uniqueDates) {
      try {
        await pool.query(`SELECT refresh_advocacy_metrics_daily($1)`, [dateStr]);
        processedDates++;
        if (processedDates % 20 === 0) {
          process.stdout.write(`   Processed ${processedDates}/${uniqueDates.length} dates...\r`);
        }
      } catch (error: any) {
        // Continue on errors
      }
    }

    console.log(`\n✅ Processed ${processedDates} dates for advocacy metrics\n`);

    // Show summary
    const metricsCount = await pool.query(`
      SELECT COUNT(*) as count FROM advocacy_metrics_daily
    `);

    console.log("📊 Summary:");
    console.log(`   - Advocacy metrics daily: ${metricsCount.rows[0].count} rows\n`);

    await pool.end();
    console.log("✅ Advocacy metrics populated!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

populateMetrics();

