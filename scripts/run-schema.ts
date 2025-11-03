import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";
import { readFileSync } from "fs";
import { join } from "path";

async function runSchema() {
  const config = getConfig();
  if (!config.SUPABASE_DB_URL) {
    console.error("❌ Missing SUPABASE_DB_URL in .env file");
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: config.SUPABASE_DB_URL,
    ssl: {
      rejectUnauthorized: false,
    },
  });

  try {
    console.log("📖 Reading schema file...");
    const schemaPath = join(process.cwd(), "db", "ecommerce_schema.sql");
    const schemaSQL = readFileSync(schemaPath, "utf-8");

    console.log("🚀 Executing schema...");
    await pool.query(schemaSQL);

    console.log("✅ Schema executed successfully!");

    // Verify tables were created
    const tablesResult = await pool.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name
    `);

    console.log(`\n📊 Created ${tablesResult.rows.length} tables:`);
    tablesResult.rows.forEach((row, i) => {
      console.log(`  ${i + 1}. ${row.table_name}`);
    });

    // Check views
    const viewsResult = await pool.query(`
      SELECT table_name
      FROM information_schema.views
      WHERE table_schema = 'public'
      ORDER BY table_name
    `);

    if (viewsResult.rows.length > 0) {
      console.log(`\n👁️  Created ${viewsResult.rows.length} views:`);
      viewsResult.rows.forEach((row, i) => {
        console.log(`  ${i + 1}. ${row.table_name}`);
      });
    }

    // Check functions
    const functionsResult = await pool.query(`
      SELECT routine_name
      FROM information_schema.routines
      WHERE routine_schema = 'public'
        AND routine_type = 'FUNCTION'
      ORDER BY routine_name
    `);

    if (functionsResult.rows.length > 0) {
      console.log(`\n⚙️  Created ${functionsResult.rows.length} functions:`);
      functionsResult.rows.forEach((row, i) => {
        console.log(`  ${i + 1}. ${row.routine_name}`);
      });
    }

    await pool.end();
    process.exit(0);
  } catch (error: any) {
    console.error("❌ Error executing schema:", error.message);
    if (error.position) {
      console.error(`   Error at position: ${error.position}`);
    }
    await pool.end();
    process.exit(1);
  }
}

runSchema();

