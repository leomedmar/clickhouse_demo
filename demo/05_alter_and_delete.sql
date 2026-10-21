-- ============================================================
-- DEMO 4 — Changing structure and data: ALTER, UPDATE, DELETE
-- Uses the demo.sales table (Demo 1)
-- ============================================================
USE demo;

-- 1. Structural ALTER
--    ADD / RENAME / DROP COLUMN → metadata only → instant, even with 10M rows
--    MODIFY COLUMN (change type) → rewrites the column in the background (mutation)
ALTER TABLE sales ADD COLUMN channel LowCardinality(String) DEFAULT 'store';
ALTER TABLE sales RENAME COLUMN channel TO sales_channel;
ALTER TABLE sales MODIFY COLUMN quantity UInt16;
DESCRIBE TABLE sales;

-- 2. Lightweight DELETE: marks rows as deleted, cleaned up on the next merge
SELECT count() FROM sales WHERE country = 'UK';
DELETE FROM sales WHERE country = 'UK';
SELECT count() FROM sales WHERE country = 'UK';   -- 0, immediately

-- 3. UPDATE = MUTATION: asynchronous and rewrites the affected parts → expensive!
ALTER TABLE sales UPDATE sales_channel = 'online' WHERE product = 'Laptop';

-- Track mutations
SELECT mutation_id, command, is_done, parts_to_do
FROM system.mutations
WHERE database = 'demo' AND table = 'sales'
ORDER BY create_time;

SELECT sales_channel, count() FROM sales GROUP BY sales_channel;
-- → right after, everything may still show as 'store': the mutation runs in the background.
--   Repeat the two queries above after a few seconds.
--   (To wait for it to finish: SET mutations_sync = 1; before the ALTER ... UPDATE)

-- 4. Idiomatic pattern instead of UPDATE: insert a new version + ReplacingMergeTree
CREATE TABLE stock (
    product     String,
    quantity    Int32,
    updated_at  DateTime
)
ENGINE = ReplacingMergeTree(updated_at)   -- keeps the most recent version
ORDER BY product;

INSERT INTO stock VALUES ('Laptop', 10, '2026-10-01 09:00:00'), ('Mouse', 50, '2026-10-01 09:00:00');
INSERT INTO stock VALUES ('Laptop',  7, '2026-10-02 09:00:00');   -- "update"

SELECT * FROM stock ORDER BY product;         -- may show duplicates (not merged yet)
SELECT * FROM stock FINAL ORDER BY product;   -- FINAL: deduplicates at read time

-- 5. Clean up
TRUNCATE TABLE stock;            -- deletes data, keeps the structure
DROP TABLE stock;
