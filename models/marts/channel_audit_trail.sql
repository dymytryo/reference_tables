-- Audit trail: show the full history of changes to the channel reference table
--
-- Each row represents a version of a channel_id. When a CSV value changes,
-- the snapshot closes the old row (sets dbt_valid_to) and opens a new one.
-- The updated_by column tracks who made each change.

SELECT
    channel_id
    , channel_type
    , subchannel_type
    , description
    , updated_by
    , dbt_valid_from AS effective_from
    , dbt_valid_to AS effective_to
    , CASE
        WHEN dbt_valid_to IS NULL THEN 'CURRENT'
        ELSE 'SUPERSEDED'
    END AS version_status
FROM
    {{ ref('channel') }}
ORDER BY
    channel_id, dbt_valid_from
