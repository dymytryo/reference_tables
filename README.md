# dbt Reference Tables Pattern

A reusable pattern for managing business taxonomy and classification data in dbt using **CSV seeds + SCD2 snapshots**. This approach gives you version-controlled dimension tables with full audit history, no external tooling required.

## The Problem

Analytics pipelines need controlled vocabularies - standardized channel names, product categories, revenue types. These classifications:

- Change over time (new channels added, products renamed)
- Need audit trails (who changed what, when)
- Must be version-controlled (reviewable via pull request)
- Should not live in Google Sheets or someone's head

## The Solution

Three layers working together:

```
seeds/reference/current_channel.csv    -- Source of truth (edit this)
        |
        v
snapshots/reference/channel.sql        -- SCD2 history (automatic)
        |
        v
models/marts/revenue_classified.sql    -- Consumer (JOIN on current row)
```

### Layer 1: CSV Seeds (the source of truth)

```csv
channel_id,channel_type,subchannel_type,description,updated_by
1,Direct,SMB,Direct small business,jane.doe@company.com
2,Direct,Mid-Market,Direct mid-market accounts,jane.doe@company.com
3,Direct,Enterprise,Direct enterprise accounts,jane.doe@company.com
```

The CSV is the single place where taxonomy values are defined. To make a change, you edit the CSV and open a pull request. The `updated_by` column tracks who made the change.

### Layer 2: Snapshots (the history keeper)

```sql
{% snapshot channel %}
{{
    config(
      unique_key='channel_id',
      strategy='check',
      check_cols='all',
      target_schema='reference'
    )
}}

SELECT * FROM {{ ref('current_channel') }}
{% endsnapshot %}
```

The snapshot uses `strategy='check'` with `check_cols='all'`. Every time `dbt snapshot` runs:

1. It compares the current CSV values against the snapshot table
2. If any column changed for a given `channel_id`, it closes the old row (`dbt_valid_to = now()`) and inserts a new row (`dbt_valid_from = now()`, `dbt_valid_to = NULL`)
3. If nothing changed, nothing happens

This produces an SCD Type 2 table automatically.

### Layer 3: Models (the consumers)

Models join to snapshots with `WHERE dbt_valid_to IS NULL` to get the current version:

```sql
LEFT JOIN {{ ref('channel') }} ch
    ON ch.channel_id = c.channel_id
    AND ch.dbt_valid_to IS NULL
```

## How Updates Work

### Adding a new value

1. Add a row to the CSV:

```csv
7,Direct,Startup,Direct startup segment,jane.doe@company.com
```

2. Run seed + snapshot:

```bash
dbt seed --select current_channel
dbt snapshot --select channel
```

3. The snapshot table now has a new row with `dbt_valid_from = now()` and `dbt_valid_to = NULL`.

### Changing an existing value

1. Edit the CSV (e.g., rename "SMB" to "Small Business"):

```csv
1,Direct,Small Business,Direct small business accounts,john.smith@company.com
```

2. Run seed + snapshot:

```bash
dbt seed --select current_channel
dbt snapshot --select channel
```

3. The snapshot table now has:
   - Old row: `channel_id=1, subchannel_type='SMB', dbt_valid_to='2025-06-15'`
   - New row: `channel_id=1, subchannel_type='Small Business', dbt_valid_to=NULL`

4. All downstream models automatically pick up the new label on next run (they join on `dbt_valid_to IS NULL`).

### Deleting a value

Don't delete rows from the CSV. Instead, add a `is_active` column or leave the row - the snapshot preserves history either way. Downstream CASE statements simply stop producing that ID.

## Querying History

### Current state

```sql
SELECT * FROM reference.channel WHERE dbt_valid_to IS NULL
```

### Point-in-time lookup

```sql
-- What did the taxonomy look like on March 1, 2025?
SELECT *
FROM reference.channel
WHERE dbt_valid_from <= DATE '2025-03-01'
  AND (dbt_valid_to IS NULL OR dbt_valid_to > DATE '2025-03-01')
```

### Full audit trail

```sql
SELECT
    channel_id,
    subchannel_type,
    updated_by,
    dbt_valid_from AS effective_from,
    dbt_valid_to AS effective_to,
    CASE WHEN dbt_valid_to IS NULL THEN 'CURRENT' ELSE 'SUPERSEDED' END AS status
FROM reference.channel
ORDER BY channel_id, dbt_valid_from
```

Example output after renaming SMB -> Small Business:

```
channel_id | subchannel_type | updated_by             | effective_from      | effective_to        | status
1          | SMB             | jane.doe@company.com   | 2025-01-01 00:00:00 | 2025-06-15 14:30:00 | SUPERSEDED
1          | Small Business  | john.smith@company.com | 2025-06-15 14:30:00 | NULL                | CURRENT
```

### Who changed what

```sql
-- All changes by a specific person
SELECT * FROM reference.channel
WHERE updated_by = 'john.smith@company.com'
ORDER BY dbt_valid_from DESC
```

## The Classification Pattern

The full pattern for consuming reference tables in a model:

```sql
WITH classified AS (
    SELECT
        *,
        -- CASE maps raw values to reference table IDs
        CASE
            WHEN raw_channel = 'direct' AND raw_tier = 'smb' THEN 1
            WHEN raw_channel = 'direct' AND raw_tier = 'mm' THEN 2
            ...
        END AS channel_id
    FROM {{ ref('stg_raw_data') }}
)

SELECT
    c.*,
    -- Resolved labels from reference table
    ch.channel_type,
    ch.subchannel_type
FROM classified c
LEFT JOIN {{ ref('channel') }} ch
    ON ch.channel_id = c.channel_id
    AND ch.dbt_valid_to IS NULL  -- current version only
```

**Why CASE + JOIN instead of just CASE with hardcoded strings?**

- The CASE produces an integer ID. The reference table resolves it to a label.
- If a label changes (SMB -> Small Business), you update the CSV. The CASE logic stays the same.
- The snapshot preserves history. Hardcoded strings in CASE statements don't.
- Multiple models can join to the same reference table. One update propagates everywhere.
- The `updated_by` column creates accountability. You can trace every taxonomy change to a person.

## Testing

Add tests to catch mapping gaps:

```yaml
tests:
  # Catch CASE fallthrough (raw value not mapped to any ID)
  - dbt_utils.expression_is_true:
      expression: "channel_type is not null"
      config:
        severity: warn

  # Catch reference table drift (ID exists but label is unexpected)
  - dbt_utils.expression_is_true:
      expression: "revenue_type IN ('Transaction', 'Subscription', 'Float')"
      config:
        severity: error
```

## Project Structure

```
seeds/reference/
  current_channel.csv           -- Edit this to change channel taxonomy
  current_product.csv           -- Edit this to change product taxonomy
  current_revenue_type.csv      -- Edit this to change revenue types
  seeds.yml                     -- Column types and descriptions

snapshots/reference/
  channel.sql                   -- SCD2 snapshot of current_channel
  product.sql                   -- SCD2 snapshot of current_product
  revenue_type.sql              -- SCD2 snapshot of current_revenue_type

models/
  staging/
    stg_raw_revenue.sql         -- Simulated raw data
  marts/
    revenue_classified.sql      -- Silver layer: CASE + reference joins
    channel_as_of_date.sql      -- Point-in-time taxonomy lookup
    channel_audit_trail.sql     -- Full change history
```

## When to Use This Pattern

**Good fit:**
- Business taxonomies that change quarterly or less (channels, products, segments)
- Classification rules owned by a specific team (Finance, Analytics)
- Audit requirements (SOX, regulatory) that need change tracking
- Small reference data (< 10K rows) that fits comfortably in a CSV

**Not a good fit:**
- High-frequency updates (multiple times per day)
- Large reference data (> 10K rows) - use a source table instead
- Reference data that comes from an API or external system - use a source + staging model

## Commands

```bash
# Initial setup
dbt seed                        # Load all CSVs
dbt snapshot                    # Create initial snapshot rows

# After editing a CSV
dbt seed --select current_channel
dbt snapshot --select channel
dbt run --select revenue_classified

# Full refresh
dbt seed
dbt snapshot
dbt run
```
