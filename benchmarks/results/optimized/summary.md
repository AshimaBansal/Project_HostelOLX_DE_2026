# CP3 · Optimized benchmark summary

PostgreSQL 16.15 · 30 queries · 3 runs per query (`EXPLAIN (ANALYZE, BUFFERS)`). All timings are in milliseconds. Scan nodes are from the final run.

[Checkpoint report](../../../docs/04_optimization_report.md) · [Source CSV](summary.csv)

## Read queries

| Query | Type | Average (ms) | Median (ms) | Min (ms) | Max (ms) | Scan nodes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| R01 | READ | 0.964 | 0.975 | 0.905 | 1.012 | Bitmap Heap Scan on places \| Bitmap Index Scan on idx_places_open_cat_lat |
| R02 | READ | 0.157 | 0.162 | 0.143 | 0.166 | Index Scan using places_pkey on places \| Index Scan using pk_opening_hours on opening_hours |
| R03 | READ | 7.318 | 7.538 | 5.793 | 8.624 | Bitmap Heap Scan on places \| Bitmap Index Scan on idx_places_city_cat_rating |
| R04 | READ | 1.867 | 1.800 | 1.757 | 2.044 | Index Scan using idx_places_city_cat_rating on places \| Index Scan using pk_opening_hours on opening_hours |
| R05 | READ | 0.385 | 0.307 | 0.302 | 0.547 | Bitmap Heap Scan on place_reviews \| Bitmap Index Scan on uq_reviews_place_user \| Index Scan using users_pkey on users |
| R06 | READ | 0.213 | 0.193 | 0.187 | 0.259 | Index Scan using pk_saved_places on saved_places \| Index Scan using places_pkey on places |
| R07 | READ | 0.417 | 0.396 | 0.374 | 0.482 | Index Scan using idx_segments_city_road on road_segments \| Index Only Scan using idx_traffic_segment_time_speed on traffic_readings |
| R08 | READ | 0.229 | 0.207 | 0.166 | 0.315 | Index Only Scan using idx_traffic_heavy_time on traffic_readings \| Bitmap Heap Scan on road_segments \| Bitmap Index Scan on idx_segments_city_road |
| R09 | READ | 0.232 | 0.232 | 0.230 | 0.233 | Index Only Scan using idx_traffic_segment_time_speed on traffic_readings |
| R10 | READ | 0.235 | 0.229 | 0.192 | 0.285 | Index Scan using idx_incidents_reported on incident_reports \| Bitmap Heap Scan on road_segments \| Bitmap Index Scan on idx_segments_city_road |
| R11 | READ | 41.559 | 41.573 | 39.440 | 43.663 | Index Only Scan using idx_nav_started_cover on navigation_sessions |
| R12 | READ | 6.369 | 7.074 | 4.895 | 7.137 | Index Only Scan using idx_nav_started_cover on navigation_sessions \| Bitmap Heap Scan on places \| Bitmap Index Scan on idx_places_city_cat_rating |
| R13 | READ | 16.805 | 18.896 | 12.201 | 19.318 | Index Scan using places_pkey on places \| Index Only Scan using idx_nav_origin on navigation_sessions |
| R14 | READ | 5.308 | 5.188 | 5.006 | 5.731 | Index Only Scan using idx_reviews_created_cover on place_reviews \| Index Scan using users_pkey on users |
| R15 | READ | 55.847 | 50.142 | 48.768 | 68.631 | Index Scan using places_pkey on places \| Index Only Scan using idx_reviews_place_rating on place_reviews |
| R16 | READ | 5.509 | 5.271 | 5.100 | 6.155 | Index Only Scan using idx_places_closed on places \| Index Only Scan using idx_nav_dest_started on navigation_sessions |
| R17 | READ | 53.951 | 50.443 | 44.986 | 66.425 | Index Only Scan using idx_nav_dest_reroutes on navigation_sessions |
| R18 | READ | 36.702 | 39.274 | 31.064 | 39.768 | Index Only Scan using idx_nav_mode_status on navigation_sessions |
| R19 | READ | 7.222 | 7.239 | 7.071 | 7.355 | Seq Scan on place_categories \| Bitmap Heap Scan on places \| Bitmap Index Scan on idx_places_city_cat_rating \| Index Only Scan using idx_nav_dest_started on navigation_sessions |
| R20 | READ | 4.149 | 4.323 | 3.795 | 4.329 | Index Only Scan using idx_nav_started_cover on navigation_sessions |
| R21 | READ | 82.845 | 85.857 | 74.763 | 87.915 | Seq Scan on opening_hours \| Seq Scan on places \| Seq Scan on place_categories |
| R22 | READ | 9.462 | 10.214 | 7.298 | 10.874 | Index Only Scan using idx_reviews_created_cover on place_reviews |
| R23 | READ | 0.051 | 0.048 | 0.048 | 0.057 | Index Scan using places_plus_code_key on places |
| R24 | READ | 13.704 | 13.708 | 12.882 | 14.523 | Seq Scan on places \| Bitmap Heap Scan on places \| Bitmap Index Scan on idx_places_city_cat_rating |
| R25 | READ | 67.452 | 63.838 | 63.538 | 74.980 | Seq Scan on traffic_readings \| Seq Scan on road_segments |

## Write queries

| Query | Type | Average (ms) | Median (ms) | Min (ms) | Max (ms) | Scan nodes |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| W01 | WRITE | 1.326 | 1.328 | 1.248 | 1.402 | (no scan) |
| W02 | WRITE | 1.697 | 1.472 | 1.213 | 2.407 | (no scan) |
| W03 | WRITE | 1.102 | 1.113 | 1.067 | 1.126 | (no scan) |
| W04 | WRITE | 132.180 | 131.786 | 120.701 | 144.052 | Seq Scan on places \| Seq Scan on place_reviews |
| W05 | WRITE | 6.020 | 5.245 | 4.759 | 8.056 | Seq Scan on incident_reports |
