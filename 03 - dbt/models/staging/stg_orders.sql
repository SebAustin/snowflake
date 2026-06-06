WITH source AS (
    SELECT * FROM {{ source('raw', 'orders_raw') }}
)

SELECT
    order_id,
    customer_id,
    product_id,
    quantity,
    unit_price,
    order_date,
    status,
    loaded_at
FROM source
WHERE order_id IS NOT NULL