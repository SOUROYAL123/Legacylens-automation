-- 1. Create the tables
CREATE TABLE tenants (
    tenant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL
);

CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id),
    amount DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Lock down the table with Row Level Security (RLS)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON orders
    FOR ALL TO PUBLIC
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::UUID);

-- 3. Add the performance index
CREATE INDEX idx_orders_tenant_created ON orders(tenant_id, created_at DESC);