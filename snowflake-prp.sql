
--LEVEL 1

-- Warehouse: the compute engine that actually runs queries
CREATE WAREHOUSE COMPUTE_WH WITH WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 AUTO_RESUME=TRUE;

-- Custom role and grants (role hierarchy: ACCOUNTADMIN -> SYSADMIN -> DEVELOPER_ROLE)
CREATE ROLE DEVELOPER_ROLE;
GRANT ROLE DEVELOPER_ROLE TO USER AARTHIUS;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DEVELOPER_ROLE;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DEVELOPER_ROLE;
GRANT ROLE SYSADMIN TO ROLE DEVELOPER_ROLE;

-- Landing database/schema for practice ETL, plus an internal stage
-- (an internal stage is storage space living inside Snowflake itself)
CREATE DATABASE LANDING_DB;
CREATE SCHEMA LANDING_DB.STAGING_SCHEMA;
USE DATABASE LANDING_DB;
USE SCHEMA STAGING_SCHEMA;
CREATE OR REPLACE STAGE MY_INTERNAL_STAGE;

-- File formats: tell Snowflake how to interpret a raw file (delimiter, header row, etc.)
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null')
    EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE FILE FORMAT JSON_FORMAT
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE;

CREATE OR REPLACE FILE FORMAT mycsvformat
    TYPE = 'CSV'
    FIELD_DELIMITER = '|'
    SKIP_HEADER = 1;

CREATE OR REPLACE FILE FORMAT myjsonformat
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE;

-- Stages linked to specific file formats
CREATE OR REPLACE STAGE my_csv_stage FILE_FORMAT = mycsvformat;
CREATE OR REPLACE STAGE my_json_stage FILE_FORMAT = myjsonformat;

-- Target tables
-- mycsvtable: structured contact data
-- myjsontable: VARIANT column holds semi-structured JSON of any shape
CREATE OR REPLACE TABLE mycsvtable (
    id              INTEGER,
    last_name       STRING,
    first_name      STRING,
    company         STRING,
    email           STRING,
    workphone       STRING,
    cellphone       STRING,
    streetaddress   STRING,
    city            STRING,
    postalcode      STRING
);

CREATE OR REPLACE TABLE myjsontable (json_data VARIANT);

-- Load data from stage into tables
-- contacts1,2,4,5.csv load successfully; contacts3.csv is intentionally broken
-- (a stray '|' character) and gets skipped via ON_ERROR
COPY INTO mycsvtable
    FROM @my_csv_stage
    FILE_FORMAT = (FORMAT_NAME = mycsvformat)
    PATTERN = '.*contacts[1-5].csv.*'
    ON_ERROR = 'skip_file';

COPY INTO myjsontable
    FROM @my_json_stage/contacts.json
    FILE_FORMAT = (FORMAT_NAME = myjsonformat)
    ON_ERROR = 'skip_file';

-- VALIDATE inspects a past COPY INTO job (by Query/Job ID) and shows exactly
-- which rows failed and why
CREATE OR REPLACE TABLE save_copy_errors AS
SELECT * FROM TABLE(VALIDATE(mycsvtable, JOB_ID => '01c62f72-0002-675a-000e-735200031312'));

SELECT * FROM save_copy_errors;


--LEVEL 2

-- Explore Snowflake's built-in sample dataset (TPC-H) 
SHOW SCHEMAS IN DATABASE SNOWFLAKE_SAMPLE_DATA;

USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1;
SHOW TABLES;

SELECT * FROM CUSTOMER LIMIT 5;
SELECT * FROM ORDERS LIMIT 5;
SELECT * FROM LINEITEM LIMIT 5;

-- Custom retail schema: 4 tables
-- customers, products = dimension tables (descriptive/reference data)
-- orders, order_items = fact tables, split into header (orders) and detail (order_items)
CREATE DATABASE IF NOT EXISTS RETAIL_DB;
CREATE SCHEMA IF NOT EXISTS RETAIL_DB.SALES;
USE SCHEMA RETAIL_DB.SALES;

CREATE OR REPLACE TABLE customers (
    customer_id     INT AUTOINCREMENT PRIMARY KEY,
    first_name      VARCHAR(50),
    last_name       VARCHAR(50),
    email           VARCHAR(100),
    signup_date     DATE
);

CREATE OR REPLACE TABLE products (
    product_id      INT AUTOINCREMENT PRIMARY KEY,
    product_name    VARCHAR(100),
    category        VARCHAR(50),
    unit_price      NUMBER(10,2)
);

CREATE OR REPLACE TABLE orders (
    order_id        INT AUTOINCREMENT PRIMARY KEY,
    customer_id     INT NOT NULL,
    order_date      DATE NOT NULL,
    status          VARCHAR(20) DEFAULT 'PLACED',
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- line_total is a computed column: Snowflake calculates it automatically
-- from quantity * unit_price, cast to match the declared NUMBER(10,2) precision
CREATE OR REPLACE TABLE order_items (
    order_item_id   INT AUTOINCREMENT PRIMARY KEY,
    order_id        INT NOT NULL,
    product_id      INT NOT NULL,
    quantity        INT NOT NULL,
    unit_price      NUMBER(10,2) NOT NULL,
    line_total      NUMBER(10,2) AS (CAST(quantity * unit_price AS NUMBER(10,2))),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Sample data
INSERT INTO customers (first_name, last_name, email, signup_date) VALUES
    ('Aarthi', 'U', 'aarthi@example.com', '2024-01-15'),
    ('Ravi', 'Kumar', 'ravi.kumar@example.com', '2024-02-20'),
    ('Priya', 'Sharma', 'priya.sharma@example.com', '2024-03-05');

INSERT INTO products (product_name, category, unit_price) VALUES
    ('Wireless Mouse', 'Electronics', 599.00),
    ('Mechanical Keyboard', 'Electronics', 2499.00),
    ('Notebook', 'Stationery', 49.00),
    ('Water Bottle', 'Lifestyle', 299.00),
    ('Backpack', 'Lifestyle', 1299.00);

INSERT INTO orders (customer_id, order_date, status) VALUES
    (1, '2024-06-01', 'DELIVERED'),
    (1, '2024-06-10', 'SHIPPED'),
    (2, '2024-06-03', 'DELIVERED'),
    (3, '2024-06-05', 'PLACED');

INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 2, 599.00),
    (1, 3, 1, 49.00),
    (2, 2, 1, 2499.00),
    (3, 4, 3, 299.00),
    (3, 5, 1, 1299.00),
    (4, 1, 1, 599.00),
    (4, 3, 5, 49.00);


SELECT
    o.order_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    o.order_date,
    o.status,
    p.product_name,
    oi.quantity,
    oi.unit_price,
    oi.line_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
ORDER BY o.order_id;

-- Aggregation: total revenue per order
SELECT
    o.order_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    o.order_date,
    SUM(oi.line_total) AS order_total
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY o.order_id, customer_name, o.order_date
ORDER BY o.order_id;

-- 3-way join against TPC-H: revenue by nation
USE SCHEMA SNOWFLAKE_SAMPLE_DATA.TPCH_SF1;

SELECT
    n.N_NAME AS nation,
    COUNT(DISTINCT o.O_ORDERKEY) AS num_orders,
    SUM(o.O_TOTALPRICE) AS total_revenue
FROM CUSTOMER c
JOIN ORDERS o ON c.C_CUSTKEY = o.O_CUSTKEY
JOIN NATION n ON c.C_NATIONKEY = n.N_NATIONKEY
GROUP BY n.N_NAME
ORDER BY total_revenue DESC;



-- Time Travel: query a table as it existed at a past point in time
USE SCHEMA RETAIL_DB.SALES;

SELECT * FROM orders;

UPDATE orders SET status = 'CANCELLED' WHERE order_id = 4;

SELECT * FROM orders WHERE order_id = 4;

-- Query the table as it was 60 seconds ago (before the UPDATE)
SELECT * FROM orders
AT (OFFSET => -60)
WHERE order_id = 4;

-- Zero-Copy Cloning: instant copy, no duplicated storage (copy-on-write)
CREATE TABLE orders_clone CLONE orders;

SELECT * FROM orders_clone;

-- Prove independence: update only the clone
UPDATE orders_clone SET status = 'REFUNDED' WHERE order_id = 4;

SELECT order_id, status FROM orders WHERE order_id = 4;         -- unchanged
SELECT order_id, status FROM orders_clone WHERE order_id = 4;   -- diverged


--LEVEL 3

USE SCHEMA RETAIL_DB.SALES;

-- CONFIG_MASTER: transformation rules stored as DATA (rows), not hardcoded
CREATE OR REPLACE TABLE CONFIG_MASTER (
    config_id       INT AUTOINCREMENT PRIMARY KEY,
    source_table    VARCHAR(50),
    source_column   VARCHAR(50),
    target_column   VARCHAR(50),
    transformation  VARCHAR(50),
    is_active       BOOLEAN DEFAULT TRUE
);

INSERT INTO CONFIG_MASTER (source_table, source_column, target_column, transformation) VALUES
    ('customers', 'first_name', 'FIRST_NAME_CLEAN', 'UPPER'),
    ('customers', 'last_name', 'LAST_NAME_CLEAN', 'UPPER'),
    ('customers', 'email', 'EMAIL_CLEAN', 'TRIM'),
    ('customers', 'signup_date', 'SIGNUP_DATE', 'NONE');

-- Added later to prove the pattern is genuinely dynamic:
-- adding this one row alone made a new column appear in the Python output,
-- with zero code changes.
INSERT INTO CONFIG_MASTER (source_table, source_column, target_column, transformation) VALUES
    ('customers', 'email', 'EMAIL_UPPER', 'UPPER');

-- Two deliberately broken rows, used to test validation logic
INSERT INTO customers (first_name, last_name, email, signup_date) VALUES
    ('Test', 'Bad', NULL, '2024-07-01'),
    ('Test2', 'Bad2', 'not-an-email', '2024-07-02');


USE ROLE ACCOUNTADMIN;
GRANT CREATE TABLE ON SCHEMA RETAIL_DB.SALES TO ROLE SYSADMIN;


GRANT ALL ON SCHEMA RETAIL_DB.SALES TO ROLE SYSADMIN;
GRANT ALL ON DATABASE RETAIL_DB TO ROLE SYSADMIN;


SELECT * FROM customers_rejects;

-- Audit log: one row per pipeline run, tracking counts and status
CREATE OR REPLACE TABLE PIPELINE_AUDIT_LOG (
    run_id              INT AUTOINCREMENT PRIMARY KEY,
    run_timestamp       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_table        VARCHAR(50),
    records_read        INT,
    records_passed      INT,
    records_rejected    INT,
    status              VARCHAR(20)
);

SELECT * FROM PIPELINE_AUDIT_LOG;


CREATE OR REPLACE TABLE VALIDATION_RULES (
    rule_id         INT AUTOINCREMENT PRIMARY KEY,
    source_table    VARCHAR(50),
    column_name     VARCHAR(50),
    rule_type       VARCHAR(50),    -- e.g. 'NOT_NULL', 'FORMAT_EMAIL'
    fail_code       VARCHAR(50),
    is_active       BOOLEAN DEFAULT TRUE
);

INSERT INTO VALIDATION_RULES (source_table, column_name, rule_type, fail_code) VALUES
    ('customers', 'email', 'NOT_NULL', 'FAIL_NULL_EMAIL'),
    ('customers', 'email', 'FORMAT_EMAIL', 'FAIL_BAD_EMAIL_FORMAT');


--LEVEL 3 - EXTERNAL SYSTEMS - AZURE BLOB STORAGE

USE SCHEMA RETAIL_DB.SALES;


CREATE OR REPLACE STAGE azure_external_stage
    URL = 'azure://aarthipracticestorage.blob.core.windows.net/practice-container'
    CREDENTIALS = (AZURE_SAS_TOKEN = '<SAS_TOKEN_GENERATED_IN_AZURE_PORTAL>');

-- Confirm Snowflake can see the file sitting in the Blob container
LIST @azure_external_stage;

CREATE OR REPLACE TABLE azure_loaded_contacts (
    id              VARCHAR,
    lastname        VARCHAR,
    firstname       VARCHAR,
    company         VARCHAR,
    email           VARCHAR,
    workphone       VARCHAR,
    cellphone       VARCHAR,
    streetaddress   VARCHAR,
    city            VARCHAR,
    postalcode      VARCHAR
);

CREATE OR REPLACE FILE FORMAT pipe_format
    TYPE = 'CSV'
    FIELD_DELIMITER = '|'
    SKIP_HEADER = 1;

-- Actually pull the file in from Blob storage into the Snowflake table
COPY INTO azure_loaded_contacts
    FROM @azure_external_stage
    FILE_FORMAT = (FORMAT_NAME = pipe_format)
    PATTERN = '.*\.csv';

SELECT * FROM azure_loaded_contacts;


--LEVEL 3 - EXTERNAL SYSTEMS - AWS S3

-- Step 1: create a placeholder Storage Integration in Snowflake first
CREATE STORAGE INTEGRATION s3_practice_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/placeholder_role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://aarthi-practice-bucket-2026/');

-- Step 2: retrieve Snowflake's own AWS identity (STORAGE_AWS_IAM_USER_ARN)
-- and the security check value (STORAGE_AWS_EXTERNAL_ID) from the output below.
-- These were used to create a trusting IAM Role inside the AWS Console.
DESCRIBE INTEGRATION s3_practice_integration;

-- Step 3: once the real IAM Role exists in AWS, point the integration at it
ALTER STORAGE INTEGRATION s3_practice_integration
    SET STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::004720838786:role/snowflake_s3_access_role';

USE SCHEMA RETAIL_DB.SALES;


CREATE OR REPLACE STAGE s3_external_stage
    URL = 's3://aarthi-practice-bucket-2026/'
    STORAGE_INTEGRATION = s3_practice_integration;

LIST @s3_external_stage;

CREATE OR REPLACE TABLE s3_loaded_contacts (
    id              VARCHAR,
    lastname        VARCHAR,
    firstname       VARCHAR,
    company         VARCHAR,
    email           VARCHAR,
    workphone       VARCHAR,
    cellphone       VARCHAR,
    streetaddress   VARCHAR,
    city            VARCHAR,
    postalcode      VARCHAR
);

COPY INTO s3_loaded_contacts
    FROM @s3_external_stage
    FILE_FORMAT = (FORMAT_NAME = pipe_format)
    PATTERN = '.*\.csv';

SELECT * FROM s3_loaded_contacts;


--LEVEL 3 - EXTERNAL SYSTEMS - AZURE DATA FACTORY

USE SCHEMA RETAIL_DB.SALES;

-- Target table had to exist BEFORE the ADF dataset schema import would work
CREATE OR REPLACE TABLE adf_loaded_contacts (
    id              VARCHAR,
    lastname        VARCHAR,
    firstname       VARCHAR,
    company         VARCHAR,
    email           VARCHAR,
    workphone       VARCHAR,
    cellphone       VARCHAR,
    streetaddress   VARCHAR,
    city            VARCHAR,
    postalcode      VARCHAR
);


SHOW TABLES LIKE 'ADF%' IN SCHEMA RETAIL_DB.SALES;

-- Verify the ADF pipeline actually loaded data successfully
SELECT * FROM RETAIL_DB.SALES.ADF_LOADED_CONTACTS;


--LEVEL 3 - EXTERNAL SYSTEMS - REST API


SELECT
    raw_json:name::STRING AS name,
    raw_json:email::STRING AS email,
    raw_json:address.city::STRING AS city,
    raw_json:company.name::STRING AS company_name
FROM api_users_raw;


--LEVEL 4

USE SCHEMA RETAIL_DB.SALES;

-- Streams & Tasks (Change Data Capture)

SELECT * FROM customers;


CREATE OR REPLACE STREAM customers_stream ON TABLE customers;

SELECT * FROM customers_stream;   -- empty at first, nothing has changed yet

INSERT INTO customers (first_name, last_name, email, signup_date) VALUES
    ('Nina', 'Patel', 'nina.patel@example.com', '2024-08-01');

SELECT * FROM customers_stream;   -- now shows the new row, with METADATA$ACTION = INSERT

CREATE OR REPLACE TABLE customers_change_log (
    customer_id     INT,
    first_name      VARCHAR,
    last_name       VARCHAR,
    email           VARCHAR,
    change_type     VARCHAR,
    processed_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


CREATE OR REPLACE TASK process_customer_changes
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '1 MINUTE'
WHEN
    SYSTEM$STREAM_HAS_DATA('customers_stream')
AS
    INSERT INTO customers_change_log (customer_id, first_name, last_name, email, change_type)
    SELECT customer_id, first_name, last_name, email, METADATA$ACTION
    FROM customers_stream;


ALTER TASK process_customer_changes RESUME;

SHOW TASKS LIKE 'process_customer_changes';   

SELECT * FROM customers_change_log;  


UPDATE customers SET email = 'nina.patel.updated@example.com' WHERE first_name = 'Nina';

SELECT * FROM customers_change_log ORDER BY processed_at DESC;  


ALTER TASK process_customer_changes SUSPEND;


--Stored Procedures


CREATE OR REPLACE PROCEDURE validate_customers_proc()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    total_count INT;
    bad_count INT;
BEGIN
    SELECT COUNT(*) INTO :total_count FROM customers;
    SELECT COUNT(*) INTO :bad_count FROM customers WHERE email IS NULL OR email NOT LIKE '%@%';

    INSERT INTO PIPELINE_AUDIT_LOG (source_table, records_read, records_passed, records_rejected, status)
    VALUES ('customers', :total_count, :total_count - :bad_count, :bad_count, 'COMPLETED');

    RETURN 'Validation complete. Total: ' || :total_count || ', Bad emails: ' || :bad_count;
END;
$$;

CALL validate_customers_proc();

SELECT * FROM PIPELINE_AUDIT_LOG ORDER BY run_timestamp DESC LIMIT 3;


--Performance Tuning 


SELECT
    query_text,
    execution_status,
    total_elapsed_time / 1000 AS elapsed_seconds,
    bytes_scanned / (1024*1024) AS mb_scanned,
    warehouse_name,
    start_time
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER BY start_time DESC
LIMIT 20;

-- Find the slowest queries specifically
SELECT
    query_text,
    total_elapsed_time / 1000 AS elapsed_seconds,
    bytes_scanned / (1024*1024) AS mb_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC
LIMIT 5;


--Cost Optimization 


SHOW WAREHOUSES LIKE 'COMPUTE_WH';


CREATE OR REPLACE RESOURCE MONITOR practice_monitor
WITH
    CREDIT_QUOTA = 5
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 75 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = practice_monitor;

SHOW WAREHOUSES LIKE 'COMPUTE_WH';   


--Security & RBAC 

SELECT CURRENT_ROLE();

SHOW ROLES;

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS READONLY_ANALYST;

GRANT USAGE ON DATABASE RETAIL_DB TO ROLE READONLY_ANALYST;
GRANT USAGE ON SCHEMA RETAIL_DB.SALES TO ROLE READONLY_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA RETAIL_DB.SALES TO ROLE READONLY_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE READONLY_ANALYST;

GRANT ROLE READONLY_ANALYST TO USER AARTHIUS;


USE ROLE READONLY_ANALYST;
SELECT * FROM customers;                         
INSERT INTO customers (first_name) VALUES ('Test'); 

SELECT CURRENT_ROLE();  


SHOW GRANTS TO ROLE READONLY_ANALYST;   
SHOW GRANTS ON TABLE customers;       

-
USE SECONDARY ROLES NONE;

INSERT INTO customers (first_name) VALUES ('ShouldFail'); 

