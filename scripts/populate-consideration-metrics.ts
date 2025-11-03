import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function populateMetrics() {
  try {
    console.log("🔄 Populating consideration metrics...\n");

    // Get date range from existing shopify_events
    const dateRange = await pool.query(`
      SELECT MIN(occurred_at::date) as min_date, MAX(occurred_at::date) as max_date
      FROM shopify_events
    `);
    
    if (!dateRange.rows[0].min_date) {
      console.log("⚠️  No shopify_events found. Run data:mock first.");
      await pool.end();
      process.exit(0);
    }

    const minDate = new Date(dateRange.rows[0].min_date);
    const maxDate = new Date(dateRange.rows[0].max_date);
    
    console.log(`📅 Processing dates from ${minDate.toISOString().split('T')[0]} to ${maxDate.toISOString().split('T')[0]}\n`);

    // Populate consideration_metrics_daily for each date
    let processedDates = 0;
    for (let d = new Date(minDate); d <= maxDate; d.setDate(d.getDate() + 1)) {
      const dateStr = d.toISOString().split('T')[0];
      try {
        await pool.query(`SELECT refresh_consideration_metrics_daily($1)`, [dateStr]);
        processedDates++;
        if (processedDates % 50 === 0) {
          process.stdout.write(`   Processed ${processedDates} dates...\r`);
        }
      } catch (error: any) {
        // Continue on errors
      }
    }

    console.log(`\n✅ Processed ${processedDates} dates for consideration metrics\n`);

    // Populate session engagement for recent dates (last 30 days)
    console.log("📊 Populating session engagement metrics...");
    let sessionDates = 0;
    const recentDates: string[] = [];
    const today = new Date();
    for (let i = 0; i < 30; i++) {
      const d = new Date(today);
      d.setDate(d.getDate() - i);
      recentDates.push(d.toISOString().split('T')[0]);
    }
    
    // Also add dates from the date range that have events
    const eventDates = await pool.query(`
      SELECT DISTINCT occurred_at::date as date
      FROM shopify_events
      WHERE session_id IS NOT NULL
      ORDER BY date DESC
      LIMIT 100
    `);
    
    const allSessionDates = [...new Set([...recentDates, ...eventDates.rows.map(r => r.date)])];
    
    for (const dateStr of allSessionDates) {
      try {
        await pool.query(`SELECT refresh_session_engagement_daily($1)`, [dateStr]);
        sessionDates++;
        if (sessionDates % 20 === 0) {
          process.stdout.write(`   Processed ${sessionDates} dates...\r`);
        }
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`\n✅ Processed ${sessionDates} dates for session engagement\n`);

    // Show summary
    const metricsCount = await pool.query(`
      SELECT COUNT(*) as count FROM consideration_metrics_daily
    `);
    const sessionCount = await pool.query(`
      SELECT COUNT(*) as count FROM session_engagement_daily
    `);

    console.log("📊 Summary:");
    console.log(`   - Consideration metrics daily: ${metricsCount.rows[0].count} rows`);
    console.log(`   - Session engagement daily: ${sessionCount.rows[0].count} rows\n`);

    await pool.end();
    console.log("✅ Consideration metrics populated!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

populateMetrics();

