-- ============================================================
-- MODULE 6: GOVERNANCE & RBAC
-- Lab 9 Step 1: Create the access role hierarchy
-- ============================================================

USE DATABASE snowflake_learning;
USE ROLE ACCOUNTADMIN;

-- ── ACCESS ROLES (object-level) ──────────────────────────────
-- These are granted to schemas/tables, not directly to users

-- Read-only access to analytics schema
CREATE ROLE IF NOT EXISTS db_analytics_read_r;
GRANT USAGE  ON DATABASE snowflake_learning           TO ROLE db_analytics_read_r;
GRANT USAGE  ON SCHEMA   snowflake_learning.analytics TO ROLE db_analytics_read_r;
GRANT SELECT ON ALL TABLES IN SCHEMA snowflake_learning.analytics
                                                      TO ROLE db_analytics_read_r;
GRANT SELECT ON FUTURE TABLES IN SCHEMA snowflake_learning.analytics
                                                      TO ROLE db_analytics_read_r;

-- Write access to staging schema


CREATE ROLE IF NOT EXISTS db_staging_write_r;
GRANT USAGE ON DATABASE snowflake_learning            TO ROLE db_staging_write_r;
GRANT USAGE ON SCHEMA   snowflake_learning.staging    TO ROLE db_staging_write_r;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA snowflake_learning.staging
                                                      TO ROLE db_staging_write_r;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES
  IN SCHEMA snowflake_learning.staging                TO ROLE db_staging_write_r;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES
  IN SCHEMA snowflake_learning.staging                TO ROLE db_staging_write_r;

-- Warehouse usage
CREATE ROLE IF NOT EXISTS wh_xs_usage_r;
GRANT USAGE ON WAREHOUSE learning_wh TO ROLE wh_xs_usage_r;

-- Verify
SHOW ROLES LIKE '%_r';


-- ============================================================
-- STEP 2: Functional roles and user grants
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ── FUNCTIONAL ROLES (persona-based) ─────────────────────────
-- These are what users actually use day-to-day

-- Analyst: read analytics + use warehouse
CREATE ROLE IF NOT EXISTS analyst_fr;
GRANT ROLE db_analytics_read_r TO ROLE analyst_fr;
GRANT ROLE wh_xs_usage_r       TO ROLE analyst_fr;
COMMENT ON ROLE analyst_fr IS 'Business analysts — read analytics schema only';

-- Data Engineer: write staging + read analytics + use warehouse
CREATE ROLE IF NOT EXISTS data_engineer_fr;
GRANT ROLE db_staging_write_r  TO ROLE data_engineer_fr;
GRANT ROLE db_analytics_read_r TO ROLE data_engineer_fr;
GRANT ROLE wh_xs_usage_r       TO ROLE data_engineer_fr;
COMMENT ON ROLE data_engineer_fr IS 'Data engineers — build and maintain pipelines';

-- ── GRANT FUNCTIONAL ROLES UP TO SYSADMIN ────────────────────
-- Best practice: all custom roles should roll up to SYSADMIN
GRANT ROLE analyst_fr        TO ROLE SYSADMIN;
GRANT ROLE data_engineer_fr  TO ROLE SYSADMIN;
GRANT ROLE db_analytics_read_r TO ROLE SYSADMIN;
GRANT ROLE db_staging_write_r  TO ROLE SYSADMIN;
GRANT ROLE wh_xs_usage_r       TO ROLE SYSADMIN;

-- ── CREATE A TEST USER ────────────────────────────────────────
CREATE USER IF NOT EXISTS alice_analyst
  LOGIN_NAME    = 'alice_analyst'
  DISPLAY_NAME  = 'Alice (Analyst)'
  DEFAULT_ROLE  = analyst_fr
  DEFAULT_WAREHOUSE = learning_wh
  MUST_CHANGE_PASSWORD = FALSE
  PASSWORD      = 'TempPass123!';

-- Grant the analyst role to Alice
GRANT ROLE analyst_fr TO USER alice_analyst;

-- ── VERIFY ────────────────────────────────────────────────────
-- What roles does Alice have?
SHOW GRANTS TO USER alice_analyst;

-- What does analyst_fr inherit?
SHOW GRANTS TO ROLE analyst_fr;

-- What does data_engineer_fr inherit?
SHOW GRANTS TO ROLE data_engineer_fr;


-- ============================================================
-- STEP 3: Dynamic Data Masking on PII columns
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE snowflake_learning;
USE SCHEMA analytics;

-- ── MASKING POLICY 1: Email ───────────────────────────────────
-- Show full email to data engineers, mask local part for analysts
CREATE OR REPLACE MASKING POLICY email_mask AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('DATA_ENGINEER_FR', 'SYSADMIN', 'ACCOUNTADMIN')
      THEN val                                    -- full email
    WHEN CURRENT_ROLE() = 'ANALYST_FR'
      THEN REGEXP_REPLACE(val, '.*@', '****@')   -- ****@domain.com
    ELSE '***REDACTED***'                         -- everyone else: nothing
  END;

-- ── MASKING POLICY 2: Customer tier (partial mask) ───────────
CREATE OR REPLACE MASKING POLICY tier_mask AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN CURRENT_ROLE() IN ('DATA_ENGINEER_FR', 'SYSADMIN', 'ACCOUNTADMIN')
      THEN val
    WHEN CURRENT_ROLE() = 'ANALYST_FR'
      THEN '***'
    ELSE NULL
  END;

-- ── APPLY POLICIES TO COLUMNS ────────────────────────────────
-- First add email column to customers table if not there
ALTER TABLE snowflake_learning.raw.customers
  ADD COLUMN IF NOT EXISTS email_address VARCHAR(200);

UPDATE snowflake_learning.raw.customers
SET email_address = LOWER(name) || '@example.com'
WHERE email_address IS NULL;

-- Apply email mask
ALTER TABLE snowflake_learning.raw.customers
  MODIFY COLUMN email_address
    SET MASKING POLICY analytics.email_mask;

-- Apply tier mask
ALTER TABLE snowflake_learning.raw.customers
  MODIFY COLUMN tier
    SET MASKING POLICY analytics.tier_mask;

-- ── TEST THE MASKS ────────────────────────────────────────────
-- As ACCOUNTADMIN: sees everything
USE ROLE ACCOUNTADMIN;
SELECT customer_id, name, email_address, tier
FROM snowflake_learning.raw.customers;

-- As ANALYST_FR: email masked, tier hidden
USE ROLE ANALYST_FR;
SELECT customer_id, name, email_address, tier
FROM snowflake_learning.raw.customers;

-- Switch back
USE ROLE ACCOUNTADMIN;

-- Query 1: As ACCOUNTADMIN (sees everything)
USE ROLE ACCOUNTADMIN;
SELECT customer_id, name, email_address, tier
FROM snowflake_learning.raw.customers;


-- Query 2: As ANALYST_FR (email masked, tier hidden)
USE ROLE ANALYST_FR;
SELECT customer_id, name, email_address, tier
FROM snowflake_learning.raw.customers;


-- ============================================================
-- STEP 4: Row Access Policies
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE snowflake_learning;
USE SCHEMA analytics;

-- ── CREATE A REGION-BASED ACCESS MAPPING TABLE ───────────────
CREATE OR REPLACE TABLE analytics.region_access_map (
  role_name   VARCHAR(100),
  region      VARCHAR(50)
);

INSERT INTO analytics.region_access_map VALUES
  ('ANALYST_FR',       'US'),
  ('DATA_ENGINEER_FR', NULL);   -- NULL = access to all regions

-- ── ADD REGION COLUMN TO ORDERS TABLE ────────────────────────
ALTER TABLE snowflake_learning.raw.orders_raw
  ADD COLUMN IF NOT EXISTS region VARCHAR(50);

UPDATE snowflake_learning.raw.orders_raw
SET region = CASE
  WHEN customer_id = 101 THEN 'US'
  WHEN customer_id = 102 THEN 'EU'
  WHEN customer_id = 103 THEN 'US'
  ELSE 'US'
END;

-- ── CREATE ROW ACCESS POLICY ──────────────────────────────────
-- Data engineers see all rows
-- Analysts only see rows where region matches their mapping
CREATE OR REPLACE ROW ACCESS POLICY analytics.regional_access
AS (region_col VARCHAR)
RETURNS BOOLEAN ->
  CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN')
  OR EXISTS (
    SELECT 1
    FROM analytics.region_access_map
    WHERE role_name = CURRENT_ROLE()
      AND (region = region_col OR region IS NULL)
  );

-- ── APPLY TO ORDERS TABLE ─────────────────────────────────────
ALTER TABLE snowflake_learning.raw.orders_raw
  ADD ROW ACCESS POLICY analytics.regional_access ON (region);

-- ── TEST ROW ACCESS ───────────────────────────────────────────
-- As ACCOUNTADMIN: sees all rows
USE ROLE ACCOUNTADMIN;
SELECT order_id, customer_id, region, status
FROM snowflake_learning.raw.orders_raw
ORDER BY order_id;

-- As ANALYST_FR: only sees US rows (EU rows filtered out)
USE ROLE ANALYST_FR;
SELECT order_id, customer_id, region, status
FROM snowflake_learning.raw.orders_raw
ORDER BY order_id;

-- Switch back
USE ROLE ACCOUNTADMIN;


-- ============================================================
-- STEP 5: Tag-Based Governance + Audit Queries (FIXED)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE snowflake_learning;

-- ── CREATE GOVERNANCE SCHEMA ─────────────────────────────────
CREATE SCHEMA IF NOT EXISTS snowflake_learning.governance;

-- ── CREATE PII CLASSIFICATION TAG ────────────────────────────
CREATE TAG IF NOT EXISTS snowflake_learning.governance.pii_tag
  ALLOWED_VALUES 'EMAIL', 'SSN', 'PHONE', 'NAME', 'ADDRESS'
  COMMENT = 'Tag to classify PII columns for governance';

-- ── APPLY TAGS TO PII COLUMNS ────────────────────────────────
ALTER TABLE snowflake_learning.raw.customers
  MODIFY COLUMN email_address
    SET TAG snowflake_learning.governance.pii_tag = 'EMAIL';

ALTER TABLE snowflake_learning.raw.customers
  MODIFY COLUMN name
    SET TAG snowflake_learning.governance.pii_tag = 'NAME';

-- ── FIND ALL TAGGED PII COLUMNS ON SPECIFIC TABLE ────────────
SELECT
  object_database,
  object_schema,
  object_name,
  column_name,
  tag_value                     AS pii_type
FROM TABLE(
  snowflake_learning.information_schema.tag_references_all_columns(
    'snowflake_learning.raw.customers',
    'table'
  )
)
WHERE tag_name = 'PII_TAG';

-- ── ACCOUNT USAGE: full PII audit across ALL tables ──────────
SELECT
  object_database,
  object_schema,
  object_name,
  column_name,
  tag_value                     AS pii_classification
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_name = 'PII_TAG'
ORDER BY object_name, column_name;

-- ── AUDIT: who accessed PII columns recently (FIXED) ─────────
SELECT
  start_time,                   -- fixed: was QUERY_START_TIME
  user_name,
  role_name,
  query_text,
  execution_status
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_text ILIKE '%email_address%'
  AND start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- ── COST MONITORING: credit usage by warehouse ───────────────
SELECT
  warehouse_name,
  SUM(credits_used)             AS total_credits,
  SUM(credits_used_compute)     AS compute_credits,
  COUNT(*)                      AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY total_credits DESC;

-- ── RESOURCE MONITOR CHECK ────────────────────────────────────
SHOW RESOURCE MONITORS;