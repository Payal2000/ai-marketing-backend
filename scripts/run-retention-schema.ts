import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";
import { readFileSync } from "fs";
import { join } from "path";

async function runRetentionSchema() {
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
    console.log("📖 Reading retention metrics schema...");
    const schemaPath = join(process.cwd(), "db", "retention_metrics_schema.sql");
    const schemaSQL = readFileSync(schemaPath, "utf-8");

    console.log("🚀 Executing schema...");
    
    try {
      await pool.query(schemaSQL);
      console.log("✅ Schema executed successfully!\n");
    } catch (error: any) {
      if (error.message.includes('already exists') || 
          error.message.includes('does not exist') ||
          error.code === '42P07' || 
          error.code === '42710') {
        console.log("⚠️  Some objects already exist, continuing...\n");
      } else {
        console.error(`❌ Error: ${error.message}`);
        if (error.position) {
          console.error(`   Error at position: ${error.position}`);
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
        AND table_name IN ('retention_metrics_daily', 'customer_retention_cohorts')
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
        AND table_name IN ('retention_metrics_summary', 'customer_retention_cohorts_summary', 'retention_metrics_trends')
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
        AND (routine_name LIKE '%repeat%' OR routine_name LIKE '%churn%' OR routine_name LIKE '%retention%' OR routine_name LIKE '%reorder%' OR routine_name LIKE '%winback%' OR routine_name LIKE '%replenishment%' OR routine_name LIKE '%ltv%' OR routine_name LIKE '%active%')
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

runRetentionSchema();

