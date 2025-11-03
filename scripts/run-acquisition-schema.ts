import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";
import { readFileSync } from "fs";
import { join } from "path";

async function runAcquisitionSchema() {
  const config = getConfig();
  if (!config.SUPABASE_DB_URL) {
    console.error("❌ Missing SUPABASE_DB_URL in .env file");
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: config.SUPABASE_DB_URL,
    ssl: { rejectUnauthorized: false },
  });

  try {
    console.log("📖 Reading acquisition metrics schema...");
    const schemaPath = join(process.cwd(), "db", "acquisition_metrics_schema.sql");
    const schemaSQL = readFileSync(schemaPath, "utf-8");

    console.log("🚀 Executing schema...");
    
    // Execute the entire SQL file at once (PostgreSQL handles it properly)
    try {
      await pool.query(schemaSQL);
      console.log("✅ Schema executed successfully!\n");
    } catch (error: any) {
      // Check if it's a non-critical error
      if (error.message.includes('already exists') || 
          error.message.includes('does not exist') ||
          error.code === '42P07' || // duplicate_table
          error.code === '42710') { // duplicate_object
        console.log("⚠️  Some objects already exist, continuing...\n");
      } else {
        console.error(`❌ Error: ${error.message}`);
        if (error.position) {
          console.error(`   Error at position: ${error.position}`);
          // Show context around error
          const start = Math.max(0, error.position - 50);
          const end = Math.min(schemaSQL.length, error.position + 50);
          console.error(`   Context: ${schemaSQL.substring(start, end)}`);
        }
        throw error;
      }
    }

    // Verify tables
    const tablesResult = await pool.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
        AND table_name IN ('acquisition_metrics_daily', 'traffic_source_metrics_daily')
      ORDER BY table_name
    `);

    console.log(`📊 Created/Verified Tables:`);
    tablesResult.rows.forEach((row) => {
      console.log(`   ✅ ${row.table_name}`);
    });

    // Check views
    const viewsResult = await pool.query(`
      SELECT table_name
      FROM information_schema.views
      WHERE table_schema = 'public'
        AND table_name IN ('acquisition_metrics_summary', 'traffic_source_summary', 'source_roi_summary')
      ORDER BY table_name
    `);

    if (viewsResult.rows.length > 0) {
      console.log(`\n👁️  Created/Verified Views:`);
      viewsResult.rows.forEach((row) => {
        console.log(`   ✅ ${row.table_name}`);
      });
    }

    // Check functions
    const functionsResult = await pool.query(`
      SELECT routine_name
      FROM information_schema.routines
      WHERE routine_schema = 'public'
        AND routine_type = 'FUNCTION'
        AND routine_name LIKE 'calculate_%'
      ORDER BY routine_name
    `);

    if (functionsResult.rows.length > 0) {
      console.log(`\n⚙️  Created/Verified Functions:`);
      functionsResult.rows.forEach((row) => {
        console.log(`   ✅ ${row.routine_name}`);
      });
    }

    await pool.end();
    process.exit(0);
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

runAcquisitionSchema();

