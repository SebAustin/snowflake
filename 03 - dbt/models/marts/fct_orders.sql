{{
  config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

WITH orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
    {% if is_incremental() %}
        WHERE loaded_at > (SELECT MAX(loaded_at) FROM {{ this }})
    {% endif %}
),

enriched AS (
    SELECT
        o.order_id,
        o.order_date,
        o.customer_id,
        c.customer_name,
        c.customer_tier,
        o.quantity,
        o.unit_price,
        o.quantity * o.unit_price  AS line_total,
        o.status,
        o.loaded_at
    FROM orders o
    LEFT JOIN {{ ref('stg_customers') }} c
        ON o.customer_id = c.customer_id
)

SELECT * FROM enriched