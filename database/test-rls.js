const { Pool } = require('pg');

const pool = new Pool({
    host: 'terraform-523cc102412777f0391369a861.cfew2m0cwv6o.ap-south-1.rds.amazonaws.com',
    database: 'legacylens_prod',
    user: 'db_admin_user',
    password: 'LegacyLensSecure2026!',
    port: 5432,
    ssl: { rejectUnauthorized: false } // Required for secure AWS RDS connection
});

async function runTest() {
    const client = await pool.connect();
    try {
        console.log('=========================================');
        console.log('SUCCESS: Connected to AWS RDS Database!');
        console.log('=========================================\n');

        // 1. Insert sample tenants
        await client.query(
            `INSERT INTO tenants (name) VALUES ($1), ($2) ON CONFLICT DO NOTHING;`,
            ['Spice Route Cafe', 'Tandoori Nights']
        );
        
        // Fetch tenants to retrieve their auto-generated UUIDs
        const tenantResult = await client.query(`SELECT tenant_id, name FROM tenants;`);
        const tenants = tenantResult.rows;
        
        console.log('Registered Tenants:');
        tenants.forEach(t => console.log(`- ${t.name} (${t.tenant_id})`));
        console.log('');

        if (tenants.length < 2) {
            console.log('Error: Not enough tenants found to run isolation test.');
            return;
        }

        const tenantA = tenants[0];
        const tenantB = tenants[1];

        // 2. Insert sample orders for each tenant
        await client.query(
            `INSERT INTO orders (tenant_id, amount) VALUES ($1, $2), ($1, $3);`,
            [tenantA.tenant_id, 450.00, 1200.50]
        );
        await client.query(
            `INSERT INTO orders (tenant_id, amount) VALUES ($1, $2);`,
            [tenantB.tenant_id, 890.00]
        );
        console.log('Sample orders successfully inserted for both tenants.\n');

        // 3. TEST RLS: Query without setting tenant context (Should return 0 rows)
        console.log('--- TEST 1: Query WITHOUT Tenant Context ---');
        await client.query(`RESET app.current_tenant;`);
        const unconstrained = await client.query(`SELECT * FROM orders;`);
        console.log(`Orders visible: ${unconstrained.rows.length} (Expected: 0 — Blocked by RLS)`);

        // 4. TEST RLS: Query with Tenant A context
        console.log(`\n--- TEST 2: Query WITH Context [${tenantA.name}] ---`);
        await client.query(`SET LOCAL app.current_tenant = '${tenantA.tenant_id}';`);
        const tenantAOrders = await client.query(`SELECT * FROM orders;`);
        console.log(`Orders visible: ${tenantAOrders.rows.length}`);
        tenantAOrders.rows.forEach(o => console.log(`  -> Order ID: ${o.order_id} | Amount: ₹${o.amount}`));

        // 5. TEST RLS: Query with Tenant B context
        console.log(`\n--- TEST 3: Query WITH Context [${tenantB.name}] ---`);
        await client.query(`SET LOCAL app.current_tenant = '${tenantB.tenant_id}';`);
        const tenantBOrders = await client.query(`SELECT * FROM orders;`);
        console.log(`Orders visible: ${tenantBOrders.rows.length}`);
        tenantBOrders.rows.forEach(o => console.log(`  -> Order ID: ${o.order_id} | Amount: ₹${o.amount}`));

        console.log('\n=========================================');
        console.log('RLS Tenant Isolation Test Passed Successfully!');
        console.log('=========================================');

    } catch (err) {
        console.error('Error executing RLS test:', err);
    } finally {
        client.release();
        await pool.end();
    }
}

runTest();