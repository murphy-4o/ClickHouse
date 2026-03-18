-- Test that tryOptimizeTopK does not displace WHERE from prewhere
-- and produces correct results when combined with WHERE clauses.

DROP TABLE IF EXISTS tab_topk_where;
CREATE TABLE tab_topk_where
(
    id UInt32,
    val String,
    val_n Nullable(String),
    num UInt64,
    cat LowCardinality(String)
) Engine = MergeTree ORDER BY id
SETTINGS index_granularity = 64, min_bytes_for_wide_part = 0,
         min_bytes_for_full_part_storage = 0, max_bytes_to_merge_at_max_space_in_pool = 1,
         use_const_adaptive_granularity = 1, index_granularity_bytes = 0;

INSERT INTO tab_topk_where
SELECT
    number,
    lpad(toString(number), 6, '0'),
    if(number % 100 = 0, NULL, lpad(toString(number), 6, '0')),
    number * 7 % 10007,
    if(number % 3 = 0, 'alpha', if(number % 3 = 1, 'beta', 'gamma'))
FROM numbers(10000);

-- 1. No WHERE: __topKFilter should be in prewhere
SELECT '-- No WHERE, String';
SELECT val FROM tab_topk_where ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

SELECT '-- No WHERE, Nullable(String)';
SELECT val_n FROM tab_topk_where ORDER BY val_n LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

-- 2. WHERE on the ORDER BY column
SELECT '-- WHERE on sort column (String)';
SELECT val FROM tab_topk_where WHERE val > '005000' ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

SELECT '-- WHERE on sort column (Nullable)';
SELECT val_n FROM tab_topk_where WHERE val_n > '005000' ORDER BY val_n LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

-- 3. WHERE on a different column that gets pushed to prewhere
SELECT '-- WHERE on different column (pushed to prewhere)';
SELECT val FROM tab_topk_where WHERE cat = 'alpha' ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

SELECT '-- WHERE on different column, Nullable sort';
SELECT val_n FROM tab_topk_where WHERE cat = 'beta' ORDER BY val_n LIMIT 5 SETTINGS use_top_k_dynamic_filtering=1;

-- 4. Verify results match setting=0
SELECT '-- Correctness: no WHERE (setting=0)';
SELECT val FROM tab_topk_where ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=0;

SELECT '-- Correctness: WHERE on sort column (setting=0)';
SELECT val FROM tab_topk_where WHERE val > '005000' ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=0;

SELECT '-- Correctness: WHERE on different column (setting=0)';
SELECT val FROM tab_topk_where WHERE cat = 'alpha' ORDER BY val LIMIT 5 SETTINGS use_top_k_dynamic_filtering=0;

-- 5. EXPLAIN checks: verify __topKFilter placement
--    No WHERE: __topKFilter should appear in prewhere
SELECT '-- EXPLAIN no WHERE: has __topKFilter';
SELECT count() > 0 FROM (
    EXPLAIN PLAN actions=1
    SELECT val FROM tab_topk_where ORDER BY val LIMIT 5
    SETTINGS use_top_k_dynamic_filtering=1
) WHERE explain LIKE '%__topKFilter%' AND explain LIKE '%Prewhere%';

--    WHERE on different column pushed to prewhere: __topKFilter should NOT be in prewhere
SELECT '-- EXPLAIN WHERE pushed to prewhere: no __topKFilter';
SELECT count() FROM (
    EXPLAIN PLAN actions=1
    SELECT val FROM tab_topk_where WHERE cat = 'alpha' ORDER BY val LIMIT 5
    SETTINGS use_top_k_dynamic_filtering=1
) WHERE explain LIKE '%__topKFilter%';

--    WHERE on different column: the WHERE predicate IS in prewhere
SELECT '-- EXPLAIN WHERE pushed to prewhere: has equals(cat)';
SELECT count() > 0 FROM (
    EXPLAIN PLAN actions=1
    SELECT val FROM tab_topk_where WHERE cat = 'alpha' ORDER BY val LIMIT 5
    SETTINGS use_top_k_dynamic_filtering=1
) WHERE explain LIKE '%Prewhere%' AND explain LIKE '%equals%';

DROP TABLE tab_topk_where;
