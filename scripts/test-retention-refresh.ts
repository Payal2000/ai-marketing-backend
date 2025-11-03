import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function testRefresh() {
  try {
    console.log("🧪 Testing retention metrics refresh...\n");

    // Test with today's date
    const today = new Date().toISOString().split('T')[0];
    console.log(`📅 Testing refresh for date: ${today}\n`);

    // Call the refresh function
    const result = await pool.query(
      `SELECT refresh_retention_metrics_daily($1)`,
      [today]
    );

    console.log("✅ Refresh function executed successfully\n");

    // Check if data was inserted
    const checkResult = await pool.query(
      `SELECT * FROM retention_metrics_daily WHERE date = $1`,
      [today]
    );

    if (checkResult.rows.length > 0) {
      const row = checkResult.rows[0];
      console.log("✅ Data inserted successfully!");
      console.log(`   Total Customers: ${row.total_customers}`);
      console.log(`   Active 30d: ${row.active_customers_30d}`);
      console.log(`   Repeat Customers: ${row.repeat_customers}`);
      console.log(`   Repeat Purchase Rate: ${(parseFloat(row.repeat_purchase_rate || 0) * 100).toFixed(2)}%`);
      console.log(`   Avg LTV: $${parseFloat(row.avg_ltv || 0).toFixed(2)}`);
    } else {
      console.log("❌ No data inserted - checking for errors...\n");
      
      // Check if there are any customers
      const customerCount = await pool.query(`SELECT COUNT(*) as count FROM customers WHERE total_orders > 0`);
      console.log(`   Customers with orders: ${customerCount.rows[0].count}`);
      
      // Try to manually insert to see what happens
      console.log("\n🔍 Checking function logic...");
      const testQuery = await pool.query(`
        SELECT 
          COUNT(*) FILTER (WHERE total_orders > 0) as total_customers,
          COUNT(*) FILTER (WHERE total_orders > 1) as repeat_customers
        FROM customers
      `);
      console.log(`   Test query result:`, testQuery.rows[0]);
    }

    await pool.end();
    process.exit(0);
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    console.error("   Details:", error);
    await pool.end();
    process.exit(1);
  }
}

testRefresh();

