USE DATABASE snowflake_learning;
USE SCHEMA raw;

-- Define reusable file format
CREATE FILE FORMAT csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  NULL_IF = ('NULL', 'null', '')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE;

-- Create named stage
CREATE STAGE raw_data_stage
  FILE_FORMAT = csv_format
  COMMENT = 'Landing zone for raw CSV files';

-- List stage contents
LIST @raw_data_stage;


-- Use Snowflake's public sample data (no auth needed)
-- Load NYC weather data from public S3
CREATE OR REPLACE TABLE raw.weather_observations (
  station_id    VARCHAR(20),
  date_recorded DATE,
  temp_max      FLOAT,
  temp_min      FLOAT,
  precipitation FLOAT,
  snow          FLOAT,
  snow_depth    FLOAT
);

COPY INTO raw.weather_observations
FROM 's3://snowflake-workshop-lab/weather-nyc/'
FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1)
ON_ERROR = 'CONTINUE';  -- skip bad rows, log errors

-- Check load history
SELECT * FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE TABLE_NAME = 'WEATHER_OBSERVATIONS'
ORDER BY LAST_LOAD_TIME DESC
LIMIT 10;


-- Check what schemas exist in your sample database
SHOW SCHEMAS IN DATABASE SNOWFLAKE_SAMPLE_DATA;

-- Or browse the available tables
SELECT table_schema, table_name, row_count
FROM SNOWFLAKE_SAMPLE_DATA.INFORMATION_SCHEMA.TABLES
ORDER BY table_schema, table_name;

-- TPC-H is available in ALL Snowflake trial accounts
-- Convert relational data to JSON for VARIANT practice

USE DATABASE snowflake_learning;
USE SCHEMA raw;

CREATE OR REPLACE TABLE raw.weather_json AS
SELECT OBJECT_CONSTRUCT(
  'order_id',       o.O_ORDERKEY,
  'customer_id',    o.O_CUSTKEY,
  'status',         o.O_ORDERSTATUS,
  'order_date',     o.O_ORDERDATE,
  'total_price',    o.O_TOTALPRICE,
  'priority',       o.O_ORDERPRIORITY,
  'customer',       OBJECT_CONSTRUCT(
                        'name',    c.C_NAME,
                        'nation',  c.C_NATIONKEY,
                        'segment', c.C_MKTSEGMENT
                    ),
  'items',          ARRAY_CONSTRUCT(
                        OBJECT_CONSTRUCT('part', l.L_PARTKEY,
                                         'qty',  l.L_QUANTITY,
                                         'price', l.L_EXTENDEDPRICE)
                    )
) AS raw_data
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS o
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c ON o.O_CUSTKEY = c.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM l ON o.O_ORDERKEY = l.L_ORDERKEY
LIMIT 100;


-- Dot notation and colon syntax on real VARIANT data
SELECT
  raw_data:order_id::INT                AS order_id,
  raw_data:order_date::DATE             AS order_date,
  raw_data:status::STRING               AS status,
  raw_data:total_price::FLOAT           AS total_price,
  raw_data:customer:name::STRING        AS customer_name,
  raw_data:customer:segment::STRING     AS segment,
  raw_data:items[0]:qty::FLOAT          AS first_item_qty,
  raw_data:items[0]:price::FLOAT        AS first_item_price
FROM raw.weather_json
LIMIT 10;

-- FLATTEN: explode the items array into rows (like UNNEST)
SELECT
  raw_data:order_id::INT        AS order_id,
  raw_data:order_date::DATE     AS order_date,
  item.value:part::INT          AS part_key,
  item.value:qty::FLOAT         AS quantity,
  item.value:price::FLOAT       AS price
FROM raw.weather_json,
LATERAL FLATTEN(INPUT => raw_data:items) item
LIMIT 20;


-- FLATTEN explodes arrays into rows (like UNNEST in other dialects)
-- Example: order with multiple items
CREATE TABLE raw.orders_json (data VARIANT);

INSERT INTO raw.orders_json SELECT PARSE_JSON('{
  "order_id": 1001,
  "customer": "Alice",
  "items": [
    {"product": "Widget A", "qty": 2, "price": 9.99},
    {"product": "Widget B", "qty": 1, "price": 24.99}
  ]
}');

-- FLATTEN turns the items array into individual rows
SELECT
  data:order_id::INT         AS order_id,
  data:customer::STRING      AS customer,
  item.value:product::STRING AS product,
  item.value:qty::INT        AS quantity,
  item.value:price::FLOAT    AS unit_price
FROM raw.orders_json,
LATERAL FLATTEN(INPUT => data:items) item;