-- Always start with a small warehouse for learning
CREATE WAREHOUSE learning_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60          -- suspend after 60s idle
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE  -- don't start until needed
  COMMENT = 'Dev warehouse for learning';

-- Verify it
SHOW WAREHOUSES LIKE 'learning_wh

-- Resource monitor: suspends warehouse when credits hit threshold
-- CRITICAL: do this before running any expensive queries on trial
CREATE RESOURCE MONITOR daily_cap
  WITH CREDIT_QUOTA = 2          -- 2 credits per day max
  FREQUENCY = DAILY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 80 PERCENT DO NOTIFY       -- email alert at 80%
    ON 100 PERCENT DO SUSPEND;   -- hard stop at 100%

-- Attach to your warehouse
ALTER WAREHOUSE learning_wh
  SET RESOURCE_MONITOR = daily_cap;

  -- Create your learning environment
CREATE DATABASE IF NOT EXISTS snowflake_learning;
USE DATABASE snowflake_learning;

-- Use schema namespacing: layer_domain pattern
CREATE SCHEMA IF NOT EXISTS raw;      -- landing zone
CREATE SCHEMA IF NOT EXISTS staging;  -- cleansed
CREATE SCHEMA IF NOT EXISTS analytics; -- final models

-- Set context (avoid writing full qualified names every time)
USE SCHEMA raw;
USE WAREHOUSE learning_wh;

-- PERMANENT table: persists forever, Time Travel enabled
CREATE TABLE employees_perm (
  id INT, name STRING, dept STRING, salary NUMBER(10,2)
);

-- TRANSIENT table: no Fail-safe, cheaper storage, good for staging
CREATE TRANSIENT TABLE employees_staging (
  id INT, name STRING, dept STRING, salary NUMBER(10,2)
);

-- TEMPORARY table: session-scoped, auto-drops on disconnect
CREATE TEMPORARY TABLE session_work AS
  SELECT * FROM employees_perm WHERE 1=0; -- empty copy of structure

-- Check storage type
SHOW TABLES IN SCHEMA raw;