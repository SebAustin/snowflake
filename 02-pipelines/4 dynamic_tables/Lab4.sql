USE DATABASE snowflake_learning;
USE SCHEMA raw;

CREATE OR REPLACE TABLE raw.orders_raw (
  order_id      INT,
  customer_id   INT,
  product_id    INT,
  quantity      INT,
  unit_price    DECIMAL(10,2),
  order_date    DATE,
  status        STRING,
  loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert sample data including duplicates (to test deduplication)
INSERT INTO raw.orders_raw (order_id, customer_id, product_id, quantity, unit_price, order_date, status) VALUES
  (1, 101, 201, 2, 29.99, '2026-01-15', 'PAID'),
  (2, 102, 202, 1, 99.99, '2026-01-16', 'PENDING'),
  (3, 101, 203, 3, 15.50, '2026-01-17', 'SHIPPED'),
  (4, 103, 201, 1, 29.99, '2026-01-18', 'PAID'),
  -- Duplicate order_id 2 (bronze DT should deduplicate this)
  (2, 102, 202, 1, 99.99, '2026-01-16', 'PAID');


  USE SCHEMA staging;

-- Bronze: raw deduplication
CREATE OR REPLACE DYNAMIC TABLE bronze_orders
  TARGET_LAG = '1 minute'
  WAREHOUSE = learning_wh
AS
SELECT
  order_id,
  customer_id,
  product_id,
  quantity,
  unit_price,
  order_date,
  status,
  loaded_at
FROM raw.orders_raw
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY order_id
  ORDER BY loaded_at DESC
) = 1;

-- Verify it populated
SELECT * FROM bronze_orders;
SELECT COUNT(*) AS row_count FROM bronze_orders; -- should be 4 (deduplicated from 5)


-- Silver: enrichment (join with dim_customers from previous lab)
CREATE OR REPLACE DYNAMIC TABLE silver_orders_enriched
  TARGET_LAG = '2 minutes'
  WAREHOUSE = learning_wh
AS
SELECT
  o.order_id,
  o.order_date,
  o.status,
  o.quantity,
  o.unit_price,
  o.quantity * o.unit_price AS line_total,
  c.name    AS customer_name,
  c.tier    AS customer_tier
FROM bronze_orders o
LEFT JOIN staging.dim_customers c
  ON o.customer_id = c.customer_id
  AND c.is_active = TRUE;

-- Gold: aggregated metrics
CREATE OR REPLACE DYNAMIC TABLE gold_customer_metrics
  TARGET_LAG = DOWNSTREAM
  WAREHOUSE = learning_wh
AS
SELECT
  customer_name,
  customer_tier,
  COUNT(DISTINCT order_id)  AS total_orders,
  SUM(line_total)           AS lifetime_value,
  AVG(line_total)           AS avg_order_value,
  MAX(order_date)           AS last_order_date
FROM silver_orders_enriched
WHERE status != 'CANCELLED'
GROUP BY customer_name, customer_tier;

-- Check all three layers
SELECT * FROM bronze_orders;
SELECT * FROM silver_orders_enriched;
SELECT * FROM gold_customer_metrics;

-- Insert a new order into the source
INSERT INTO raw.orders_raw (order_id, customer_id, product_id, quantity, unit_price, order_date, status)
VALUES (5, 102, 204, 2, 45.00, '2026-01-19', 'PAID');

-- Wait ~1 minute then check — bronze and silver should show order 5
-- gold_customer_metrics uses DOWNSTREAM so refreshes when silver does
SELECT * FROM gold_customer_metrics;