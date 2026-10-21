-- ============================================================
-- DEMO 1 — First steps: database, table, INSERT, SELECT
-- Run in: docker exec -it clickhouse-1 clickhouse-client
-- ============================================================

-- 1. Database
CREATE DATABASE IF NOT EXISTS demo;
USE demo;

-- 2. First MergeTree table
CREATE TABLE sales (
    id          UInt64,
    sale_date   Date,
    product     String,
    category    LowCardinality(String),
    amount      Decimal(10, 2),
    quantity    UInt32,
    country     LowCardinality(String)
)
ENGINE = MergeTree
ORDER BY (sale_date, category);

-- 3. INSERT with VALUES (for testing only!)
INSERT INTO sales VALUES
    (1, '2026-01-15', 'Laptop',   'Electronics', 999.99, 1, 'PT'),
    (2, '2026-01-15', 'Mouse',    'Electronics',  29.99, 3, 'PT'),
    (3, '2026-01-16', 'Desk',     'Furniture',   249.00, 1, 'ES'),
    (4, '2026-01-16', 'Chair',    'Furniture',   189.00, 2, 'PT'),
    (5, '2026-01-17', 'Monitor',  'Electronics', 399.00, 1, 'FR');

SELECT * FROM sales;

-- 4. INSERT ... SELECT: generate 10 million synthetic rows
INSERT INTO sales
SELECT
    number + 10                                                         AS id,
    today() - toUInt32(randUniform(0, 365))                             AS sale_date,
    ['Laptop','Mouse','Keyboard','Monitor','Desk','Chair'][rand() % 6 + 1] AS product,
    ['Electronics','Furniture','Accessories'][rand() % 3 + 1]           AS category,
    round(randUniform(10, 2000), 2)                                     AS amount,
    toUInt32(randUniform(1, 20))                                        AS quantity,
    ['PT','ES','FR','DE','UK'][rand() % 5 + 1]                          AS country
FROM numbers(10000000);

-- 5. Analytical queries — note the response time
SELECT count() FROM sales;

SELECT
    category,
    formatReadableQuantity(sum(amount * quantity)) AS revenue,
    count()                                        AS num_sales
FROM sales
GROUP BY category
ORDER BY sum(amount * quantity) DESC;

SELECT
    toStartOfMonth(sale_date) AS month,
    country,
    round(sum(amount), 2)     AS revenue
FROM sales
WHERE sale_date >= today() - 90
GROUP BY month, country
ORDER BY month, revenue DESC;

-- 6. Inspect
DESCRIBE TABLE sales;
SHOW CREATE TABLE sales;

-- 7. Compression per column (the "why" of columnar)
SELECT
    name                                              AS column_name,
    type,
    formatReadableSize(data_uncompressed_bytes)       AS original,
    formatReadableSize(data_compressed_bytes)         AS compressed,
    round(data_uncompressed_bytes / data_compressed_bytes, 1) AS ratio
FROM system.columns
WHERE database = 'demo' AND table = 'sales'
ORDER BY data_compressed_bytes DESC;
