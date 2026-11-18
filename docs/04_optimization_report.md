# Phase 4 · Optimization Report (CP3)

**Team T0070 · Google Maps Navigation Database**

Files for this checkpoint:

| File | What it is |
|------|------------|
| `sql/05_indexes.sql` | 17 new indexes, each with the queries it serves and why this type/column order |
| `sql/06_optimized_queries.sql` | Copy of the workload; 7 queries rewritten (R07, R10, R11, R13, R14, R19, R20), the rest unchanged |
| `benchmarks/results/optimized/summary.csv` | Optimized timings, 3 runs per query (avg / median / min / max / scan nodes) |
| `benchmarks/results/optimized/summary.md` | The same summary as a readable table |

[Baseline summary](../benchmarks/results/baseline/summary.csv) · [Optimized summary](../benchmarks/results/optimized/summary.md)

## How we measured

* Same method as Phase 3: `EXPLAIN (ANALYZE, BUFFERS)`, **3 runs, average**, writes inside `BEGIN … ROLLBACK`.
* **Before and after were measured on the same machine, back to back**, so the comparison is fair:
  * Before: `./benchmarks/run_benchmark.sh <db> baseline` on a database with only `01_schema.sql` + `02_load_data.sql`
  * After: same data + `sql/05_indexes.sql`, then `./benchmarks/run_benchmark.sh <db> optimized 3 sql/06_optimized_queries.sql` → `benchmarks/results/optimized/summary.csv`
* Machine: PostgreSQL 16.15 on a 2-vCPU Intel Xeon @ 2.10 GHz Linux VM, 7 GB RAM. Session time zone `Asia/Kolkata` (it matters for R10, R11, R20 — see below).
* The absolute numbers differ from `docs/03_baseline_timings.md` (that run was on a different laptop), which is why the "Before" column below was re-measured on the same machine as the optimized run, so both columns come from one machine.
* Timings below 1 ms vary by ±30 % between runs on this machine; treat changes in that range as noise.

## Schema fix found while benchmarking

`W01` inserts a session without `rerouted_count`, but `sql/01_schema.sql` declared it `NOT NULL` with no default, so `W01` failed with *null value in column "rerouted_count"*. A navigation that has just started has been re-routed 0 times, so the fix is a default, not a change to the query:

```sql
rerouted_count   SMALLINT NOT NULL DEFAULT 0,
```

(`sql/01_schema.sql` is updated. On an existing database: `ALTER TABLE gmaps.navigation_sessions ALTER COLUMN rerouted_count SET DEFAULT 0;`)

## Optimization table

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01 | 16.637 | Seq Scan on 40k places, acos() on every row | Partial covering index `idx_places_open_cat_lat (category_id, latitude) INCLUDE (longitude, name, avg_rating) WHERE NOT is_permanently_closed` | 0.964 | 94.2% (17.3×) | ✅ |
| R02 | 0.141 | Already PK lookups (places_pkey, pk_opening_hours) | None needed | 0.157 | -11.3% (slower) | ✅ |
| R03 | 23.769 | Seq Scan: `ILIKE '%biryani%'` has a leading wildcard | Trigram GIN `idx_places_name_trgm`, ANDed with `idx_places_city_cat_rating` (BitmapAnd) | 7.318 | 69.2% (3.2×) | ✅ |
| R04 | 27.037 | Seq Scan on places **and** on 252k opening_hours, hash join | `idx_places_city_cat_rating (city_id, category_id, avg_rating DESC NULLS LAST)` → read in rating order + PK probe into opening_hours, stops after 30 rows | 1.867 | 93.1% (14.5×) | ✅ (ties)* |
| R05 | 0.546 | Bitmap scan on (place_id, user_id) + sort | `idx_reviews_place_created (place_id, created_at DESC)`: reads exactly 10 entries, no sort | 0.385 | 29.5% (1.4×) | ✅ |
| R06 | 0.192 | Already PK scan on saved_places | None needed | 0.213 | -10.9% (slower) | ✅ |
| R07 | 18.146 | DISTINCT ON reads + sorts every reading of 40 segments | **Rewrite** to `LATERAL … ORDER BY recorded_at DESC LIMIT 1` + `idx_segments_city_road`, `idx_traffic_segment_time_speed` (Index Only, 1 entry per segment) | 0.417 | 97.7% (43.5×) | ✅ |
| R08 | 1.236 | Seq Scan on road_segments; index on (segment_id, recorded_at) not useful for a time filter | Partial `idx_traffic_heavy_time (recorded_at DESC) WHERE congestion_level IN ('HEAVY','STANDSTILL')` | 0.229 | 81.5% (5.4×) | ✅ |
| R09 | 0.603 | Bitmap Heap Scan: visits heap for avg_speed_kmph | Covering `idx_traffic_segment_time_speed … INCLUDE (avg_speed_kmph)` → Index Only Scan | 0.232 | 61.5% (2.6×) | ✅ |
| R10 | 2.447 | `DATE(reported_at) = …` is not sargable → Seq Scan | **Rewrite** to half-open range on `reported_at` + `idx_incidents_reported` | 0.235 | 90.4% (10.4×) | ✅ |
| R11 | 57.958 | `EXTRACT(YEAR …) = 2026` not sargable → Seq Scan 200k | **Rewrite** to range + covering `idx_nav_started_cover` (Index Only). Still reads 1/3 of the table | 41.559 | 28.3% (1.4×) | ✅ |
| R12 | 32.687 | Seq Scan of 200k sessions for 7 days of data | `idx_nav_started_cover` (Index Only on the last 7 days) + `idx_places_city_cat_rating` | 6.369 | 80.5% (5.1×) | ✅ (ties)* |
| R13 | 81.994 | **Wrong result:** `NOT IN` over a column with NULLs returns 0 rows | **Rewrite** to `NOT EXISTS` (anti-join) + partial `idx_nav_origin WHERE origin_place_id IS NOT NULL` | 16.805 | 79.5% (4.9×) | ❌→✅ fixed (0 → 33,368 rows) |
| R14 | 40.750 | Joins all 2026 reviews to all 40k users before grouping | **Rewrite**: aggregate reviews first (Index Only on `idx_reviews_created_cover`), join only the top 20 users by PK | 5.308 | 87.0% (7.7×) | ✅ (ties)* |
| R15 | 184.713 | Seq Scan + hash aggregate of all 90k reviews | `idx_reviews_place_rating (place_id) INCLUDE (rating)` → sorted Index Only Scan, Merge Join with places | 55.847 | 69.8% (3.3×) | ✅ |
| R16 | 38.869 | Seq Scan on sessions and places | Partial `idx_places_closed WHERE is_permanently_closed` (~1 % of places) + `idx_nav_dest_started` probes per closed place | 5.509 | 85.8% (7.1×) | ✅ (ties)* |
| R17 | 169.813 | Seq Scan + HashAggregate of 39k groups | Narrow `idx_nav_dest_reroutes (dest_place_id, rerouted_count)` → streaming GroupAggregate on Index Only Scan. Still reads every row | 53.951 | 68.2% (3.1×) | ✅ (ties)* |
| R18 | 40.280 | Seq Scan of the wide 200k-row heap | `idx_nav_mode_status` (Index Only). Must still count every row → small gain | 36.702 | 8.9% (1.1×) | ✅ |
| R19 | 20999.140 | Two correlated subqueries = 2 Seq Scans of 200k sessions **per hospital** | **Rewrite** to one `LEFT JOIN … GROUP BY` + `idx_nav_dest_started` (Index Only per hospital) | 7.222 | 100.0% (2907.7×) | ✅ (ties)* |
| R20 | 24.980 | `started_at::date BETWEEN` casts every row → Seq Scan | **Rewrite** to range + `idx_nav_started_cover` (Index Only) | 4.149 | 83.4% (6.0×) | ✅ |
| R21 | 58.115 | Hash Anti Join: must read all 252k opening_hours rows | None that helps; same plan before and after, so the difference is run-to-run noise (see *Queries we could not speed up*) | 82.845 | -42.6% (slower) | ✅ |
| R22 | 45.212 | Seq Scan + top-N sort of all 90k reviews for OFFSET 50,000 | Covering `idx_reviews_created_cover (created_at DESC) INCLUDE (…)` → Index Only Scan, no sort (still steps over 50k entries; keyset pagination planned for CP4) | 9.462 | 79.1% (4.8×) | ✅ |
| R23 | 0.067 | Already unique-index lookup on plus_code | None needed | 0.051 | 23.9% (1.3×) | ✅ |
| R24 | 19.756 | Self-join of places; Hash Join is the cheapest plan | `idx_places_city_cat_rating` for the outer side; inner side still a Seq Scan (see below) | 13.704 | 30.6% (1.4×) | ✅ |
| R25 | 69.241 | Must aggregate all 250k readings | None that helps (see below) | 67.452 | 2.6% (1.0×) | ✅ |
| W01 | 1.175 | Single INSERT | None — pays for 6 new navigation_sessions indexes (write overhead) | 1.326 | -12.9% (slower) | ✅ |
| W02 | 1.211 | Single INSERT … ON CONFLICT | None — pays for 3 new place_reviews indexes | 1.697 | -40.1% (slower) | ✅ |
| W03 | 1.345 | Single INSERT … ON CONFLICT | None (no new index on saved_places) | 1.102 | 18.1% (1.2×) | ✅ |
| W04 | 148.189 | Seq Scan + hash aggregate of all reviews, then UPDATE of changed rows | Unchanged query; aggregate is unavoidable | 132.180 | 10.8% (1.1×) | ✅ |
| W05 | 5.380 | Deletes 11,339 of 12,000 rows → Seq Scan is correct | `idx_incidents_expires` (used only when few rows expire, e.g. a daily job) | 6.020 | -11.9% (slower) | ✅ |
| **Total** | **22111.629** | | | **561.277** | **97.5% (39.4×)** | |

\* **"✅ (ties)"** — the rows are correct, but the original query's `ORDER BY` leaves ties, so PostgreSQL may return tied rows in any order (and with `LIMIT`, pick any of the tied rows). This is allowed by SQL and also happens between two runs of the *same* query when the plan changes. Details in *Proof that results are unchanged*.

**Headline:** total workload time **22,111.6 ms → 561.3 ms (97.5 %, 39× faster)**. Without R19 the rest of the workload went from 1,112.5 ms to 554.1 ms (2.0× faster). Real-time queries (R01, R04, R05, R07, R08, R10) are all under 2 ms now.

---

## The wrong-result query: R13 (NOT IN + NULL)

```sql
-- original: returns 0 rows
WHERE p.place_id NOT IN (SELECT n.origin_place_id FROM navigation_sessions n);
```

* 192,584 of 200,000 sessions (96 %) have `origin_place_id = NULL`, because they started from the user's GPS position, not from a known place.
* `x NOT IN (a, b, NULL)` means `x <> a AND x <> b AND x <> NULL`. `x <> NULL` is **UNKNOWN**, so the whole condition is never TRUE; at best it is UNKNOWN. `WHERE` keeps only TRUE rows → **every place is dropped, 0 rows**. That is why problem **P6** says the list is "empty, which is impossible".
* Fix: `NOT EXISTS (SELECT 1 FROM navigation_sessions n WHERE n.origin_place_id = p.place_id)`. `NOT EXISTS` only asks whether a matching row exists; a NULL never matches, so it is simply ignored. Result: **33,368 places** were never a starting point.
* Check: 40,042 places − 6,674 distinct non-NULL origin places = 33,368 ✅.
* Speed: planned as an anti-join that probes the small partial index `idx_nav_origin` (only the 7,416 non-NULL origins, 176 kB), instead of a NOT IN over 200k values.

## Before / after plans for the 5 biggest improvements

### R19: 20,999.140 ms → 7.222 ms (2,908× faster)

Two correlated subqueries, each a Seq Scan of all 200,000 sessions, executed **1,067 times** (once per Bengaluru hospital) → ~427 million rows read. After the rewrite, one nested loop probes `idx_nav_dest_started` once per hospital (5 entries each) as an Index Only Scan.

**Before** (run 3):
```
Sort  (cost=14743852.91..14743856.32 rows=1364 width=40) (actual time=19008.791..19008.874 rows=1067 loops=1)
  Sort Key: ((SubPlan 1)) DESC
  Sort Method: quicksort  Memory: 123kB
  InitPlan 3 (returns $2)
    ->  Seq Scan on place_categories  (cost=0.00..1.15 rows=1 width=4) (actual time=0.045..0.046 rows=1 loops=1)
          Filter: ((category_name)::text = 'Hospital'::text)
          Rows Removed by Filter: 11
  ->  Seq Scan on places p  (cost=0.00..14743780.74 rows=1364 width=40) (actual time=169.863..19004.458 rows=1067 loops=1)
        Filter: ((category_id = $2) AND (city_id = 1))
        Rows Removed by Filter: 38975
        SubPlan 1
          ->  Aggregate  (cost=5404.02..5404.03 rows=1 width=8) (actual time=8.807..8.808 rows=1 loops=1067)
                ->  Seq Scan on navigation_sessions n  (cost=0.00..5404.00 rows=6 width=0) (actual time=2.050..8.795 rows=5 loops=1067)
                      Filter: (dest_place_id = p.place_id)
                      Rows Removed by Filter: 199995
        SubPlan 2
          ->  Aggregate  (cost=5404.02..5404.03 rows=1 width=8) (actual time=8.842..8.842 rows=1 loops=1067)
                ->  Seq Scan on navigation_sessions n_1  (cost=0.00..5404.00 rows=6 width=8) (actual time=2.070..8.829 rows=5 loops=1067)
                      Filter: (dest_place_id = p.place_id)
                      Rows Removed by Filter: 199995
Execution Time: 19023.837 ms
```
**After** (run 3):
```
Sort  (cost=1855.55..1862.24 rows=2678 width=40) (actual time=6.980..7.028 rows=1067 loops=1)
  Sort Key: (count(n.dest_place_id)) DESC, p.place_id
  Sort Method: quicksort  Memory: 123kB
  ->  HashAggregate  (cost=1676.30..1703.08 rows=2678 width=40) (actual time=6.208..6.394 rows=1067 loops=1)
        Group Key: p.place_id
        Batches: 1  Memory Usage: 241kB
        ->  Nested Loop Left Join  (cost=58.73..1656.21 rows=2678 width=36) (actual time=0.333..5.250 rows=5450 loops=1)
              ->  Nested Loop  (cost=58.31..1057.43 rows=565 width=24) (actual time=0.306..1.644 rows=1067 loops=1)
                    ->  Seq Scan on place_categories c  (cost=0.00..1.15 rows=1 width=4) (actual time=0.008..0.012 rows=1 loops=1)
                          Filter: ((category_name)::text = 'Hospital'::text)
                          Rows Removed by Filter: 11
                    ->  Bitmap Heap Scan on places p  (cost=58.31..1042.72 rows=1356 width=28) (actual time=0.295..1.510 rows=1067 loops=1)
                          Recheck Cond: ((city_id = 1) AND (c.category_id = category_id))
                          Heap Blocks: exact=606
                          ->  Bitmap Index Scan on idx_places_city_cat_rating  (cost=0.00..57.98 rows=1356 width=0) (actual time=0.196..0.196 rows=1135 loops=1)
                                Index Cond: ((city_id = 1) AND (category_id = c.category_id))
              ->  Index Only Scan using idx_nav_dest_started on navigation_sessions n  (cost=0.42..1.00 rows=6 width=12) (actual time=0.002..0.003 rows=5 loops=1067)
                    Index Cond: (dest_place_id = p.place_id)
                    Heap Fetches: 1
Execution Time: 7.239 ms
```

### R07: 18.146 ms → 0.417 ms (44× faster)

`DISTINCT ON` fetched all 5,048 readings of the 40 segments (4,865 heap pages) and sorted them to keep 40. The LATERAL rewrite reads **1 index entry per segment** (`Heap Fetches: 0`), and the segments themselves are found by `idx_segments_city_road` instead of filtering all 2,000.

**Before** (run 3):
```
Unique  (cost=327.07..3885.20 rows=1500 width=48) (actual time=0.457..15.419 rows=40 loops=1)
  ->  Incremental Sort  (cost=327.07..3881.45 rows=1500 width=48) (actual time=0.456..14.996 rows=5048 loops=1)
        Sort Key: t.segment_id, t.recorded_at DESC
        Presorted Key: t.segment_id
        Full-sort Groups: 40  Sort Method: quicksort  Average Memory: 30kB  Peak Memory: 30kB
        Pre-sorted Groups: 40  Sort Method: quicksort  Average Memory: 34kB  Peak Memory: 34kB
        ->  Nested Loop  (cost=5.67..3810.22 rows=1500 width=48) (actual time=0.056..11.132 rows=5048 loops=1)
              ->  Index Scan using road_segments_pkey on road_segments s  (cost=0.28..105.28 rows=12 width=29) (actual time=0.014..0.441 rows=40 loops=1)
                    Filter: (((road_name)::text ~~ 'Outer Ring Road%'::text) AND (city_id = 1))
                    Rows Removed by Filter: 1960
              ->  Bitmap Heap Scan on traffic_readings t  (cost=5.39..307.50 rows=125 width=23) (actual time=0.031..0.243 rows=126 loops=40)
                    Recheck Cond: (segment_id = s.segment_id)
                    Heap Blocks: exact=4865
                    ->  Bitmap Index Scan on uq_traffic_segment_time  (cost=0.00..5.36 rows=125 width=0) (actual time=0.016..0.016 rows=126 loops=40)
                          Index Cond: (segment_id = s.segment_id)
Execution Time: 15.521 ms
```
**After** (run 3):
```
Sort  (cost=30.30..30.33 rows=12 width=48) (actual time=0.324..0.326 rows=40 loops=1)
  Sort Key: s.segment_id
  Sort Method: quicksort  Memory: 28kB
  ->  Nested Loop  (cost=0.70..30.08 rows=12 width=48) (actual time=0.056..0.288 rows=40 loops=1)
        ->  Index Scan using idx_segments_city_road on road_segments s  (cost=0.28..24.33 rows=12 width=29) (actual time=0.019..0.036 rows=40 loops=1)
              Index Cond: ((city_id = 1) AND ((road_name)::text ~>=~ 'Outer Ring Road'::text) AND ((road_name)::text ~<~ 'Outer Ring Roae'::text))
              Filter: ((road_name)::text ~~ 'Outer Ring Road%'::text)
        ->  Limit  (cost=0.42..0.47 rows=1 width=19) (actual time=0.006..0.006 rows=1 loops=40)
              ->  Index Only Scan using idx_traffic_segment_time_speed on traffic_readings tr  (cost=0.42..6.61 rows=125 width=19) (actual time=0.006..0.006 rows=1 loops=40)
                    Index Cond: (segment_id = s.segment_id)
                    Heap Fetches: 0
Execution Time: 0.374 ms
```

### R01: 16.637 ms → 0.964 ms (17× faster)

The Seq Scan read all 40,042 places and threw away 40,026. The partial index jumps straight to open restaurants in the 0.018° latitude band (249 entries); only those rows get the longitude check and the `acos()` distance.

**Before** (run 3):
```
Limit  (cost=1918.41..1918.41 rows=2 width=61) (actual time=17.500..17.506 rows=16 loops=1)
  ->  Sort  (cost=1918.41..1918.41 rows=2 width=61) (actual time=17.497..17.500 rows=16 loops=1)
        Sort Key: (round((('6371'::double precision * acos(LEAST('1'::double precision, ((('0.9746238552210419'::double precision * cos(radians((latitude)::double precision))) * cos((radians((longitude)::double precision) - '1.3548031052143383'::double precision))) + ('0.2238489241298101'::double precision * sin(radians((latitude)::double precision))))))))::numeric, 3))
        Sort Method: quicksort  Memory: 26kB
        ->  Seq Scan on places  (cost=0.00..1918.40 rows=2 width=61) (actual time=0.271..17.425 rows=16 loops=1)
              Filter: ((NOT is_permanently_closed) AND (latitude >= 12.9262) AND (latitude <= 12.9442) AND (longitude >= 77.6152) AND (longitude <= 77.6338) AND (category_id = 1))
              Rows Removed by Filter: 40026
Execution Time: 17.695 ms
```
**After** (run 3):
```
Limit  (cost=490.31..490.31 rows=2 width=61) (actual time=0.903..0.908 rows=16 loops=1)
  ->  Sort  (cost=490.31..490.31 rows=2 width=61) (actual time=0.902..0.903 rows=16 loops=1)
        Sort Key: (round((('6371'::double precision * acos(LEAST('1'::double precision, ((('0.9746238552210419'::double precision * cos(radians((latitude)::double precision))) * cos((radians((longitude)::double precision) - '1.3548031052143383'::double precision))) + ('0.2238489241298101'::double precision * sin(radians((latitude)::double precision))))))))::numeric, 3))
        Sort Method: quicksort  Memory: 26kB
        ->  Bitmap Heap Scan on places  (cost=10.85..490.30 rows=2 width=61) (actual time=0.191..0.863 rows=16 loops=1)
              Recheck Cond: ((category_id = 1) AND (latitude >= 12.9262) AND (latitude <= 12.9442) AND (NOT is_permanently_closed))
              Filter: ((longitude >= 77.6152) AND (longitude <= 77.6338))
              Rows Removed by Filter: 205
              Heap Blocks: exact=212
              ->  Bitmap Index Scan on idx_places_open_cat_lat  (cost=0.00..10.85 rows=195 width=0) (actual time=0.113..0.113 rows=249 loops=1)
                    Index Cond: ((category_id = 1) AND (latitude >= 12.9262) AND (latitude <= 12.9442))
Execution Time: 1.012 ms
```

### R04: 27.037 ms → 1.867 ms (14× faster)

Before: Seq Scan of all 252k opening_hours + Seq Scan of places + hash join + sort. After: walk Bengaluru restaurants **already in rating order** from `idx_places_city_cat_rating`, probe `pk_opening_hours` for Saturday, and **stop after 30 matches** (192 places visited).

**Before** (run 3):
```
Limit  (cost=8391.51..8394.96 rows=30 width=45) (actual time=20.684..23.877 rows=30 loops=1)
  ->  Gather Merge  (cost=8391.51..8441.30 rows=433 width=45) (actual time=20.681..23.871 rows=30 loops=1)
        Workers Planned: 1
        Workers Launched: 1
        ->  Sort  (cost=7391.50..7392.58 rows=433 width=45) (actual time=18.182..18.186 rows=26 loops=2)
              Sort Key: p.avg_rating DESC NULLS LAST
              Sort Method: top-N heapsort  Memory: 29kB
              Worker 0:  Sort Method: top-N heapsort  Memory: 28kB
              ->  Hash Join  (cost=1628.05..7378.71 rows=433 width=45) (actual time=8.236..18.031 rows=132 loops=2)
                    Hash Cond: (h.place_id = p.place_id)
                    ->  Parallel Seq Scan on opening_hours h  (cost=0.00..5728.77 rows=8339 width=20) (actual time=0.016..8.892 rows=6669 loops=2)
                          Filter: ((weekday = 6) AND (((opens < closes) AND ('23:30:00'::time without time zone >= opens) AND ('23:30:00'::time without time zone <= closes)) OR ((opens > closes) AND (('23:30:00'::time without time zone >= opens) OR ('23:30:00'::time without time zone < closes)))))
                          Rows Removed by Filter: 119464
                    ->  Hash  (cost=1600.53..1600.53 rows=2201 width=29) (actual time=8.079..8.080 rows=2121 loops=2)
                          Buckets: 4096  Batches: 1  Memory Usage: 157kB
                          ->  Seq Scan on places p  (cost=0.00..1600.53 rows=2201 width=29) (actual time=0.013..7.422 rows=2121 loops=2)
                                Filter: ((NOT is_permanently_closed) AND (city_id = 1) AND (category_id = 1))
                                Rows Removed by Filter: 37921
Execution Time: 24.009 ms
```
**After** (run 3):
```
Limit  (cost=0.83..513.93 rows=30 width=45) (actual time=0.072..1.711 rows=30 loops=1)
  ->  Nested Loop  (cost=0.83..12794.05 rows=748 width=45) (actual time=0.071..1.707 rows=30 loops=1)
        ->  Index Scan using idx_places_city_cat_rating on places p  (cost=0.41..3765.86 rows=2207 width=29) (actual time=0.029..0.496 rows=192 loops=1)
              Index Cond: ((city_id = 1) AND (category_id = 1))
              Filter: (NOT is_permanently_closed)
              Rows Removed by Filter: 9
        ->  Index Scan using pk_opening_hours on opening_hours h  (cost=0.42..4.09 rows=1 width=20) (actual time=0.006..0.006 rows=0 loops=192)
              Index Cond: ((place_id = p.place_id) AND (weekday = 6))
              Filter: (((opens < closes) AND ('23:30:00'::time without time zone >= opens) AND ('23:30:00'::time without time zone <= closes)) OR ((opens > closes) AND (('23:30:00'::time without time zone >= opens) OR ('23:30:00'::time without time zone < closes))))
              Rows Removed by Filter: 1
Execution Time: 1.757 ms
```

### R10: 2.447 ms → 0.235 ms (10× faster)

`date(reported_at) = '2026-06-30'` hides the column inside a function, so the 12,000 incidents were scanned and 11,979 removed. The range rewrite turns it into an `Index Cond` on `idx_incidents_reported` (21 rows read).

**Before** (run 3):
```
Sort  (cost=351.74..351.75 rows=6 width=58) (actual time=2.100..2.103 rows=2 loops=1)
  Sort Key: i.reported_at DESC
  Sort Method: quicksort  Memory: 25kB
  ->  Hash Join  (cost=57.50..351.66 rows=6 width=58) (actual time=2.068..2.075 rows=2 loops=1)
        Hash Cond: (i.segment_id = s.segment_id)
        ->  Seq Scan on incident_reports i  (cost=0.00..294.00 rows=60 width=37) (actual time=1.820..1.826 rows=21 loops=1)
              Filter: (date(reported_at) = '2026-06-30'::date)
              Rows Removed by Filter: 11979
        ->  Hash  (cost=55.00..55.00 rows=200 width=29) (actual time=0.207..0.207 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 21kB
              ->  Seq Scan on road_segments s  (cost=0.00..55.00 rows=200 width=29) (actual time=0.008..0.164 rows=200 loops=1)
                    Filter: (city_id = 1)
                    Rows Removed by Filter: 1800
Execution Time: 2.162 ms
```
**After** (run 3):
```
Sort  (cost=49.62..49.63 rows=2 width=58) (actual time=0.135..0.136 rows=2 loops=1)
  Sort Key: i.reported_at DESC
  Sort Method: quicksort  Memory: 25kB
  ->  Hash Join  (cost=41.11..49.61 rows=2 width=58) (actual time=0.110..0.114 rows=2 loops=1)
        Hash Cond: (i.segment_id = s.segment_id)
        ->  Index Scan using idx_incidents_reported on incident_reports i  (cost=0.29..8.72 rows=22 width=37) (actual time=0.010..0.012 rows=21 loops=1)
              Index Cond: ((reported_at >= '2026-06-30 00:00:00+05:30'::timestamp with time zone) AND (reported_at < '2026-07-01 00:00:00+05:30'::timestamp with time zone))
        ->  Hash  (cost=38.33..38.33 rows=200 width=29) (actual time=0.082..0.082 rows=200 loops=1)
              Buckets: 1024  Batches: 1  Memory Usage: 21kB
              ->  Bitmap Heap Scan on road_segments s  (cost=5.83..38.33 rows=200 width=29) (actual time=0.027..0.045 rows=200 loops=1)
                    Recheck Cond: (city_id = 1)
                    Heap Blocks: exact=3
                    ->  Bitmap Index Scan on idx_segments_city_road  (cost=0.00..5.78 rows=200 width=0) (actual time=0.016..0.016 rows=200 loops=1)
                          Index Cond: (city_id = 1)
Execution Time: 0.192 ms
```


## Proof that results are unchanged

Every original query from `queries/workload_30.sql` (on the database without indexes) and every query from `sql/06_optimized_queries.sql` (on the database with indexes) was run and compared on the **row count**, an **md5 of the output in the returned order**, and an **md5 of the sorted output** (= the same set of rows). For writes we compared the number of rows inserted/updated/deleted (inside `ROLLBACK`).

| Result | Queries |
|---|---|
| Identical output, same order (md5 equal) | R01, R02, R03, R05, R06, R07, R08, R09, R10, R11, R15, R18, R20, R21, R22, R23, R24, R25, W01–W05 |
| Same rows, only tied rows in a different order | R14, R16, R19 |
| Different tied rows chosen at the `LIMIT` cut-off | R04, R12, R17 |
| Intentionally different (bug fix) | R13 |

The six tie cases are not changes in the answer. They are cases where the original query does not specify a unique order:

| Query | ORDER BY | Why the rows can differ |
|---|---|---|
| R04 | `avg_rating DESC` LIMIT 30 | **34** qualifying restaurants have rating 5.0. Any 30 of them is a correct answer; both versions return 30 rows, all rated 5.0. |
| R12 | `navigations DESC` LIMIT 10 | 1 place has 5 navigations, then **20 places are tied at 2** for the remaining 9 slots. |
| R17 | `avg_reroutes DESC` LIMIT 20 | The 20th place falls inside a group of **23 destinations tied at 2.40**; 17 rows are above it and identical. |
| R14 | `reviews DESC, photos DESC` | Same 20 users; users with equal reviews *and* photos swap places. |
| R16 | `navigations_2026 DESC` | Same 895 rows; equal counts come out in a different order. |
| R19 | `navigations DESC` | Same 1,067 rows. We added `p.place_id` as a final tie-breaker so the new version is deterministic. |

Tie counts were checked with, for example (R04):

```sql
SELECT p.avg_rating, count(*)
FROM places p JOIN opening_hours h ON h.place_id = p.place_id AND h.weekday = 6
WHERE p.city_id = 1 AND p.category_id = 1 AND NOT p.is_permanently_closed
  AND ((h.opens < h.closes AND TIME '23:30' BETWEEN h.opens AND h.closes)
    OR (h.opens > h.closes AND (TIME '23:30' >= h.opens OR TIME '23:30' < h.closes)))
GROUP BY 1 ORDER BY 1 DESC NULLS LAST LIMIT 3;
--  5.0 | 34      4.8 | 1      4.7 | 6
```

**Why each rewrite is equivalent**

* **R07** `DISTINCT ON (segment_id) … ORDER BY segment_id, recorded_at DESC` keeps the newest reading per segment. `LATERAL (… ORDER BY recorded_at DESC LIMIT 1)` picks the same row; `(segment_id, recorded_at)` is UNIQUE, so there is no tie. The inner join / `CROSS JOIN LATERAL` both drop segments without readings.
* **R10, R11, R20** `DATE(x) = d`, `EXTRACT(YEAR FROM x) = y` and `x::date BETWEEN a AND b` are evaluated in the session time zone. The literals `'2026-06-30'`, `'2026-01-01'` … in the range version are also read in the session time zone, so `x >= d AND x < d + 1` selects exactly the same rows — and does it on the bare column, so an index can be used ("sargable").
* **R14** `users.user_id` is the PK, so grouping by `u.user_id, u.display_name, u.guide_level` is the same as grouping by `r.user_id`; `place_reviews.user_id` is a NOT NULL FK, so the inner join drops no review. Aggregating first and joining the 20 winners gives the same rows.
* **R19** The scalar subqueries return `count = 0`, `max = NULL` for a hospital nobody navigated to. `LEFT JOIN` + `count(n.dest_place_id)` (counts non-NULL only) + `max(n.started_at)` give exactly that. If "Hospital" did not exist, the scalar subquery would return NULL and match nothing; the inner join to `place_categories` also returns nothing.

## Write overhead

Every new index must be updated on INSERT/UPDATE/DELETE.

| Query | Before (ms) | After (ms) | Change | Indexes it now has to maintain | Acceptable? |
|---|---:|---:|---:|---|---|
| W01 | 1.175 | 1.326 | +12.9% | PK + 6 new on navigation_sessions | Yes — still ~1 ms |
| W02 | 1.211 | 1.697 | +40.1% | PK + UNIQUE + 3 new on place_reviews | Yes — still < 2 ms |
| W03 | 1.345 | 1.102 | -18.1% | PK only (no new index) | Yes |
| W04 | 148.189 | 132.180 | -10.8% | 4 new on places (+ PK, UNIQUE) | Yes |
| W05 | 5.380 | 6.020 | +11.9% | PK + 2 new on incident_reports | Yes — nightly batch job |

* **W01 / W02** got slower by a fraction of a millisecond. `navigation_sessions` has 6 new indexes and `place_reviews` 3. They stay far under the 5 ms target for real-time writes, so this is acceptable — and the reads they enable (R11–R20, R05, R14, R15, R22) are used far more often than one row is inserted.
* **W05** deletes 11,339 of 12,000 incident reports, so it has to remove 11,339 entries from each of the 2 new indexes as well. It is a nightly housekeeping job; ~1 ms extra is irrelevant. `idx_incidents_expires` does not help this particular run (95 % of rows match, so a Seq Scan is correct), but it does help when the job runs every day and only a few rows expire.
* **W03** has no new index on `saved_places`; the difference is noise.
* **W04** updates only the 558 places whose stored values are stale, so the extra index maintenance on `places` is small; the time is dominated by aggregating all reviews. The difference is noise.

## Index storage

Sizes from `pg_relation_size` on the seed data, after `VACUUM ANALYZE`:

| Index | Table | Index size | Table size | Index / table |
|---|---|---:|---:|---:|
| `idx_incidents_reported` | incident_reports | 384 kB | 912 kB | 42.1 % |
| `idx_incidents_expires` | incident_reports | 280 kB | 912 kB | 30.7 % |
| `idx_nav_started_cover` | navigation_sessions | 12 MB | 23 MB | 51.7 % |
| `idx_nav_dest_started` | navigation_sessions | 6184 kB | 23 MB | 26.6 % |
| `idx_nav_dest_reroutes` | navigation_sessions | 3144 kB | 23 MB | 13.5 % |
| `idx_nav_mode_status` | navigation_sessions | 1416 kB | 23 MB | 6.1 % |
| `idx_nav_origin` | navigation_sessions | 176 kB | 23 MB | 0.8 % |
| `idx_reviews_created_cover` | place_reviews | 3584 kB | 6208 kB | 57.7 % |
| `idx_reviews_place_created` | place_reviews | 2792 kB | 6208 kB | 45.0 % |
| `idx_reviews_place_rating` | place_reviews | 2000 kB | 6208 kB | 32.2 % |
| `idx_places_open_cat_lat` | places | 3928 kB | 7632 kB | 51.5 % |
| `idx_places_name_trgm` | places | 3440 kB | 7632 kB | 45.1 % |
| `idx_places_city_cat_rating` | places | 3016 kB | 7632 kB | 39.5 % |
| `idx_places_closed` | places | 72 kB | 7632 kB | 0.9 % |
| `idx_segments_city_road` | road_segments | 56 kB | 240 kB | 23.3 % |
| `idx_traffic_segment_time_speed` | traffic_readings | 12 MB | 14 MB | 82.5 % |
| `idx_traffic_heavy_time` | traffic_readings | 1448 kB | 14 MB | 9.8 % |
| **All 17 new indexes** | | **55 MB** | all tables 70 MB | 79 % |

Database size: **117 MB before → 171 MB after**.

The two big ones are justified but worth watching at 20×:

* `idx_traffic_segment_time_speed` (82 % of its table) duplicates the key of the existing UNIQUE `(segment_id, recorded_at)` index and adds the payload columns. It is what makes R07 and R09 Index Only Scans. The UNIQUE constraint index cannot be dropped, so we pay twice.
* `idx_nav_started_cover` (52 %) carries 5 INCLUDE columns so R11, R12, R16 and R20 never touch the heap.

## Queries we could not speed up (much)

* **R21 places with no opening hours** — an anti-join has to know, for every place, whether *any* of its ~6 opening-hours rows exists. PostgreSQL reads all 252k rows of `opening_hours` into a hash and does it in one pass; this is already the cheapest plan on PostgreSQL 16, which has no B-tree "skip scan" to jump from one place_id to the next in `pk_opening_hours`. (PostgreSQL 18, on the team laptop, added skip scan, so R21 may improve there with the existing PK index.) Same plan before and after (Hash Right Anti Join over two Seq Scans); the time difference is machine noise. Re-running it 6 more times on each database gave 59–213 ms before and 56–109 ms after with the identical plan.
* **R25 road safety** — the share of readings over the limit needs **every one** of the 250,000 readings. A Seq Scan + hash join with the 2,000 segments is the right plan. For CP4 the honest option is a summary table refreshed every hour.
* **R18 cancelled share per mode** — also needs every row. The narrow index lets it read 1.4 MB instead of 23 MB of heap, but counting 200k rows still costs the same.
* **R11, R17** — got faster (Index Only Scans, GroupAggregate instead of HashAggregate) but still read 1/3 of / the whole `navigation_sessions` table. At 20× they will grow ~20×; a monthly / per-destination summary table is the next step for CP4.
* **R24 duplicates** — the inner side looks up places by name; the Hash Join over one Seq Scan of 40k places is what the planner prefers and is already ~10 ms. An index on `(name, latitude)` was tried, but the planner still preferred the Hash Join (forcing the index only saved ~2 ms), so we did not keep it: it would only add write overhead.
* **R02, R06, R23** — were already primary-key / unique-key lookups (< 0.2 ms). Nothing to do.
* **W04** — must aggregate every review to know which places are stale.

## How to reproduce

```bash
createdb gmaps_base   && psql -d gmaps_base -f sql/01_schema.sql && psql -d gmaps_base -f sql/02_load_data.sql
createdb -T gmaps_base gmaps_opt && psql -d gmaps_opt -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh gmaps_opt optimized 3 sql/06_optimized_queries.sql
```
