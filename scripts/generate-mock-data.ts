import "dotenv/config";
import { Pool } from "pg";
import { getConfig } from "../src/utils/config";

const pool = new Pool({
  connectionString: getConfig().SUPABASE_DB_URL,
  ssl: { rejectUnauthorized: false },
});

const names = [
  "Emma Johnson", "Liam Smith", "Olivia Brown", "Noah Williams", "Ava Jones",
  "Ethan Garcia", "Sophia Miller", "Mason Davis", "Isabella Rodriguez", "Lucas Martinez",
  "Mia Anderson", "Alexander Taylor", "Charlotte Thomas", "Benjamin Jackson", "Amelia White",
  "Henry Harris", "Harper Martin", "Sebastian Thompson", "Evelyn Moore", "Aiden Clark",
];

const emails = names.map(name => {
  const parts = name.toLowerCase().split(" ");
  return `${parts[0]}.${parts[1]}@example.com`;
});

const products = [
  { title: "Classic Cotton T-Shirt", type: "Apparel", vendor: "Fashion Co", price: 29.99, cost: 12.00 },
  { title: "Premium Denim Jeans", type: "Apparel", vendor: "Fashion Co", price: 79.99, cost: 35.00 },
  { title: "Leather Backpack", type: "Accessories", vendor: "Leather Works", price: 129.99, cost: 55.00 },
  { title: "Wireless Headphones", type: "Electronics", vendor: "TechCorp", price: 199.99, cost: 80.00 },
  { title: "Stainless Steel Water Bottle", type: "Accessories", vendor: "EcoLife", price: 24.99, cost: 10.00 },
  { title: "Yoga Mat Premium", type: "Fitness", vendor: "FitLife", price: 49.99, cost: 18.00 },
  { title: "Organic Coffee Beans", type: "Food & Beverage", vendor: "Coffee Co", price: 16.99, cost: 7.00 },
  { title: "Wooden Watch", type: "Accessories", vendor: "TimeCraft", price: 89.99, cost: 40.00 },
  { title: "Canvas Sneakers", type: "Footwear", vendor: "ShoeBrand", price: 59.99, cost: 25.00 },
  { title: "Minimalist Wallet", type: "Accessories", vendor: "Leather Works", price: 39.99, cost: 15.00 },
];

const variants = [
  { option1: "Small", option2: "Black" },
  { option1: "Medium", option2: "Black" },
  { option1: "Large", option2: "Black" },
  { option1: "Small", option2: "White" },
  { option1: "Medium", option2: "White" },
  { option1: "Large", option2: "Blue" },
];

const campaigns = [
  { name: "Summer Sale 2024", type: "email" },
  { name: "New Arrivals", type: "email" },
  { name: "Abandoned Cart Reminder", type: "email" },
  { name: "Black Friday Deals", type: "email" },
  { name: "Welcome Series", type: "email" },
  { name: "Flash Sale Alert", type: "sms" },
];

const flows = [
  { name: "Welcome Series", trigger_type: "welcome_series" },
  { name: "Abandoned Cart Recovery", trigger_type: "abandoned_cart" },
  { name: "Browse Abandonment", trigger_type: "browse_abandonment" },
  { name: "Post Purchase Follow-up", trigger_type: "post_purchase" },
];

function randomDate(start: Date, end: Date): Date {
  return new Date(start.getTime() + Math.random() * (end.getTime() - start.getTime()));
}

function randomElement<T>(array: T[]): T {
  return array[Math.floor(Math.random() * array.length)];
}

function randomInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

async function generateMockData() {
  console.log("🚀 Generating mock data...\n");

  try {
    // 1. Create Customers
    console.log("1️⃣ Creating customers...");
    const customerIds: string[] = [];
    for (let i = 0; i < names.length; i++) {
      const nameParts = names[i].split(" ");
      const isFirstTime = i < 5;
      const totalOrders = isFirstTime ? 1 : randomInt(2, 8);
      const totalRevenue = totalOrders * randomInt(50, 500);
      const aov = totalRevenue / totalOrders;
      
      const firstOrderDate = randomDate(new Date(2024, 0, 1), new Date());
      const lastOrderDate = new Date(firstOrderDate);
      lastOrderDate.setDate(lastOrderDate.getDate() + randomInt(0, 90));

      const result = await pool.query(`
        INSERT INTO customers (
          shopify_customer_id, klaviyo_profile_id, email, phone, first_name, last_name,
          location_country, location_region, location_city, timezone,
          is_first_time_customer, total_orders, total_revenue, average_order_value,
          first_order_date, last_order_date, tags, marketing_consent_email, source
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
        RETURNING id
      `, [
        `shopify_${i + 1000}`,
        `klaviyo_${i + 2000}`,
        emails[i],
        `+1-555-${randomInt(100, 999)}-${randomInt(1000, 9999)}`,
        nameParts[0],
        nameParts[1],
        randomElement(["USA", "Canada", "UK", "Australia"]),
        randomElement(["CA", "NY", "TX", "FL", "ON", "BC"]),
        randomElement(["New York", "Los Angeles", "Toronto", "London", "Sydney"]),
        randomElement(["America/New_York", "America/Los_Angeles", "America/Toronto", "Europe/London"]),
        isFirstTime,
        totalOrders,
        totalRevenue,
        aov,
        firstOrderDate.toISOString().split('T')[0],
        lastOrderDate.toISOString().split('T')[0],
        isFirstTime ? ['new'] : ['vip', 'repeat'],
        true,
        randomElement(['shopify', 'klaviyo', 'api'])
      ]);
      customerIds.push(result.rows[0].id);
    }
    console.log(`   ✅ Created ${customerIds.length} customers\n`);

    // 1b. Create Customer Addresses
    console.log("1️⃣b Creating customer addresses...");
    const streets = ["Main St", "Oak Ave", "Park Blvd", "Maple Dr", "Elm St", "First Ave", "Second St"];
    const cities = ["New York", "Los Angeles", "Chicago", "Houston", "Toronto", "Vancouver", "London"];
    
    for (let i = 0; i < customerIds.length; i++) {
      // Shipping address
      await pool.query(`
        INSERT INTO customer_addresses (
          customer_id, shopify_address_id, type, is_default, address_line1,
          city, province, postal_code, country
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      `, [
        customerIds[i],
        `addr_shipping_${i + 1}`,
        'shipping',
        true,
        `${randomInt(100, 9999)} ${randomElement(streets)}`,
        randomElement(cities),
        randomElement(["NY", "CA", "TX", "IL", "ON", "BC"]),
        `${randomInt(10000, 99999)}`,
        randomElement(["USA", "Canada", "UK"])
      ]);

      // Billing address (sometimes same, sometimes different)
      if (Math.random() > 0.3) {
        await pool.query(`
          INSERT INTO customer_addresses (
            customer_id, shopify_address_id, type, is_default, address_line1,
            city, province, postal_code, country
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
          customerIds[i],
          `addr_billing_${i + 1}`,
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
    console.log(`   ✅ Created customer addresses\n`);

    // 2. Create Shopify Products and Variants
    console.log("2️⃣ Creating products and variants...");
    const productIds: string[] = [];
    const variantIds: Map<string, string[]> = new Map();

    for (let i = 0; i < products.length; i++) {
      const product = products[i];
      const productResult = await pool.query(`
        INSERT INTO shopify_products (
          shopify_product_id, title, handle, product_type, vendor, tags, status, published_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
      `, [
        `prod_${i + 1}`,
        product.title,
        product.title.toLowerCase().replace(/\s+/g, '-'),
        product.type,
        product.vendor,
        [product.type.toLowerCase(), 'featured'],
        'active',
        randomDate(new Date(2023, 0, 1), new Date()).toISOString()
      ]);
      productIds.push(productResult.rows[0].id);

      // Create variants
      const productVariants: string[] = [];
      const numVariants = randomInt(2, 4);
      for (let v = 0; v < numVariants; v++) {
        const variant = randomElement(variants);
        const variantResult = await pool.query(`
          INSERT INTO shopify_product_variants (
            product_id, shopify_variant_id, sku, title, price, cost, compare_at_price,
            inventory_quantity, inventory_policy, option1, option2
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
          RETURNING id
        `, [
          productResult.rows[0].id,
          `var_${i + 1}_${v + 1}`,
          `SKU-${i + 1}-${v + 1}`,
          `${variant.option1} / ${variant.option2}`,
          product.price,
          product.cost,
          product.price * 1.2,
          randomInt(10, 100),
          'deny',
          variant.option1,
          variant.option2
        ]);
        productVariants.push(variantResult.rows[0].id);
      }
      variantIds.set(productResult.rows[0].id, productVariants);
    }
    console.log(`   ✅ Created ${productIds.length} products with variants\n`);

    // 3. Create Shopify Orders and Line Items
    console.log("3️⃣ Creating orders and line items...");
    const orderIds: string[] = [];
    for (let i = 0; i < customerIds.length; i++) {
      const numOrders = randomInt(1, 5);
      for (let o = 0; o < numOrders; o++) {
        const orderDate = randomDate(new Date(2024, 0, 1), new Date());
        const financialStatus = randomElement(['paid', 'paid', 'paid', 'pending', 'refunded']);
        const subtotal = randomInt(50, 500);
        const tax = subtotal * 0.08;
        const discount = randomInt(0, 50);
        const total = subtotal + tax - discount;

        const orderResult = await pool.query(`
          INSERT INTO shopify_orders (
            shopify_order_id, customer_id, order_number, order_date, source, financial_status,
            fulfillment_status, subtotal_price, total_tax, total_discounts, total_price,
            currency_code, payment_gateway, discount_codes, tags
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
          RETURNING id
        `, [
          `order_${i}_${o + 1}`,
          customerIds[i],
          `#${1000 + i * 10 + o}`,
          orderDate.toISOString(),
          randomElement(['online_store', 'pos', 'api']),
          financialStatus,
          randomElement(['fulfilled', 'partial', 'unfulfilled']),
          subtotal,
          tax,
          discount,
          total,
          'USD',
          randomElement(['stripe', 'paypal', 'shopify_payments']),
          discount > 0 ? ['SUMMER10'] : [],
          []
        ]);
        orderIds.push(orderResult.rows[0].id);

        // Create line items
        const numItems = randomInt(1, 4);
        const selectedProducts = productIds.slice(0, numItems);
        for (const productId of selectedProducts) {
          const productVariants = variantIds.get(productId) || [];
          const variantId = productVariants[0] || null;
          const quantity = randomInt(1, 3);
          const price = randomInt(20, 200);
          const lineDiscount = randomInt(0, 20);
          const lineTax = price * 0.08;
          const lineTotal = (price * quantity) - lineDiscount + lineTax;

          await pool.query(`
            INSERT INTO shopify_order_line_items (
              order_id, shopify_line_item_id, product_id, variant_id, sku, title,
              quantity, price, total_discount, total_tax, line_total, fulfillment_status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
          `, [
            orderResult.rows[0].id,
            `line_${i}_${o}_${Math.random().toString(36).substr(2, 9)}`,
            productId,
            variantId,
            `SKU-${Math.random().toString(36).substr(2, 6)}`,
            randomElement(products).title,
            quantity,
            price,
            lineDiscount,
            lineTax,
            lineTotal,
            randomElement(['fulfilled', 'pending'])
          ]);
        }
      }
    }
    console.log(`   ✅ Created ${orderIds.length} orders with line items\n`);

    // 4. Create Klaviyo Profiles
    console.log("4️⃣ Creating Klaviyo profiles...");
    const profileIds: string[] = [];
    for (let i = 0; i < customerIds.length; i++) {
      const result = await pool.query(`
        INSERT INTO klaviyo_profiles (
          klaviyo_profile_id, customer_id, email, phone, first_name, last_name,
          location_properties, properties
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING id
      `, [
        `klaviyo_${i + 2000}`,
        customerIds[i],
        emails[i],
        `+1-555-${randomInt(100, 999)}-${randomInt(1000, 9999)}`,
        names[i].split(" ")[0],
        names[i].split(" ")[1],
        JSON.stringify({
          timezone: randomElement(["America/New_York", "America/Los_Angeles"]),
          country: randomElement(["USA", "Canada"])
        }),
        JSON.stringify({
          lifetime_value: randomInt(100, 1000),
          favorite_category: randomElement(["Apparel", "Electronics", "Accessories"])
        })
      ]);
      profileIds.push(result.rows[0].id);
    }
    console.log(`   ✅ Created ${profileIds.length} Klaviyo profiles\n`);

    // 5. Create Klaviyo Campaigns
    console.log("5️⃣ Creating Klaviyo campaigns...");
    const campaignIds: string[] = [];
    for (let i = 0; i < campaigns.length; i++) {
      const campaign = campaigns[i];
      const sendDate = randomDate(new Date(2024, 0, 1), new Date());
      const recipients = randomInt(500, 5000);
      const delivered = Math.floor(recipients * 0.95);
      const uniqueOpens = Math.floor(delivered * randomInt(15, 30) / 100);
      const uniqueClicks = Math.floor(delivered * randomInt(2, 5) / 100);
      const revenue = randomInt(500, 5000);

      const result = await pool.query(`
        INSERT INTO klaviyo_campaigns (
          klaviyo_campaign_id, name, type, send_date, status, recipients_count,
          delivered_count, opens_count, unique_opens_count, clicks_count,
          unique_clicks_count, unsubscribes_count, bounces_count, revenue
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
        RETURNING id
      `, [
        `campaign_${i + 1}`,
        campaign.name,
        campaign.type,
        sendDate.toISOString(),
        'sent',
        recipients,
        delivered,
        uniqueOpens + randomInt(0, 50),
        uniqueOpens,
        uniqueClicks + randomInt(0, 20),
        uniqueClicks,
        randomInt(0, 10),
        randomInt(0, 5),
        revenue
      ]);
      campaignIds.push(result.rows[0].id);
    }
    console.log(`   ✅ Created ${campaignIds.length} campaigns\n`);

    // 6. Create Klaviyo Flows and Steps
    console.log("6️⃣ Creating Klaviyo flows...");
    const flowIds: string[] = [];
    for (let i = 0; i < flows.length; i++) {
      const flow = flows[i];
      const recipients = randomInt(200, 2000);
      const conversions = Math.floor(recipients * randomInt(5, 15) / 100);
      const revenue = conversions * randomInt(50, 200);

      const flowResult = await pool.query(`
        INSERT INTO klaviyo_flows (
          klaviyo_flow_id, name, trigger_type, status, recipients_entered_count,
          conversion_count, revenue
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING id
      `, [
        `flow_${i + 1}`,
        flow.name,
        flow.trigger_type,
        'live',
        recipients,
        conversions,
        revenue
      ]);
      flowIds.push(flowResult.rows[0].id);

      // Create flow steps
      const numSteps = randomInt(3, 5);
      for (let s = 0; s < numSteps; s++) {
        await pool.query(`
          INSERT INTO klaviyo_flow_steps (
            flow_id, klaviyo_step_id, step_name, step_order, step_type,
            recipients_count, opens_count, clicks_count, conversions_count
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
          flowResult.rows[0].id,
          `step_${i}_${s + 1}`,
          `Email ${s + 1}`,
          s + 1,
          'email',
          recipients - (s * 50),
          Math.floor((recipients - (s * 50)) * 0.25),
          Math.floor((recipients - (s * 50)) * 0.03),
          s === numSteps - 1 ? conversions : 0
        ]);
      }
    }
    console.log(`   ✅ Created ${flowIds.length} flows with steps\n`);

    // 7. Create Events
    console.log("7️⃣ Creating events...");
    
    // Shopify events
    for (let i = 0; i < orderIds.length * 3; i++) {
      const customerId = randomElement(customerIds);
      const productId = randomElement(productIds);
      const eventTypes = ['product_viewed', 'cart_added', 'checkout_started', 'checkout_completed'];
      
      await pool.query(`
        INSERT INTO shopify_events (
          event_type, customer_id, product_id, session_id, event_properties, occurred_at
        ) VALUES ($1, $2, $3, $4, $5, $6)
      `, [
        randomElement(eventTypes),
        customerId,
        productId,
        `session_${randomInt(1000, 9999)}`,
        JSON.stringify({
          referrer: randomElement(['google', 'direct', 'facebook', 'email']),
          device: randomElement(['desktop', 'mobile', 'tablet']),
          utm_source: randomElement(['email', 'social', 'search', null]),
        }),
        randomDate(new Date(2024, 0, 1), new Date()).toISOString()
      ]);
    }

    // Klaviyo events
    for (let i = 0; i < profileIds.length * 5; i++) {
      const profileId = randomElement(profileIds);
      const customerId = customerIds[profileIds.indexOf(profileId)];
      const campaignId = randomElement(campaignIds);
      
      await pool.query(`
        INSERT INTO klaviyo_events (
          event_type, profile_id, customer_id, campaign_id, event_properties, occurred_at
        ) VALUES ($1, $2, $3, $4, $5, $6)
      `, [
        randomElement(['Opened Email', 'Clicked Email', 'Placed Order', 'Viewed Product']),
        profileId,
        customerId,
        campaignId,
        JSON.stringify({
          subject: randomElement(['Summer Sale', 'New Arrivals', 'Special Offer']),
          link_clicked: randomElement(['product', 'cta', 'footer']),
        }),
        randomDate(new Date(2024, 0, 1), new Date()).toISOString()
      ]);
    }
    console.log(`   ✅ Created shopify_events and klaviyo_events\n`);

    // 8. Create Ad Events
    console.log("8️⃣ Creating ad events...");
    const platforms = ['meta', 'google', 'tiktok'];
    for (let i = 0; i < 30; i++) {
      const date = randomDate(new Date(2024, 0, 1), new Date());
      const spend = randomInt(50, 500);
      const impressions = randomInt(1000, 50000);
      const clicks = Math.floor(impressions * randomInt(1, 3) / 100);
      const conversions = Math.floor(clicks * randomInt(2, 5) / 100);
      const revenue = conversions * randomInt(50, 300);

      await pool.query(`
        INSERT INTO ad_events (
          platform, campaign_id, spend, impressions, clicks, conversions, revenue, date
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [
        randomElement(platforms),
        `ad_campaign_${randomInt(1, 10)}`,
        spend,
        impressions,
        clicks,
        conversions,
        revenue,
        date.toISOString().split('T')[0]
      ]);
    }
    console.log(`   ✅ Created ad events\n`);

    // 9. Create Lists and Segments
    console.log("9️⃣ Creating lists and segments...");
    const listNames = ['VIP Customers', 'Newsletter Subscribers', 'Abandoned Cart', 'High Value'];
    const listIds: string[] = [];
    
    for (const listName of listNames) {
      const result = await pool.query(`
        INSERT INTO klaviyo_lists (klaviyo_list_id, name, profile_count)
        VALUES ($1, $2, $3)
        RETURNING id
      `, [`list_${listNames.indexOf(listName) + 1}`, listName, randomInt(50, 500)]);
      listIds.push(result.rows[0].id);
    }

    // Add profiles to lists
    for (let i = 0; i < profileIds.length; i++) {
      if (Math.random() > 0.5) {
        await pool.query(`
          INSERT INTO klaviyo_profile_lists (profile_id, list_id)
          VALUES ($1, $2)
          ON CONFLICT DO NOTHING
        `, [profileIds[i], randomElement(listIds)]);
      }
    }

    const segmentNames = ['High Value Customers', 'At Risk', 'New Customers', 'Engaged Users'];
    for (const segmentName of segmentNames) {
      await pool.query(`
        INSERT INTO klaviyo_segments (klaviyo_segment_id, name, rule_logic, profile_count)
        VALUES ($1, $2, $3, $4)
      `, [
        `segment_${segmentNames.indexOf(segmentName) + 1}`,
        segmentName,
        JSON.stringify({ condition: 'AND', rules: [] }),
        randomInt(20, 200)
      ]);
    }
    console.log(`   ✅ Created lists and segments\n`);

    // 10. Create Predictive Metrics
    console.log("🔟 Creating predictive metrics...");
    for (let i = 0; i < profileIds.length; i++) {
      const nextOrderDate = randomDate(new Date(), new Date(2025, 11, 31));
      await pool.query(`
        INSERT INTO klaviyo_predictive_metrics (
          profile_id, predicted_next_order_date, predicted_churn_probability,
          predicted_lifetime_value, email_engagement_probability, calculated_at
        ) VALUES ($1, $2, $3, $4, $5, $6)
      `, [
        profileIds[i],
        nextOrderDate.toISOString().split('T')[0],
        parseFloat((Math.random() * 0.5).toFixed(4)),
        randomInt(200, 2000),
        parseFloat((0.3 + Math.random() * 0.4).toFixed(4)),
        new Date().toISOString()
      ]);
    }
    console.log(`   ✅ Created predictive metrics\n`);

    // 11. Populate Daily Aggregation Tables
    console.log("1️⃣1️⃣ Populating daily aggregation tables...");
    const today = new Date();
    for (let i = 0; i < customerIds.length; i++) {
      const numDays = randomInt(5, 30);
      for (let d = 0; d < numDays; d++) {
        const date = new Date(today);
        date.setDate(date.getDate() - d);

        await pool.query(`
          INSERT INTO customer_metrics_daily (
            customer_id, date, orders_count, revenue, products_viewed_count,
            cart_adds_count, checkouts_started_count, emails_opened_count, emails_clicked_count
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          ON CONFLICT (customer_id, date) DO NOTHING
        `, [
          customerIds[i],
          date.toISOString().split('T')[0],
          d % 3 === 0 ? 1 : 0,
          d % 3 === 0 ? randomInt(50, 300) : 0,
          randomInt(0, 5),
          randomInt(0, 3),
          randomInt(0, 2),
          randomInt(0, 3),
          randomInt(0, 1)
        ]);
      }
    }

    for (const campaignId of campaignIds) {
      const sendDate = randomDate(new Date(2024, 0, 1), new Date());
      await pool.query(`
        INSERT INTO campaign_performance_daily (
          campaign_id, date, sent_count, delivered_count, opens_count,
          clicks_count, unsubscribes_count, revenue
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (campaign_id, date) DO NOTHING
      `, [
        campaignId,
        sendDate.toISOString().split('T')[0],
        randomInt(500, 5000),
        randomInt(475, 4750),
        randomInt(100, 1000),
        randomInt(20, 200),
        randomInt(0, 10),
        randomInt(500, 5000)
      ]);
    }

    for (const productId of productIds) {
      const numDays = randomInt(10, 60);
      for (let d = 0; d < numDays; d++) {
        const date = new Date(today);
        date.setDate(date.getDate() - d);
        
        await pool.query(`
          INSERT INTO product_performance_daily (
            product_id, date, views_count, cart_adds_count, orders_count,
            units_sold, revenue
          ) VALUES ($1, $2, $3, $4, $5, $6, $7)
          ON CONFLICT (product_id, date) DO NOTHING
        `, [
          productId,
          date.toISOString().split('T')[0],
          randomInt(10, 100),
          randomInt(5, 50),
          randomInt(1, 20),
          randomInt(1, 30),
          randomInt(50, 1000)
        ]);
      }
    }
    console.log(`   ✅ Populated daily aggregation tables\n`);

    console.log("\n✅ Mock data generation complete!\n");
    console.log("📊 Summary:");
    const counts = await pool.query(`
      SELECT 
        (SELECT COUNT(*) FROM customers) as customers,
        (SELECT COUNT(*) FROM shopify_orders) as orders,
        (SELECT COUNT(*) FROM shopify_products) as products,
        (SELECT COUNT(*) FROM klaviyo_profiles) as profiles,
        (SELECT COUNT(*) FROM klaviyo_campaigns) as campaigns,
        (SELECT COUNT(*) FROM shopify_events) as shopify_events,
        (SELECT COUNT(*) FROM klaviyo_events) as klaviyo_events,
        (SELECT COUNT(*) FROM ad_events) as ad_events
    `);
    
    const summary = counts.rows[0];
    console.log(`   - Customers: ${summary.customers}`);
    console.log(`   - Orders: ${summary.orders}`);
    console.log(`   - Products: ${summary.products}`);
    console.log(`   - Klaviyo Profiles: ${summary.profiles}`);
    console.log(`   - Campaigns: ${summary.campaigns}`);
    console.log(`   - Shopify Events: ${summary.shopify_events}`);
    console.log(`   - Klaviyo Events: ${summary.klaviyo_events}`);
    console.log(`   - Ad Events: ${summary.ad_events}\n`);

    await pool.end();
  } catch (error: any) {
    console.error("❌ Error:", error.message);
    await pool.end();
    process.exit(1);
  }
}

generateMockData();

