#!/usr/bin/env tsx
/**
 * Quick deployment script for Supabase
 *
 * Usage:
 *   npm install -g tsx
 *   tsx scripts/deploy-to-supabase.ts
 *
 * Or add to package.json:
 *   "deploy:supabase": "tsx scripts/deploy-to-supabase.ts"
 */

import * as fs from 'fs';
import * as path from 'path';
import { Pool } from 'pg';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

const MIGRATIONS_DIR = path.join(process.cwd(), 'supabase', 'migrations');
const EXTENSIONS_FILE = path.join(process.cwd(), 'supabase', 'extensions.sql');

async function deploy() {
  const dbUrl = process.env.SUPABASE_DB_URL;

  if (!dbUrl) {
    console.error('❌ Error: SUPABASE_DB_URL not found in environment variables');
    console.error('   Please set it in your .env file:');
    console.error('   SUPABASE_DB_URL=postgresql://postgres:password@db.xxxxx.supabase.co:5432/postgres');
    process.exit(1);
  }

  console.log('🚀 Starting deployment to Supabase...\n');

  const pool = new Pool({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false }
  });

  try {
    // Test connection
    console.log('🔌 Testing database connection...');
    await pool.query('SELECT 1');
    console.log('✅ Connected successfully!\n');

    // Apply extensions first
    if (fs.existsSync(EXTENSIONS_FILE)) {
      console.log('📦 Installing extensions...');
      const extensionsSql = fs.readFileSync(EXTENSIONS_FILE, 'utf8');
      await pool.query(extensionsSql);
      console.log('✅ Extensions installed\n');
    }

    // Get all migration files
    const migrationFiles = fs.readdirSync(MIGRATIONS_DIR)
      .filter(file => file.endsWith('.sql'))
      .sort();

    console.log(`📝 Found ${migrationFiles.length} migrations:\n`);
    migrationFiles.forEach((file, idx) => {
      console.log(`   ${idx + 1}. ${file}`);
    });
    console.log('');

    // Apply each migration
    for (const file of migrationFiles) {
      console.log(`⏳ Applying: ${file}...`);
      const filePath = path.join(MIGRATIONS_DIR, file);
      const sql = fs.readFileSync(filePath, 'utf8');

      try {
        await pool.query(sql);
        console.log(`✅ Applied: ${file}`);
      } catch (error: any) {
        console.error(`❌ Error in ${file}:`);
        console.error(`   ${error.message}`);
        throw error;
      }
    }

    console.log('\n🎉 All migrations applied successfully!\n');

    // Verify installation
    console.log('🔍 Verifying installation...');

    const tablesResult = await pool.query(`
      SELECT COUNT(*) as count
      FROM information_schema.tables
      WHERE table_schema = 'public'
    `);
    console.log(`✅ Tables created: ${tablesResult.rows[0].count}`);

    const viewsResult = await pool.query(`
      SELECT COUNT(*) as count
      FROM pg_matviews
      WHERE schemaname = 'public'
    `);
    console.log(`✅ Materialized views: ${viewsResult.rows[0].count}`);

    const functionsResult = await pool.query(`
      SELECT COUNT(*) as count
      FROM information_schema.routines
      WHERE routine_schema = 'public'
      AND routine_type = 'FUNCTION'
    `);
    console.log(`✅ Functions created: ${functionsResult.rows[0].count}`);

    console.log('\n✨ Deployment complete! Your data warehouse is ready.');
    console.log('\n📚 Next steps:');
    console.log('   1. Generate sample data: npm run data:mock');
    console.log('   2. Populate metrics: npm run metrics:acquisition');
    console.log('   3. Query metrics: npm run metrics:all');
    console.log('   4. View in Supabase dashboard: SQL Editor\n');

  } catch (error: any) {
    console.error('\n❌ Deployment failed!');
    console.error('Error:', error.message);
    console.error('\n💡 Tips:');
    console.error('   - Check your SUPABASE_DB_URL is correct');
    console.error('   - Verify database password');
    console.error('   - Ensure you have necessary permissions');
    console.error('   - Check Supabase dashboard for more details\n');
    process.exit(1);
  } finally {
    await pool.end();
  }
}

// Run deployment
deploy();
