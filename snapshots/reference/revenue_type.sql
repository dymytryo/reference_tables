{% snapshot revenue_type %}
{{
    config(
      unique_key='revenue_type_id',
      strategy='check',
      check_cols='all',
      target_schema='reference'
    )
}}

SELECT * FROM {{ ref('current_revenue_type') }}

{% endsnapshot %}
