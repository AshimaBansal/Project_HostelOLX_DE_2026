-- Phase 4: Range partitioning for navigation sessions
-- Partition the table by started_at to improve date-based query performance.

CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_partitioned (
    session_id INTEGER NOT NULL,
    user_id INTEGER,
    origin_place_id INTEGER,
    origin_lat NUMERIC(9,6) NOT NULL,
    origin_lng NUMERIC(9,6) NOT NULL,
    dest_place_id INTEGER NOT NULL,
    travel_mode VARCHAR(20) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    distance_km NUMERIC(6,2) NOT NULL,
    eta_minutes INTEGER NOT NULL,
    actual_minutes INTEGER,
    rerouted_count SMALLINT NOT NULL DEFAULT 0,
    status VARCHAR(20)
)
PARTITION BY RANGE (started_at);

-- Create yearly partitions
CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_p2023
PARTITION OF gmaps.navigation_sessions_partitioned
FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');

CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_p2024
PARTITION OF gmaps.navigation_sessions_partitioned
FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_p2025
PARTITION OF gmaps.navigation_sessions_partitioned
FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');

CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_p2026
PARTITION OF gmaps.navigation_sessions_partitioned
FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- Catch dates outside the predefined range
CREATE TABLE IF NOT EXISTS gmaps.navigation_sessions_default
PARTITION OF gmaps.navigation_sessions_partitioned DEFAULT;

TRUNCATE TABLE gmaps.navigation_sessions_partitioned;

-- Copy data from the original table
INSERT INTO gmaps.navigation_sessions_partitioned (
    session_id,
    user_id,
    origin_place_id,
    origin_lat,
    origin_lng,
    dest_place_id,
    travel_mode,
    started_at,
    distance_km,
    eta_minutes,
    actual_minutes,
    rerouted_count,
    status
)
SELECT
    session_id,
    user_id,
    origin_place_id,
    origin_lat,
    origin_lng,
    dest_place_id,
    travel_mode,
    started_at,
    distance_km,
    eta_minutes,
    actual_minutes,
    rerouted_count,
    status
FROM gmaps.navigation_sessions;

-- Indexes for partitioned queries
CREATE INDEX IF NOT EXISTS idx_partitioned_started_at
ON gmaps.navigation_sessions_partitioned (started_at);

CREATE INDEX IF NOT EXISTS idx_partitioned_dest_started
ON gmaps.navigation_sessions_partitioned (dest_place_id, started_at);

CREATE INDEX IF NOT EXISTS idx_partitioned_mode_status
ON gmaps.navigation_sessions_partitioned (travel_mode, status);

ANALYZE gmaps.navigation_sessions_partitioned;
