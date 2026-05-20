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
