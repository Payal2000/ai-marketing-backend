import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

async function testConnection() {
  const config = getConfig();
  if (!config.SUPABASE_DB_URL) {
    console.error("❌ Missing SUPABASE_DB_URL in .env file");
    process.exit(1);
  }
  
  const pool = new Pool({ 
    connectionString: config.SUPABASE_DB_URL,
    ssl: {
      rejectUnauthorized: false // Supabase uses self-signed certificates
    }
  });
  
  try {
    console.log("Testing database connection...");
    const result = await pool.query("SELECT version(), current_database(), current_user");
    console.log("✅ Connection successful!");
    console.log("\nDatabase Info:");
    console.log("- Version:", result.rows[0].version);
    console.log("- Database:", result.rows[0].current_database);
    console.log("- User:", result.rows[0].current_user);
    
    // Test if we can query tables
    const tablesResult = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      ORDER BY table_name
      LIMIT 10
    `);
    
    console.log("\n📊 Existing tables:", tablesResult.rows.map(r => r.table_name).join(", ") || "None");
    
    await pool.end();
    process.exit(0);
  } catch (error: any) {
    console.error("❌ Connection failed:", error.message);
    await pool.end();
    process.exit(1);
  }
}

testConnection();

