{% snapshot product %}
{{
    config(
      unique_key='product_id',
      strategy='check',
      check_cols='all',
      target_schema='reference'
    )
}}

SELECT * FROM {{ ref('current_product') }}

{% endsnapshot %}
