-- =====================================================================
-- Google Maps DBMS Project · Phase 4 (CP3): indexes
-- Run after 01_schema.sql + 02_load_data.sql:
--     psql -d <db> -f sql/05_indexes.sql
--
-- Every index says which queries it serves and why this type / column order.
-- Rules followed: equality columns first, then range/sort columns;
-- INCLUDE (...) when it lets the query become an Index Only Scan;
-- partial indexes when a query only ever wants a small, fixed slice.
--
-- Indexes that already exist from Phase 2 (PK / UNIQUE) and are reused:
--   places_pkey, places_plus_code_key (R23), pk_opening_hours (R02, R04, R21),
--   uq_reviews_place_user, pk_saved_places (R06), uq_traffic_segment_time (R07),
--   users_pkey, road_segments_pkey.
-- =====================================================================
SET search_path TO gmaps;

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- trigram GIN for ILIKE '%...%' (R03)

-- ---------------------------------------------------------------------
-- PLACES
-- ---------------------------------------------------------------------

-- R01 "near me": category_id is an equality filter, latitude is the bounding-box range.
-- Partial on NOT is_permanently_closed because the query never wants closed places.
-- INCLUDE longitude/name/avg_rating so the box is checked and the row returned
-- without touching the heap (Index Only Scan).
CREATE INDEX idx_places_open_cat_lat
    ON places (category_id, latitude)
    INCLUDE (longitude, name, avg_rating)
    WHERE NOT is_permanently_closed;

-- R03 search: '%biryani%' has a leading wildcard, so a B-tree can never help.
-- A trigram GIN index finds the few names that contain the trigrams of "biryani".
CREATE INDEX idx_places_name_trgm
    ON places USING gin (name gin_trgm_ops);

-- R04 "open now", R19 hospitals, R24 duplicates, R03, R12: all filter places on
-- city_id = ? AND category_id = ? (two equalities, most selective pair first).
-- avg_rating DESC last so R04's ORDER BY avg_rating DESC NULLS LAST can be read in order.
CREATE INDEX idx_places_city_cat_rating
    ON places (city_id, category_id, avg_rating DESC NULLS LAST)
    INCLUDE (name, is_permanently_closed);

-- R16: only ~1–2 % of places are permanently closed; a tiny partial index lists them.
CREATE INDEX idx_places_closed
    ON places (place_id)
    INCLUDE (name)
    WHERE is_permanently_closed;

-- ---------------------------------------------------------------------
-- PLACE_REVIEWS
-- ---------------------------------------------------------------------

-- R05 newest reviews of one place: place_id (equality) then created_at DESC (sort),
-- so "ORDER BY created_at DESC LIMIT 10" reads exactly 10 index entries.
CREATE INDEX idx_reviews_place_created
    ON place_reviews (place_id, created_at DESC);

-- R15, W04: both aggregate avg(rating)/count(*) per place over ALL reviews.
-- (place_id) INCLUDE (rating) gives an Index Only Scan already sorted by place_id,
-- so the aggregate becomes a streaming GroupAggregate / Merge Join with places.
CREATE INDEX idx_reviews_place_rating
    ON place_reviews (place_id)
    INCLUDE (rating);

-- R14 leaderboard (created_at >= 2026-01-01) and R22 moderation (ORDER BY created_at DESC OFFSET):
-- created_at is the range / sort key. INCLUDE the columns both queries return so
-- both become Index Only Scans (R22 still has to step over 50,000 entries, but in
-- a narrow index instead of sorting the whole table).
CREATE INDEX idx_reviews_created_cover
    ON place_reviews (created_at DESC)
    INCLUDE (review_id, place_id, user_id, rating, photo_count);

-- ---------------------------------------------------------------------
-- ROAD_SEGMENTS / TRAFFIC_READINGS / INCIDENT_REPORTS
-- ---------------------------------------------------------------------

-- R07: city_id = 1 AND road_name LIKE 'Outer Ring Road%'.
-- text_pattern_ops lets B-tree answer a left-anchored LIKE prefix in any collation.
CREATE INDEX idx_segments_city_road
    ON road_segments (city_id, road_name text_pattern_ops);

-- R09 typical-traffic chart and R25 road safety: per-segment reads of avg_speed_kmph.
-- (segment_id, recorded_at) is the existing unique key; INCLUDE avg_speed_kmph so the
-- chart is an Index Only Scan. Also gives R07's LATERAL "latest reading" a backward scan.
CREATE INDEX idx_traffic_segment_time_speed
    ON traffic_readings (segment_id, recorded_at DESC)
    INCLUDE (avg_speed_kmph, congestion_level);

-- R08 alerts: only HEAVY/STANDSTILL rows are ever wanted (≈12 % of rows) and always
-- "since <time>". Partial index on recorded_at keeps it small and range-scannable.
CREATE INDEX idx_traffic_heavy_time
    ON traffic_readings (recorded_at DESC)
    INCLUDE (segment_id, avg_speed_kmph, congestion_level)
    WHERE congestion_level IN ('HEAVY', 'STANDSTILL');

-- R10 incident layer (after the sargable rewrite, reported_at is a plain range).
CREATE INDEX idx_incidents_reported
    ON incident_reports (reported_at DESC)
    INCLUDE (segment_id);

-- W05 housekeeping: DELETE ... WHERE expires_at < '2026-06-01'.
CREATE INDEX idx_incidents_expires
    ON incident_reports (expires_at);

-- ---------------------------------------------------------------------
-- NAVIGATION_SESSIONS (200k rows now, 4M at 20× — the table that matters most)
-- ---------------------------------------------------------------------

-- R19 hospital health, R16 closed places, R12 trends: dest_place_id (equality / join key)
-- then started_at (range, max()). R19's count(*) and max(started_at) per hospital are
-- read straight from this index (Index Only Scan, one small range per hospital).
CREATE INDEX idx_nav_dest_started
    ON navigation_sessions (dest_place_id, started_at);

-- R17 reroute ranking: GROUP BY dest_place_id over the WHOLE table. A narrow index already
-- sorted by dest_place_id turns HashAggregate (~39k groups) into a streaming GroupAggregate
-- over an Index Only Scan. Kept separate from idx_nav_dest_started on purpose: with
-- started_at in the index it is ~50 % bigger and the planner went back to Seq Scan + HashAggregate.
CREATE INDEX idx_nav_dest_reroutes
    ON navigation_sessions (dest_place_id, rerouted_count);

-- R12 (last 7 days), R20 (June), R11 (2026): time-range scans.
-- INCLUDE what those queries read, so they stay Index Only Scans.
CREATE INDEX idx_nav_started_cover
    ON navigation_sessions (started_at)
    INCLUDE (dest_place_id, travel_mode, status, eta_minutes, actual_minutes);

-- R13 (fixed with NOT EXISTS): anti-join probe "is this place ever an origin?".
-- Partial: 96 % of sessions have NULL origin (started from GPS); they can never match.
CREATE INDEX idx_nav_origin
    ON navigation_sessions (origin_place_id)
    WHERE origin_place_id IS NOT NULL;

-- R18 cancelled share per mode: needs every row, but only 2 short columns.
-- Index Only Scan over a narrow index instead of the wide heap.
CREATE INDEX idx_nav_mode_status
    ON navigation_sessions (travel_mode, status);

-- Fresh statistics + visibility map (needed for Index Only Scans).
VACUUM ANALYZE;
