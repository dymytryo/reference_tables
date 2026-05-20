-- Silver layer: classify raw data using CASE logic, resolve via reference tables
--
-- Pattern:
--   1. CASE statements map raw values to reference table IDs
--   2. LEFT JOIN to snapshot tables (WHERE dbt_valid_to IS NULL = current row)
--   3. Output uses the resolved labels, not the raw values

WITH classified AS (
    SELECT
        entity_id
        , transaction_date
        , revenue_amount
        , raw_revenue_type
        , raw_channel
        , raw_subchannel
        , raw_product

        -- Map raw revenue type to standardized ID
        , CASE
            WHEN raw_revenue_type IN ('TXN', 'TRANSACTION') THEN 1
            WHEN raw_revenue_type = 'SUBSCRIPTION' THEN 2
            WHEN raw_revenue_type = 'FLOAT' THEN 3
        END AS revenue_type_id

        -- Map raw channel/subchannel to standardized ID
        , CASE
            WHEN raw_channel = 'direct' AND raw_subchannel = 'smb' THEN 1
            WHEN raw_channel = 'direct' AND raw_subchannel = 'mid-market' THEN 2
            WHEN raw_channel = 'direct' AND raw_subchannel = 'enterprise' THEN 3
            WHEN raw_channel = 'partner' AND raw_subchannel = 'reseller' THEN 4
            WHEN raw_channel = 'partner' AND raw_subchannel = 'referral' THEN 5
            WHEN raw_channel = 'marketplace' THEN 6
        END AS channel_id

        -- Map raw product to standardized ID
        , CASE
            WHEN raw_product = 'saas' THEN 1
            WHEN raw_product = 'api_access' THEN 2
            WHEN raw_product = 'transaction_fee' THEN 3
            WHEN raw_product = 'premium_support' THEN 4
            WHEN raw_product = 'data_export' THEN 5
        END AS product_id
    FROM
        {{ ref('stg_raw_revenue') }}
)

SELECT
    c.entity_id
    , c.transaction_date
    , c.revenue_amount

    -- Resolved dimension labels (these are what downstream consumers use)
    , rt.revenue_type
    , ch.channel_type
    , ch.subchannel_type
    , p.product_type
    , p.product_category
FROM
    classified c
LEFT JOIN {{ ref('revenue_type') }} rt
    ON rt.revenue_type_id = c.revenue_type_id
    AND rt.dbt_valid_to IS NULL
LEFT JOIN {{ ref('channel') }} ch
    ON ch.channel_id = c.channel_id
    AND ch.dbt_valid_to IS NULL
LEFT JOIN {{ ref('product') }} p
    ON p.product_id = c.product_id
    AND p.dbt_valid_to IS NULL
