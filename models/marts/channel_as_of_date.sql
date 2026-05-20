-- Point-in-time query: what was the channel taxonomy on a specific date?
--
-- Snapshots store every version of each row with dbt_valid_from / dbt_valid_to.
-- To see what the taxonomy looked like at any point in time, filter on those columns.

SELECT
    channel_id
    , channel_type
    , subchannel_type
    , description
    , updated_by
    , dbt_valid_from
    , dbt_valid_to
FROM
    {{ ref('channel') }}
WHERE
    -- Replace with your target date
    dbt_valid_from <= DATE '2025-06-01'
    AND (dbt_valid_to IS NULL OR dbt_valid_to > DATE '2025-06-01')
