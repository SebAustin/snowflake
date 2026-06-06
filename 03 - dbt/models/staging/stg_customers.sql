WITH source AS (
    SELECT * FROM {{ source('raw', 'customers') }}
)

SELECT
    customer_id,
    LOWER(TRIM(name))   AS customer_name,
    LOWER(TRIM(email))  AS customer_email,
    UPPER(tier)         AS customer_tier,
    updated_at
FROM source
WHERE customer_id IS NOT NULL
