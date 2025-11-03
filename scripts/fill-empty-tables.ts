import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function randomElement<T>(array: T[]): T {
  return array[Math.floor(Math.random() * array.length)];
}

async function fillEmptyTables() {
  try {
    console.log("🔍 Checking for empty tables...\n");

    // Check customer_addresses
    const addressCount = await pool.query(`SELECT COUNT(*) as count FROM customer_addresses`);
    if (parseInt(addressCount.rows[0].count) === 0) {
      console.log("📦 Filling customer_addresses...");
      
      const customers = await pool.query(`SELECT id FROM customers`);
      const streets = ["Main St", "Oak Ave", "Park Blvd", "Maple Dr", "Elm St", "First Ave", "Second St"];
      const cities = ["New York", "Los Angeles", "Chicago", "Houston", "Toronto", "Vancouver", "London"];
      
      for (const customer of customers.rows) {
        // Shipping address
        await pool.query(`
          INSERT INTO customer_addresses (
            customer_id, shopify_address_id, type, is_default, address_line1,
            city, province, postal_code, country
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
          customer.id,
          `addr_shipping_${customer.id.substring(0, 8)}`,
          'shipping',
          true,
          `${randomInt(100, 9999)} ${randomElement(streets)}`,
          randomElement(cities),
          randomElement(["NY", "CA", "TX", "IL", "ON", "BC"]),
          `${randomInt(10000, 99999)}`,
          randomElement(["USA", "Canada", "UK"])
        ]);

        // Billing address (70% of customers have separate billing)
        if (Math.random() > 0.3) {
          await pool.query(`
            INSERT INTO customer_addresses (
              customer_id, shopify_address_id, type, is_default, address_line1,
              city, province, postal_code, country
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          `, [
            customer.id,
            `addr_billing_${customer.id.substring(0, 8)}`,
            'billing',
            false,
            `${randomInt(100, 9999)} ${randomElement(streets)}`,
            randomElement(cities),
            randomElement(["NY", "CA", "TX", "IL", "ON", "BC"]),
            `${randomInt(10000, 99999)}`,
            randomElement(["USA", "Canada", "UK"])
          ]);
        }
      }
      
      const finalCount = await pool.query(`SELECT COUNT(*) as count FROM customer_addresses`);
      console.log(`   ✅ Created ${finalCount.rows[0].count} customer addresses\n`);
    } else {
      console.log(`✅ customer_addresses: ${addressCount.rows[0].count} rows (already populated)\n`);
    }

    // Verify all tables
    console.log("🔍 Verifying all tables...\n");
    const tables = await pool.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name
    `);

    let allPopulated = true;
    for (const row of tables.rows) {
      const count = await pool.query(`SELECT COUNT(*) as count FROM ${row.table_name}`);
      const tableCount = parseInt(count.rows[0].count);
      
      if (tableCount === 0) {
        console.log(`❌ ${row.table_name}: 0 rows`);
        allPopulated = false;
      } else {
        console.log(`✅ ${row.table_name}: ${tableCount} rows`);
      }
    }

    await pool.end();

    if (allPopulated) {
      console.log(`\n✅ All tables are populated!`);
      process.exit(0);
    } else {
      console.log(`\n⚠️  Some tables are still empty`);
      process.exit(1);
    }
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

fillEmptyTables();

