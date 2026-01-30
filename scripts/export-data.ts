#!/usr/bin/env tsx
/**
 * Export all data from Supabase database
 *
 * Usage:
 *   tsx scripts/export-data.ts
 *   npm run data:export
 *
 * This will create SQL INSERT statements for all tables
 */

import * as fs from 'fs';
import * as path from 'path';
import { Pool } from 'pg';
import * as dotenv from 'dotenv';

dotenv.config();

const OUTPUT_DIR = path.join(process.cwd(), 'supabase', 'seed');
const OUTPUT_FILE = path.join(OUTPUT_DIR, 'data.sql');

async function exportData() {
  const dbUrl = process.env.SUPABASE_DB_URL;

  if (!dbUrl) {
    console.error('❌ Error: SUPABASE_DB_URL not found in .env file');
    process.exit(1);
  }

  console.log('🚀 Starting data export from Supabase...\n');

  const pool = new Pool({
    connectionString: dbUrl,
    ssl: {
      rejectUnauthorized: false
    }
  });

  try {
    // Test connection
    console.log('🔌 Connecting to database...');
    await pool.query('SELECT 1');
    console.log('✅ Connected!\n');

    // Create output directory
    if (!fs.existsSync(OUTPUT_DIR)) {
      fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    }

    // Get all tables in public schema
    console.log('📋 Finding all tables...');
    const tablesResult = await pool.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name
    `);

    const tables = tablesResult.rows.map(row => row.table_name);
    console.log(`✅ Found ${tables.length} tables\n`);

    let sqlOutput = `-- Data export from Supabase
-- Generated: ${new Date().toISOString()}
-- Database: ${dbUrl.split('@')[1].split('/')[0]}

-- Disable triggers during import for better performance
SET session_replication_role = 'replica';

`;

    let totalRows = 0;

    // Export each table
    for (const table of tables) {
      console.log(`📦 Exporting: ${table}...`);

      // Get row count
      const countResult = await pool.query(`SELECT COUNT(*) as count FROM "${table}"`);
      const rowCount = parseInt(countResult.rows[0].count);

      if (rowCount === 0) {
        console.log(`   ⚠️  Empty (0 rows)\n`);
        continue;
      }

      // Get all columns
      const columnsResult = await pool.query(`
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = $1
        ORDER BY ordinal_position
      `, [table]);

      const columns = columnsResult.rows.map(r => r.column_name);

      // Get all data
      const dataResult = await pool.query(`SELECT * FROM "${table}"`);

      if (dataResult.rows.length > 0) {
        sqlOutput += `\n-- Table: ${table} (${dataResult.rows.length} rows)\n`;
        sqlOutput += `TRUNCATE TABLE "${table}" CASCADE;\n`;

        // Generate INSERT statements
        for (const row of dataResult.rows) {
          const values = columns.map(col => {
            const value = row[col];

            if (value === null) {
              return 'NULL';
            } else if (typeof value === 'string') {
              // Escape single quotes and wrap in quotes
              return `'${value.replace(/'/g, "''")}'`;
            } else if (typeof value === 'boolean') {
              return value ? 'TRUE' : 'FALSE';
            } else if (value instanceof Date) {
              return `'${value.toISOString()}'`;
            } else if (Array.isArray(value)) {
              // Handle arrays (like tags)
              return `ARRAY[${value.map(v => `'${v.replace(/'/g, "''")}'`).join(',')}]`;
            } else if (typeof value === 'object') {
              // Handle JSON objects
              return `'${JSON.stringify(value).replace(/'/g, "''")}'::jsonb`;
            } else {
              return value;
            }
          });

          sqlOutput += `INSERT INTO "${table}" (${columns.map(c => `"${c}"`).join(', ')}) VALUES (${values.join(', ')});\n`;
        }

        totalRows += dataResult.rows.length;
        console.log(`   ✅ ${dataResult.rows.length} rows\n`);
      }
    }

    sqlOutput += `\n-- Re-enable triggers
SET session_replication_role = 'origin';

-- Refresh materialized views
SELECT 'Refreshing materialized views...' as status;
`;

    // Add refresh commands for materialized views
    const viewsResult = await pool.query(`
      SELECT matviewname
      FROM pg_matviews
      WHERE schemaname = 'public'
    `);

    for (const view of viewsResult.rows) {
      sqlOutput += `REFRESH MATERIALIZED VIEW CONCURRENTLY ${view.matviewname};\n`;
    }

    sqlOutput += `\nSELECT 'Data import complete!' as status;\n`;

    // Write to file
    fs.writeFileSync(OUTPUT_FILE, sqlOutput);

    console.log(`\n✅ Export complete!`);
    console.log(`\n📊 Summary:`);
    console.log(`   Tables exported: ${tables.length}`);
    console.log(`   Total rows: ${totalRows}`);
    console.log(`   Output file: ${OUTPUT_FILE}`);
    console.log(`   File size: ${(fs.statSync(OUTPUT_FILE).size / 1024).toFixed(2)} KB`);

    console.log(`\n📤 To share this data:`);
    console.log(`   1. Commit the file: git add supabase/seed/data.sql`);
    console.log(`   2. Push to GitHub`);
    console.log(`   3. Recipients can run: npm run data:import`);

  } catch (error: any) {
    console.error('\n❌ Export failed!');
    console.error('Error:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

exportData();
