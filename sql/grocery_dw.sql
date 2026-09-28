-- CIS 3050 Grocery Chain Sales DW (MySQL 8.0)
-- Source dataset: SuperMarket Analysis.csv
-- This script creates schema, staging, dimensions, fact, ETL steps, and report queries.
-- Execute in MySQL Workbench.




/* --------------------
   1) STAGING TABLE
   -------------------- */
DROP TABLE IF EXISTS stg_supermarket_raw;
CREATE TABLE stg_supermarket_raw (
  Invoice_ID VARCHAR(30),
  Branch VARCHAR(20),
  City VARCHAR(50),
  Customer_type VARCHAR(20),
  Gender VARCHAR(10),
  Product_line VARCHAR(100),
  Unit_price DECIMAL(10,2),
  Quantity INT,
  Tax_5 DECIMAL(12,4),
  Sales DECIMAL(12,4),
  Date VARCHAR(20),
  Time VARCHAR(20),
  Payment VARCHAR(20),
  cogs DECIMAL(12,4),
  gross_margin_percentage DECIMAL(8,6),
  gross_income DECIMAL(12,4),
  Rating DECIMAL(3,1)
);



/* --------------------
   2) DIMENSION TABLES
   -------------------- */
DROP TABLE IF EXISTS TRANSACTION_FACT;
DROP TABLE IF EXISTS TIME_DIM;
DROP TABLE IF EXISTS PRODUCT;
DROP TABLE IF EXISTS STORE;

CREATE TABLE STORE (
  store_id     INT AUTO_INCREMENT PRIMARY KEY,
  branch_code  VARCHAR(10) NOT NULL,
  city         VARCHAR(50) NOT NULL,
  UNIQUE KEY uk_store_branch_city (branch_code, city)
);

CREATE TABLE PRODUCT (
  product_id   INT AUTO_INCREMENT PRIMARY KEY,
  product_line VARCHAR(100) NOT NULL,
  unit_price   DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  UNIQUE KEY uk_product_line_price (product_line, unit_price)
);

CREATE TABLE TIME_DIM (
  time_id       INT AUTO_INCREMENT PRIMARY KEY,
  sale_date     DATE NOT NULL,
  sale_time     TIME NULL,
  day_name      ENUM('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') NOT NULL,
  week_of_year  TINYINT NOT NULL,
  month_num     TINYINT NOT NULL,
  month_name    VARCHAR(12) NOT NULL,
  quarter_num   TINYINT NOT NULL,
  year_num      SMALLINT NOT NULL,
  UNIQUE KEY uk_time_date_time (sale_date, sale_time)
);


/* --------------------
   3) FACT TABLE
   -------------------- */
CREATE TABLE TRANSACTION_FACT (
  invoice_id      VARCHAR(20) PRIMARY KEY,
  store_id        INT NOT NULL,
  product_id      INT NOT NULL,
  time_id         INT NOT NULL,
  quantity        INT NOT NULL CHECK (quantity >= 0),
  tax             DECIMAL(10,2) NOT NULL CHECK (tax >= 0),
  sales           DECIMAL(12,2) NOT NULL CHECK (sales >= 0),
  cogs            DECIMAL(12,2) NOT NULL CHECK (cogs >= 0),
  gross_income    DECIMAL(12,2) NOT NULL CHECK (gross_income >= 0),
  payment_method  VARCHAR(20) NOT NULL,
  customer_type   VARCHAR(20) NOT NULL,
  gender          VARCHAR(10) NOT NULL,
  rating          DECIMAL(3,1) NULL,
  CONSTRAINT fk_tf_store   FOREIGN KEY (store_id)   REFERENCES STORE(store_id),
  CONSTRAINT fk_tf_product FOREIGN KEY (product_id) REFERENCES PRODUCT(product_id),
  CONSTRAINT fk_tf_time    FOREIGN KEY (time_id)    REFERENCES TIME_DIM(time_id)
);

-- Performance indexes
CREATE INDEX ix_tf_time_store   ON TRANSACTION_FACT (time_id, store_id);
CREATE INDEX ix_tf_product_time ON TRANSACTION_FACT (product_id, time_id);
CREATE INDEX ix_tf_payment      ON TRANSACTION_FACT (payment_method);


/* --------------------
   4) ETL: POPULATE DIMENSIONS
   -------------------- */

-- STORE
INSERT INTO STORE (branch_code, city)
SELECT DISTINCT Branch, City
FROM STG_SUPERMARKET_RAW
WHERE Branch IS NOT NULL AND City IS NOT NULL;

-- PRODUCT (granularity = product_line + unit_price)
INSERT INTO PRODUCT (product_line, unit_price)
SELECT DISTINCT Product_line, Unit_price
FROM STG_SUPERMARKET_RAW
WHERE Product_line IS NOT NULL AND Unit_price IS NOT NULL;

-- TIME_DIM
INSERT INTO TIME_DIM (
  sale_date, sale_time, day_name, week_of_year, month_num, month_name, quarter_num, year_num
)
SELECT DISTINCT
  STR_TO_DATE(Date, '%m/%d/%Y') AS sale_date,
  STR_TO_DATE(Time, '%h:%i:%s %p') AS sale_time,
  DAYNAME(STR_TO_DATE(Date, '%m/%d/%Y')),
  WEEKOFYEAR(STR_TO_DATE(Date, '%m/%d/%Y')),
  MONTH(STR_TO_DATE(Date, '%m/%d/%Y')),
  DATE_FORMAT(STR_TO_DATE(Date, '%m/%d/%Y'), '%M'),
  QUARTER(STR_TO_DATE(Date, '%m/%d/%Y')),
  YEAR(STR_TO_DATE(Date, '%m/%d/%Y'))
FROM STG_SUPERMARKET_RAW;


/* --------------------
   5) ETL: POPULATE FACT
   -------------------- */
INSERT INTO TRANSACTION_FACT (
  invoice_id, store_id, product_id, time_id, quantity, tax, sales, cogs, gross_income,
  payment_method, customer_type, gender, rating
)
SELECT
  r.Invoice_ID,
  s.store_id,
  p.product_id,
  t.time_id,
  r.Quantity,
  r.Tax_5,
  r.Sales,
  r.cogs,
  r.gross_income,
  r.Payment,
  r.Customer_type,
  r.Gender,
  r.Rating
FROM STG_SUPERMARKET_RAW r
JOIN STORE   s ON s.branch_code = r.Branch AND s.city = r.City
JOIN PRODUCT p ON p.product_line = r.Product_line AND p.unit_price = r.Unit_price
JOIN TIME_DIM t ON t.sale_date = STR_TO_DATE(r.Date, '%m/%d/%Y')
               AND ((t.sale_time IS NULL AND r.Time IS NULL)
                 OR  t.sale_time = STR_TO_DATE(r.Time, '%h:%i:%s %p'));


/* --------------------
   6) VALIDATION QUERIES
   -------------------- */
SELECT COUNT(*) AS rows_fact FROM TRANSACTION_FACT;
SELECT COUNT(*) AS products   FROM PRODUCT;
SELECT COUNT(*) AS stores     FROM STORE;
SELECT COUNT(*) AS days       FROM TIME_DIM;

-- Missing FK checks (should be zero)
SELECT COUNT(*) AS missing_store_fk
FROM STG_SUPERMARKET_RAW r
LEFT JOIN STORE s ON s.branch_code=r.Branch AND s.city=r.City
WHERE s.store_id IS NULL;

SELECT COUNT(*) AS missing_product_fk
FROM STG_SUPERMARKET_RAW r
LEFT JOIN PRODUCT p ON p.product_line=r.Product_line AND p.unit_price=r.Unit_price
WHERE p.product_id IS NULL;


/* --------------------
   7) BUSINESS REPORT QUERIES
   -------------------- */

-- A) Sales by Day of Week
SELECT t.day_name,
       SUM(f.quantity)     AS total_units,
       SUM(f.sales)        AS total_sales,
       SUM(f.gross_income) AS total_gross_income
FROM TRANSACTION_FACT f
JOIN TIME_DIM t ON f.time_id = t.time_id
GROUP BY t.day_name
ORDER BY FIELD(t.day_name,'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday');

-- B) Sales by Month
SELECT t.month_name,
       SUM(f.sales) AS total_sales
FROM TRANSACTION_FACT f
JOIN TIME_DIM t ON f.time_id = t.time_id
GROUP BY t.month_num, t.month_name
ORDER BY t.month_num;

-- C) Sales by Quarter & Year
SELECT t.year_num  AS year,
       t.quarter_num AS quarter,
       SUM(f.sales)   AS total_sales,
       SUM(f.cogs)    AS total_cogs,
       SUM(f.gross_income) AS total_gross_income
FROM TRANSACTION_FACT f
JOIN TIME_DIM t ON f.time_id = t.time_id
GROUP BY t.year_num, t.quarter_num
ORDER BY t.year_num, t.quarter_num;

-- D) Top 5 Product Lines by Sales
SELECT p.product_line,
       SUM(f.sales) AS sales
FROM TRANSACTION_FACT f
JOIN PRODUCT p ON f.product_id = p.product_id
GROUP BY p.product_line
ORDER BY sales DESC
LIMIT 5;

-- E) Store Performance (Branch/City)
SELECT s.branch_code AS branch,
       s.city,
       SUM(f.sales)        AS total_sales,
       AVG(f.rating)       AS avg_rating,
       COUNT(*)            AS txns
FROM TRANSACTION_FACT f
JOIN STORE s ON f.store_id = s.store_id
GROUP BY s.store_id, s.branch_code, s.city
ORDER BY total_sales DESC;

-- F) Payment Mix
SELECT payment_method, COUNT(*) AS txns, SUM(sales) AS sales
FROM TRANSACTION_FACT
GROUP BY payment_method
ORDER BY sales DESC;

-- G) Rolling 7-Day Sales (trend)
WITH daily AS (
  SELECT t.sale_date, SUM(f.sales) AS daily_sales
  FROM TRANSACTION_FACT f
  JOIN TIME_DIM t ON f.time_id = t.time_id
  GROUP BY t.sale_date
)
SELECT sale_date,
       daily_sales,
       AVG(daily_sales) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7d_avg
FROM daily
ORDER BY sale_date;


/* --------------------
   8) ROLES & ACCESS CONTROL (optional)
   -------------------- */
-- CREATE ROLE role_admin, role_analyst, role_clerk, role_guest;
-- GRANT ALL PRIVILEGES ON *.* TO role_admin;
-- GRANT SELECT, SHOW VIEW ON *.* TO role_analyst;
-- GRANT INSERT, SELECT ON TRANSACTION_FACT TO role_clerk;
-- GRANT SELECT ON PRODUCT, STORE, TIME_DIM TO role_clerk;
-- GRANT SELECT ON PRODUCT, STORE, TIME_DIM, TRANSACTION_FACT TO role_guest;
