-- Day 11: Multi-Tenant Indexing and Query Optimization
BEGIN;

-- Create composite index on tenant_alpha orders for time-series lookup
CREATE INDEX IF NOT EXISTS idx_tenant_alpha_created ON tenant_alpha.orders (created_at DESC, customer_name);

-- Create composite index on tenant_beta orders
CREATE INDEX IF NOT EXISTS idx_tenant_beta_created ON tenant_beta.orders (created_at DESC, customer_name);

-- Analyze query execution plan to confirm index usage
EXPLAIN ANALYZE SELECT order_id, customer_name, amount FROM tenant_alpha.orders WHERE created_at >= NOW() - INTERVAL '7 days' ORDER BY created_at DESC;

COMMIT;