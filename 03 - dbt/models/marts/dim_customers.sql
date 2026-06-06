SELECT
    customer_id,
    customer_name,
    customer_email,
    customer_tier,
    updated_at
FROM {{ ref('stg_customers') }}


