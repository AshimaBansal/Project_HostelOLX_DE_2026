# Baseline Query Timings

## 1. Benchmark Setup

The baseline benchmark was executed on the `gmaps_project` PostgreSQL database using the provided workload file `queries/workload_30.sql`.

- Total queries: 30
- Read queries: 25 (R01–R25)
- Write queries: 5 (W01–W05)
- Runs per query: 3
- Measurement: `EXPLAIN (ANALYZE, BUFFERS)`
- Reported timing: Average execution time across three runs
- Write queries: Executed inside transactions and rolled back after measurement.

The benchmark was run using:

```bash
./benchmarks/run_benchmark.sh gmaps_project baseline
```

All 30 queries completed successfully. The raw execution plans for all three runs and the summary CSV are stored in `benchmarks/results/baseline/`.

## 2. Baseline Timing Results

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: "Restaurants near me": open restaurants within ~1 km of Koramangala (12.9352, 77.6245), nearest first | READ | 7.048 | 5.703 | 5.067 | 5.939 |
| R02: Place page: details of place 18 with Tuesday's opening hours | READ | 0.054 | 0.054 | 0.053 | 0.054 |
| R03: Search: Bengaluru places with "biryani" in the name, best rated first | READ | 15.910 | 13.588 | 13.260 | 14.253 |
| R04: "Open now" filter: Bengaluru restaurants open at 23:30 on a Saturday (some close after midnight) | READ | 9.652 | 8.284 | 8.441 | 8.792 |
| R05: Place page: the 10 newest reviews of place 18 | READ | 0.155 | 0.134 | 0.136 | 0.142 |
| R06: "Saved" tab: user 1005's saved places grouped by list | READ | 0.471 | 0.059 | 0.062 | 0.197 |
| R07: Live traffic layer: the latest reading of every Outer Ring Road segment in Bengaluru | READ | 3.546 | 3.413 | 3.534 | 3.498 |
| R08: Traffic alerts: Bengaluru segments with heavy traffic or standstill since 18:00 on 30 June 2026 | READ | 0.371 | 0.359 | 0.366 | 0.365 |
| R09: "Typical traffic" chart: average speed by hour of the day on segment 5 | READ | 0.664 | 0.236 | 0.229 | 0.376 |
| R10: Incident layer: incidents reported in Bengaluru on 30 June 2026 | READ | 0.886 | 0.837 | 0.787 | 0.837 |
| R11: ETA quality: average error (actual − ETA, minutes) per travel mode per month in 2026 | READ | 25.492 | 24.523 | 23.287 | 24.434 |
| R12: Trends: 10 most-navigated-to places in Mumbai in the last 7 days of June 2026 | READ | 10.506 | 10.200 | 10.032 | 10.246 |
| R13: Data team: places that have never been the starting point of a navigation | READ | 19.713 | 19.654 | 19.282 | 19.550 |
| R14: Local Guides leaderboard: users with the most reviews in 2026 (photos as tie-breaker) | READ | 8.496 | 8.675 | 8.468 | 8.546 |
| R15: Data quality: places whose stored rating or review count no longer matches their reviews | READ | 27.511 | 26.841 | 27.130 | 27.161 |
| R16: Data quality: permanently closed places that people still navigate to (2026) | READ | 12.968 | 12.680 | 12.610 | 12.753 |
| R17: Routing team: destinations with the most re-routing on average (at least 5 trips) | READ | 30.110 | 31.657 | 31.169 | 30.979 |
| R18: Product analytics: share of cancelled navigations per travel mode | READ | 13.697 | 35.516 | 14.189 | 21.134 |
| R19: Health report: every Bengaluru hospital with its number of navigations and the most recent one | READ | 13975.193 | 14083.168 | 13516.097 | 13858.153 |
| R20: Product analytics: navigations per day and running total for June 2026 | READ | 9.977 | 9.796 | 9.740 | 9.838 |
| R21: Data team: places with no opening hours, counted per category | READ | 21.265 | 23.989 | 24.253 | 23.169 |
| R22: Moderation console: all reviews, newest first, page 2,001 (25 per page) | READ | 16.827 | 17.630 | 16.268 | 16.908 |
| R23: Plus Code search: open the place with this code | READ | 0.022 | 0.022 | 0.023 | 0.022 |
| R24: Duplicate listings: Bengaluru restaurants with the same name within ~100 m of each other | READ | 4.805 | 5.007 | 5.057 | 4.956 |
| R25: Road safety: share of readings above the speed limit, per road type | READ | 28.642 | 29.580 | 27.206 | 28.476 |
| W01: "Start": begin navigation from current location to place 18 | WRITE | 0.737 | 0.489 | 0.469 | 0.565 |
| W02: Write a review: user 1005 rates place 18 | WRITE | 0.481 | 0.412 | 0.408 | 0.434 |
| W03: "Save": user 1005 adds place 18 to "Want to go" | WRITE | 0.491 | 0.478 | 0.433 | 0.467 |
| W04: Nightly job: recompute every place's rating and review count | WRITE | 37.809 | 30.364 | 30.263 | 32.812 |
| W05: Housekeeping: delete incident reports that expired before June 2026 | WRITE | 2.398 | 2.080 | 2.095 | 2.191 |
| **Total (sum of all 30)** | | | | | **14167.246** |

## 3. Scan Types and Query Observations

The scan types below are taken from the benchmark summary. The observations describe the baseline execution behaviour and identify possible areas for optimization.

| Query | Scan type | Observation |
|---|---|---|
| R01 | Seq Scan on places | Scans the places table to filter nearby restaurants and calculate distance. |
| R02 | Index Scan on places and opening_hours | Primary-key and composite-key lookups make this query very fast. |
| R03 | Seq Scan on places | Searches place names using a text pattern and sorts matching results. |
| R04 | Seq Scan on opening_hours and places | Scans both tables to evaluate opening hours and restaurant filters. |
| R05 | Bitmap Heap Scan and Bitmap Index Scan on place_reviews; Index Scan on users | Uses an existing unique index to locate reviews, keeping execution fast. |
| R06 | Index Scan on saved_places and places | Existing primary-key indexes support the saved-place lookups efficiently. |
| R07 | Index Scan on road_segments; Bitmap Heap Scan and Bitmap Index Scan on traffic_readings | Uses indexes for segment and traffic lookups, but execution time varies between runs. |
| R08 | Seq Scan on road_segments; Index Scan on traffic_readings | The segment scan is relatively small, while the traffic lookup uses an existing index. |
| R09 | Bitmap Heap Scan and Bitmap Index Scan on traffic_readings | Uses the existing traffic index and completes quickly. |
| R10 | Seq Scan on incident_reports and road_segments | Scans both tables to filter incidents and their associated road segments. |
| R11 | Seq Scan on navigation_sessions | Processes navigation records to calculate ETA error grouped by month and travel mode. |
| R12 | Seq Scan on navigation_sessions and places | Scans navigation sessions and places to identify the most frequently visited destinations. |
| R13 | Seq Scan on places and navigation_sessions | Scans both tables to identify places without matching navigation origins. |
| R14 | Seq Scan on place_reviews and users | Processes review and user records to calculate the leaderboard. |
| R15 | Seq Scan on place_reviews and places | Compares stored place statistics with aggregated review data. |
| R16 | Seq Scan on navigation_sessions and places | Scans navigation and place records to identify destinations that are permanently closed. |
| R17 | Seq Scan on navigation_sessions | Processes navigation records to calculate average rerouting by destination. |
| R18 | Seq Scan on navigation_sessions | Processes navigation records to calculate cancellation percentages by travel mode. |
| R19 | Seq Scan on place_categories, places and navigation_sessions | The multi-table scan and aggregation over navigation records make this the slowest read query. |
| R20 | Seq Scan on navigation_sessions | Processes navigation records by date and calculates a running total. |
| R21 | Seq Scan on opening_hours, places and place_categories | Scans related tables to find places without opening-hour records and group them by category. |
| R22 | Seq Scan on place_reviews | Scans review records and handles a deep OFFSET-based page request. |
| R23 | Index Scan on places | The unique Plus Code index supports a very fast direct lookup. |
| R24 | Seq Scan on places | Searches restaurant listings for matching names and nearby duplicates. |
| R25 | Seq Scan on traffic_readings and road_segments | Scans traffic and road data to calculate the share of readings above speed limits. |
| W01 | No scan | A simple insert completes quickly. |
| W02 | No scan | A review insert with conflict handling completes quickly. |
| W03 | No scan | A saved-place insert completes quickly. |
| W04 | Seq Scan on places and place_reviews | Aggregates review data and updates matching place records, making it the slowest write query. |
| W05 | Seq Scan on incident_reports | Scans incident reports to identify expired records for deletion. |

## 4. Baseline Findings

### 4.1 Slowest Queries

R19 is the slowest query in the workload, with an average execution time of **13,858.153 ms**. It scans place categories, places and navigation sessions to generate a hospital navigation report.

Other relatively slow read queries include:

- R17: 30.979 ms
- R25: 28.476 ms
- R15: 27.161 ms
- R11: 24.434 ms
- R21: 23.169 ms
- R18: 21.134 ms
- R13: 19.550 ms

W04 is the slowest write query, with an average execution time of **32.812 ms**, because it aggregates review records and updates place statistics.

### 4.2 Fastest Queries

Queries R23, R02, R05 and R06 have very low execution times. These queries benefit from existing primary-key or unique-constraint indexes.

W01, W02 and W03 also complete in less than 1 ms on average.

### 4.3 Initial Observations

1. Several analytical queries use sequential scans on large tables such as `navigation_sessions`, `places`, `place_reviews` and `traffic_readings`.
2. Queries involving aggregation, joins and filtering over large datasets take longer than direct lookups.
3. Existing primary-key and unique-constraint indexes already help several point-lookup queries.
4. R19 is the most significant read-query bottleneck and should be investigated during optimization.
5. W04 has a higher execution time than the other write queries because it performs aggregation and updates across tables.
6. R07 shows noticeable variation across its three runs, so its execution time should be compared carefully with later measurements.

## 5. Conclusion

The baseline benchmark establishes the initial execution performance of all 30 workload queries on the seed dataset. The results show that direct lookups are generally fast, while queries involving large-table scans, joins and aggregations require more time.

These measurements will be used as the reference for comparing optimized query performance in Phase 4. The workload queries will remain unchanged so that the before-and-after comparison uses the same SQL statements.
