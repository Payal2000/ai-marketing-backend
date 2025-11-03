import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function checkEmptyTables() {
  const result = await pool.query(`
    SELECT 
      table_name,
      (SELECT COUNT(*) FROM information_schema.columns 
       WHERE table_name = t.table_name AND table_schema = 'public') as column_count
    FROM information_schema.tables t
    WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
    ORDER BY table_name
  `);

  const emptyTables: string[] = [];
  
  for (const row of result.rows) {
    const count = await pool.query(`SELECT COUNT(*) as count FROM ${row.table_name}`);
    const tableCount = parseInt(count.rows[0].count);
    
    if (tableCount === 0) {
      emptyTables.push(row.table_name);
      console.log(`❌ ${row.table_name}: 0 rows`);
    } else {
      console.log(`✅ ${row.table_name}: ${tableCount} rows`);
    }
  }
  
  await pool.end();
  
  if (emptyTables.length > 0) {
    console.log(`\n⚠️  ${emptyTables.length} empty tables found`);
    process.exit(1);
  } else {
    console.log(`\n✅ All tables have data!`);
    process.exit(0);
  }
}

checkEmptyTables();

