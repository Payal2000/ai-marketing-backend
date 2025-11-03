import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

async function generateMockData() {
  try {
    console.log("🔄 Generating advocacy mock data...\n");

    // Get existing customers and orders
    const customers = await pool.query(`SELECT id, email, total_orders, total_revenue FROM customers WHERE total_orders > 0 ORDER BY total_revenue DESC LIMIT 20`);
    const orders = await pool.query(`SELECT id, customer_id, order_date FROM shopify_orders WHERE financial_status = 'paid' ORDER BY order_date DESC LIMIT 50`);

    if (customers.rows.length === 0) {
      console.log("⚠️  No customers found. Run data:mock first.");
      await pool.end();
      process.exit(0);
    }

    console.log(`📊 Found ${customers.rows.length} customers and ${orders.rows.length} orders\n`);

    // 1. Generate NPS Surveys
    console.log("1️⃣ Generating NPS Surveys...");
    let npsCount = 0;
    for (const customer of customers.rows.slice(0, 15)) {
      const npsScore = Math.floor(Math.random() * 11); // 0-10
      const order = orders.rows[Math.floor(Math.random() * orders.rows.length)];
      const surveyDate = order ? new Date(order.order_date) : new Date();
      surveyDate.setDate(surveyDate.getDate() + Math.floor(Math.random() * 7) + 1); // 1-7 days after order

      try {
        await pool.query(`
          INSERT INTO nps_surveys (customer_id, order_id, nps_score, survey_type, survey_date)
          VALUES ($1, $2, $3, 'post_purchase', $4)
          ON CONFLICT DO NOTHING
        `, [customer.id, order?.id || null, npsScore, surveyDate.toISOString().split('T')[0]]);
        npsCount++;
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`   ✅ Generated ${npsCount} NPS surveys\n`);

    // 2. Generate Referrals
    console.log("2️⃣ Generating Referrals...");
    let referralCount = 0;
    const referrers = customers.rows.slice(0, 10);
    for (const referrer of referrers) {
      const referralCode = `REF${referrer.id.toString().substring(0, 8).toUpperCase()}`;
      const status = Math.random() > 0.5 ? 'converted' : (Math.random() > 0.5 ? 'completed' : 'pending');
      const referredCustomer = customers.rows[Math.floor(Math.random() * customers.rows.length)];
      
      try {
        await pool.query(`
          INSERT INTO referrals (referrer_customer_id, referred_customer_id, referral_code, referral_status)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT DO NOTHING
        `, [referrer.id, referredCustomer.id, referralCode, status]);
        referralCount++;
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`   ✅ Generated ${referralCount} referrals\n`);

    // 3. Generate Reviews
    console.log("3️⃣ Generating Reviews...");
    let reviewCount = 0;
    for (const order of orders.rows.slice(0, 30)) {
      const rating = Math.floor(Math.random() * 5) + 1; // 1-5
      const reviewText = rating >= 4 ? "Great product!" : (rating >= 3 ? "Good quality" : "Could be better");
      
      try {
        await pool.query(`
          INSERT INTO reviews (customer_id, order_id, rating, review_text, is_verified_purchase, status)
          VALUES ($1, $2, $3, $4, true, 'published')
          ON CONFLICT DO NOTHING
        `, [order.customer_id, order.id, rating, reviewText]);
        reviewCount++;
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`   ✅ Generated ${reviewCount} reviews\n`);

    // 4. Generate UGC Submissions
    console.log("4️⃣ Generating UGC Submissions...");
    let ugcCount = 0;
    const platforms = ['instagram', 'facebook', 'tiktok', 'website'];
    const submissionTypes = ['photo', 'video', 'testimonial', 'social_post'];
    
    for (const customer of customers.rows.slice(0, 12)) {
      const platform = platforms[Math.floor(Math.random() * platforms.length)];
      const type = submissionTypes[Math.floor(Math.random() * submissionTypes.length)];
      const status = Math.random() > 0.3 ? 'approved' : (Math.random() > 0.5 ? 'pending' : 'rejected');
      
      try {
        await pool.query(`
          INSERT INTO ugc_submissions (customer_id, submission_type, platform, status)
          VALUES ($1, $2, $3, $4)
          ON CONFLICT DO NOTHING
        `, [customer.id, type, platform, status]);
        ugcCount++;
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`   ✅ Generated ${ugcCount} UGC submissions\n`);

    // 5. Generate Loyalty Enrollments
    console.log("5️⃣ Generating Loyalty Enrollments...");
    let loyaltyCount = 0;
    const tiers = ['member', 'silver', 'gold', 'platinum', 'vip'];
    
    // Mark top customers as VIP in tags
    for (const customer of customers.rows.slice(0, 5)) {
      try {
        await pool.query(`
          UPDATE customers 
          SET tags = COALESCE(tags, ARRAY[]::text[]) || 'VIP'
          WHERE id = $1 AND NOT (tags @> ARRAY['VIP'])
        `, [customer.id]);
      } catch (error: any) {
        // Continue
      }
    }

    for (const customer of customers.rows) {
      const tier = tiers[Math.floor(Math.random() * tiers.length)];
      const points = tier === 'vip' ? 10000 + Math.floor(Math.random() * 5000) :
                     tier === 'platinum' ? 5000 + Math.floor(Math.random() * 3000) :
                     tier === 'gold' ? 2000 + Math.floor(Math.random() * 2000) :
                     tier === 'silver' ? 500 + Math.floor(Math.random() * 1000) :
                     Math.floor(Math.random() * 500);
      
      const enrollmentDate = customer.id ? new Date() : new Date();
      enrollmentDate.setDate(enrollmentDate.getDate() - Math.floor(Math.random() * 365));
      
      try {
        await pool.query(`
          INSERT INTO loyalty_enrollments (customer_id, loyalty_tier, points_balance, total_points_earned, enrollment_date)
          VALUES ($1, $2, $3, $4, $5)
          ON CONFLICT (customer_id) DO UPDATE SET
            loyalty_tier = EXCLUDED.loyalty_tier,
            points_balance = EXCLUDED.points_balance
        `, [customer.id, tier, points, points, enrollmentDate.toISOString().split('T')[0]]);
        loyaltyCount++;
      } catch (error: any) {
        // Continue on errors
      }
    }
    console.log(`   ✅ Generated ${loyaltyCount} loyalty enrollments\n`);

    // Show summary
    const finalCounts = {
      nps: (await pool.query(`SELECT COUNT(*) as count FROM nps_surveys`)).rows[0].count,
      referrals: (await pool.query(`SELECT COUNT(*) as count FROM referrals`)).rows[0].count,
      reviews: (await pool.query(`SELECT COUNT(*) as count FROM reviews`)).rows[0].count,
      ugc: (await pool.query(`SELECT COUNT(*) as count FROM ugc_submissions`)).rows[0].count,
      loyalty: (await pool.query(`SELECT COUNT(*) as count FROM loyalty_enrollments`)).rows[0].count
    };

    console.log("📊 Final Summary:");
    console.log(`   - NPS Surveys: ${finalCounts.nps} rows`);
    console.log(`   - Referrals: ${finalCounts.referrals} rows`);
    console.log(`   - Reviews: ${finalCounts.reviews} rows`);
    console.log(`   - UGC Submissions: ${finalCounts.ugc} rows`);
    console.log(`   - Loyalty Enrollments: ${finalCounts.loyalty} rows\n`);

    await pool.end();
    console.log("✅ Advocacy mock data generated!");
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

generateMockData();

