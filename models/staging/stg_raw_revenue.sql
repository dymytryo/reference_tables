-- Simulated raw revenue data (in production this would be a source table)
-- This model pretends to be upstream data with raw/unstandardized values

SELECT
    1001 AS entity_id
    , DATE '2025-01-15' AS transaction_date
    , 'SUBSCRIPTION' AS raw_revenue_type
    , 'direct' AS raw_channel
    , 'smb' AS raw_subchannel
    , 'saas' AS raw_product
    , 99.99 AS revenue_amount

UNION ALL SELECT 1002, DATE '2025-01-20', 'TXN', 'partner', 'reseller', 'transaction_fee', 2.50
UNION ALL SELECT 1003, DATE '2025-02-01', 'SUBSCRIPTION', 'direct', 'enterprise', 'api_access', 499.00
UNION ALL SELECT 1004, DATE '2025-02-10', 'FLOAT', 'marketplace', NULL, NULL, 12.34
UNION ALL SELECT 1005, DATE '2025-03-01', 'TXN', 'direct', 'mid-market', 'data_export', 15.00
