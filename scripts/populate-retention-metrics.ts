import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function populateMetrics() {
  try {
    console.log("🔄 Populating retention metrics...\n");

    // First, refresh customer cohorts
    console.log("📊 Refreshing customer retention cohorts...");
    await pool.query("SELECT refresh_customer_retention_cohorts()");
    console.log("✅ Customer cohorts refreshed\n");

    // Get date range from existing orders
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

    // Populate retention_metrics_daily for key dates
    let processedDates = 0;
    let skippedDates = 0;
    
    // Process today and last 30 days (recent dates)
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
      d.setDate(15); // Use middle of month
      monthlyDates.push(d.toISOString().split('T')[0]);
    }
    
    // Combine and remove duplicates
    const allDates = [...datesToProcess, ...monthlyDates];
    const uniqueDates = [...new Set(allDates)].sort();
    
    console.log(`   Processing ${uniqueDates.length} dates...\n`);
    
    for (const dateStr of uniqueDates) {
      try {
        await pool.query(`SELECT refresh_retention_metrics_daily($1)`, [dateStr]);
        processedDates++;
        if (processedDates % 20 === 0) {
          process.stdout.write(`   Processed ${processedDates}/${uniqueDates.length} dates...\r`);
        }
      } catch (error: any) {
        skippedDates++;
        if (skippedDates <= 5) {
          console.warn(`   ⚠️  Error for ${dateStr}: ${error.message.substring(0, 50)}`);
        }
      }
    }

    console.log(`\n✅ Processed ${processedDates} dates for retention metrics (skipped ${skippedDates} dates)\n`);

    // Show summary
    const metricsCount = await pool.query(`
      SELECT COUNT(*) as count FROM retention_metrics_daily
    `);
    const cohortsCount = await pool.query(`
      SELECT COUNT(*) as count FROM customer_retention_cohorts
    `);

    console.log("📊 Summary:");
    console.log(`   - Retention metrics daily: ${metricsCount.rows[0].count} rows`);
    console.log(`   - Customer retention cohorts: ${cohortsCount.rows[0].count} rows\n`);

    await pool.end();
    console.log("✅ Retention metrics populated!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

populateMetrics();

