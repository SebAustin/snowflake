USE DATABASE snowflake_learning;
USE SCHEMA raw;

-- Source table: simulates an operational system
CREATE OR REPLACE TABLE customers (
  customer_id   INT PRIMARY KEY,
  name          VARCHAR(100),
  email         VARCHAR(200),
  tier          VARCHAR(20) DEFAULT 'standard',
  updated_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Create stream to track all changes
CREATE OR REPLACE STREAM customers_stream
  ON TABLE customers
  COMMENT = 'CDC stream for customers table';

-- Check stream (empty initially)
SELECT SYSTEM$STREAM_HAS_DATA('customers_stream');

USE SCHEMA staging;

-- Target: clean dimension table  
CREATE OR REPLACE TABLE dim_customers (
  customer_id   INT PRIMARY KEY,
  name          VARCHAR(100),
  email         VARCHAR(200),
  tier          VARCHAR(20),
  is_active     BOOLEAN DEFAULT TRUE,
  loaded_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE PROCEDURE staging.merge_customers()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
  -- Only process if there's data in the stream
  IF (NOT SYSTEM$STREAM_HAS_DATA('raw.customers_stream')) THEN
    RETURN 'No new data in stream';
  END IF;

  MERGE INTO staging.dim_customers AS tgt
  USING (
    -- Deduplicate stream: keep last action per customer
    SELECT customer_id, name, email, tier,
           METADATA$ACTION, METADATA$ISUPDATE
    FROM raw.customers_stream
    QUALIFY ROW_NUMBER() OVER (
      PARTITION BY customer_id
      ORDER BY METADATA$ACTION DESC
    ) = 1
  ) AS src
  ON tgt.customer_id = src.customer_id

  WHEN MATCHED AND src.METADATA$ACTION = 'DELETE'
    THEN UPDATE SET tgt.is_active = FALSE

  WHEN MATCHED AND src.METADATA$ACTION = 'INSERT'
    THEN UPDATE SET
      tgt.name      = src.name,
      tgt.email     = src.email,
      tgt.tier      = src.tier,
      tgt.loaded_at = CURRENT_TIMESTAMP()

  WHEN NOT MATCHED AND src.METADATA$ACTION = 'INSERT'
    THEN INSERT (customer_id, name, email, tier)
    VALUES (src.customer_id, src.name, src.email, src.tier);

  RETURN 'Merge complete: ' || SQLROWCOUNT || ' rows affected';
END;
$$;

CREATE OR REPLACE TABLE customers (
  customer_id   INT PRIMARY KEY,
  name          VARCHAR(100),
  email         VARCHAR(200),
  tier          VARCHAR(20) DEFAULT 'standard',
  updated_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()  -- ← 5th column
);

-- Option 1: name the columns explicitly (best practice)
INSERT INTO raw.customers (customer_id, name, email, tier) VALUES
  (1, 'Alice Chen', 'alice@example.com', 'gold'),
  (2, 'Bob Smith', 'bob@example.com', 'standard'),
  (3, 'Carol Wu', 'carol@example.com', 'platinum');

-- Option 2: include all 5 values
INSERT INTO raw.customers VALUES
  (1, 'Alice Chen', 'alice@example.com', 'gold',     CURRENT_TIMESTAMP()),
  (2, 'Bob Smith',  'bob@example.com',   'standard', CURRENT_TIMESTAMP()),
  (3, 'Carol Wu',   'carol@example.com', 'platinum', CURRENT_TIMESTAMP());

-- UPDATE triggers CDC
UPDATE raw.customers SET tier = 'platinum' WHERE customer_id = 2;

-- DELETE triggers CDC
DELETE FROM raw.customers WHERE customer_id = 3;

-- Check stream
SELECT *, METADATA$ACTION, METADATA$ISUPDATE
FROM raw.customers_stream;