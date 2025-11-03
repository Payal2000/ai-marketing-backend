import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function populateMetrics() {
  try {
    console.log("🔄 Populating acquisition metrics...\n");

    // Get date range from existing ad_events
    const dateRange = await pool.query(`
      SELECT MIN(date) as min_date, MAX(date) as max_date
      FROM ad_events
    `);
    
    if (!dateRange.rows[0].min_date) {
      console.log("⚠️  No ad_events found. Run data:mock first.");
      await pool.end();
      process.exit(0);
    }

    const minDate = new Date(dateRange.rows[0].min_date);
    const maxDate = new Date(dateRange.rows[0].max_date);
    
    console.log(`📅 Processing dates from ${minDate.toISOString().split('T')[0]} to ${maxDate.toISOString().split('T')[0]}\n`);

    // Populate acquisition_metrics_daily for each date
    let processedDates = 0;
    for (let d = new Date(minDate); d <= maxDate; d.setDate(d.getDate() + 1)) {
      const dateStr = d.toISOString().split('T')[0];
      try {
        await pool.query(`SELECT refresh_acquisition_metrics_daily($1)`, [dateStr]);
        processedDates++;
        if (processedDates % 10 === 0) {
          process.stdout.write(`   Processed ${processedDates} dates...\r`);
        }
      } catch (error: any) {
        // Continue on errors
      }
    }

    console.log(`\n✅ Processed ${processedDates} dates for acquisition metrics\n`);

    // Populate traffic_source_metrics_daily
    processedDates = 0;
    for (let d = new Date(minDate); d <= maxDate; d.setDate(d.getDate() + 1)) {
      const dateStr = d.toISOString().split('T')[0];
      try {
        await pool.query(`SELECT refresh_traffic_source_metrics_daily($1)`, [dateStr]);
        processedDates++;
      } catch (error: any) {
        // Continue on errors
      }
    }

    console.log(`✅ Processed ${processedDates} dates for traffic source metrics\n`);

    // Show summary
    const metricsCount = await pool.query(`
      SELECT COUNT(*) as count FROM acquisition_metrics_daily
    `);
    const trafficCount = await pool.query(`
      SELECT COUNT(*) as count FROM traffic_source_metrics_daily
    `);

    console.log("📊 Summary:");
    console.log(`   - Acquisition metrics daily: ${metricsCount.rows[0].count} rows`);
    console.log(`   - Traffic source metrics daily: ${trafficCount.rows[0].count} rows\n`);

    await pool.end();
    console.log("✅ Acquisition metrics populated!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

populateMetrics();

