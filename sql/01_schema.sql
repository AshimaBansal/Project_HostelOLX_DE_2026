
-- ============================================================
-- Google Maps Navigation Database
-- CP1 / Phase 2: Final relational schema
-- PostgreSQL 15+
-- ============================================================

CREATE SCHEMA IF NOT EXISTS gmaps;
SET search_path TO gmaps;

-- 1. CITIES
CREATE TABLE cities (
    city_id       INTEGER PRIMARY KEY,
    city_name     VARCHAR(100) NOT NULL,
    center_lat    NUMERIC(9,6) NOT NULL,
    center_lng    NUMERIC(9,6) NOT NULL,

    CONSTRAINT uq_cities_name UNIQUE (city_name),
    CONSTRAINT chk_cities_lat CHECK (center_lat BETWEEN -90 AND 90),
    CONSTRAINT chk_cities_lng CHECK (center_lng BETWEEN -180 AND 180)
);

-- 2. PLACE CATEGORIES
CREATE TABLE place_categories (
    category_id   INTEGER PRIMARY KEY,
    category_name VARCHAR(80) NOT NULL UNIQUE
);

-- 3. USERS
CREATE TABLE users (
    user_id        INTEGER PRIMARY KEY,
    display_name   VARCHAR(100) NOT NULL,
    email          VARCHAR(254) NOT NULL UNIQUE,
    home_city_id   INTEGER,
    is_local_guide BOOLEAN NOT NULL,
    guide_level    SMALLINT,
    created_at     TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_users_city
        FOREIGN KEY (home_city_id)
        REFERENCES cities(city_id)
        ON DELETE SET NULL,

    CONSTRAINT chk_users_guide_level
        CHECK (
            (is_local_guide = TRUE
            AND guide_level IS NOT NULL
            AND guide_level BETWEEN 1 AND 10)
            OR
            (is_local_guide = FALSE AND guide_level IS NULL)
        )
);

-- 4. PLACES
CREATE TABLE places (
    place_id              INTEGER PRIMARY KEY,
    plus_code             VARCHAR(20) NOT NULL UNIQUE,
    name                  VARCHAR(200) NOT NULL,
    category_id           INTEGER NOT NULL,
    city_id               INTEGER NOT NULL,
    latitude              NUMERIC(9,6) NOT NULL,
    longitude             NUMERIC(9,6) NOT NULL,
    address               TEXT NOT NULL,
    phone                 VARCHAR(30),
    website               TEXT,
    price_level           SMALLINT,
    avg_rating            NUMERIC(2,1),
    review_count          INTEGER NOT NULL,
    is_permanently_closed BOOLEAN NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_places_category
        FOREIGN KEY (category_id)
        REFERENCES place_categories(category_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_places_city
        FOREIGN KEY (city_id)
        REFERENCES cities(city_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_places_lat
        CHECK (latitude BETWEEN -90 AND 90),

    CONSTRAINT chk_places_lng
        CHECK (longitude BETWEEN -180 AND 180),

    CONSTRAINT chk_places_price
        CHECK (price_level IS NULL OR price_level BETWEEN 1 AND 4),

    CONSTRAINT chk_places_rating
        CHECK (avg_rating IS NULL OR avg_rating BETWEEN 1 AND 5),

    CONSTRAINT chk_places_review_count
        CHECK (review_count >= 0),

    CONSTRAINT chk_places_plus_code
        CHECK (plus_code ~* '^[23456789CFGHJMPQRVWX]{8}\+[23456789CFGHJMPQRVWX]{2}$')
);

-- 5. OPENING HOURS
CREATE TABLE opening_hours (
    place_id INTEGER NOT NULL,
    weekday  SMALLINT NOT NULL,
    opens    TIME NOT NULL,
    closes   TIME NOT NULL,

    CONSTRAINT pk_opening_hours
        PRIMARY KEY (place_id, weekday),

    CONSTRAINT fk_opening_hours_place
        FOREIGN KEY (place_id)
        REFERENCES places(place_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_opening_hours_weekday
        CHECK (weekday BETWEEN 1 AND 7),

    CONSTRAINT chk_opening_hours_times
        CHECK (opens <> closes)
);

-- 6. PLACE REVIEWS
CREATE TABLE place_reviews (
    review_id   INTEGER PRIMARY KEY,
    place_id    INTEGER NOT NULL,
    user_id     INTEGER NOT NULL,
    rating      SMALLINT NOT NULL,
    review_text TEXT,
    photo_count SMALLINT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_reviews_place
        FOREIGN KEY (place_id)
        REFERENCES places(place_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_reviews_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_reviews_place_user
        UNIQUE (place_id, user_id),

    CONSTRAINT chk_reviews_rating
        CHECK (rating BETWEEN 1 AND 5),

    CONSTRAINT chk_reviews_photo_count
        CHECK (photo_count >= 0)
);

-- 7. SAVED PLACES
CREATE TABLE saved_places (
    user_id   INTEGER NOT NULL,
    place_id  INTEGER NOT NULL,
    list_name VARCHAR(40) NOT NULL,
    saved_at  TIMESTAMPTZ NOT NULL,

    CONSTRAINT pk_saved_places
        PRIMARY KEY (user_id, place_id, list_name),

    CONSTRAINT fk_saved_places_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_saved_places_place
        FOREIGN KEY (place_id)
        REFERENCES places(place_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_saved_places_list
        CHECK (list_name IN (
            'Favourites',
            'Starred',
            'Travel plans',
            'Want to go'
        ))
);

-- 8. ROAD SEGMENTS
CREATE TABLE road_segments (
    segment_id       INTEGER PRIMARY KEY,
    road_name        VARCHAR(200) NOT NULL,
    city_id          INTEGER NOT NULL,
    road_type        VARCHAR(20) NOT NULL,
    start_lat        NUMERIC(9,6) NOT NULL,
    start_lng        NUMERIC(9,6) NOT NULL,
    end_lat          NUMERIC(9,6) NOT NULL,
    end_lng          NUMERIC(9,6) NOT NULL,
    length_m         INTEGER NOT NULL,
    speed_limit_kmph SMALLINT NOT NULL,

    CONSTRAINT fk_road_segments_city
        FOREIGN KEY (city_id)
        REFERENCES cities(city_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_road_type
        CHECK (road_type IN ('ARTERIAL', 'HIGHWAY', 'LOCAL')),

    CONSTRAINT chk_road_start_lat
        CHECK (start_lat BETWEEN -90 AND 90),

    CONSTRAINT chk_road_start_lng
        CHECK (start_lng BETWEEN -180 AND 180),

    CONSTRAINT chk_road_end_lat
        CHECK (end_lat BETWEEN -90 AND 90),

    CONSTRAINT chk_road_end_lng
        CHECK (end_lng BETWEEN -180 AND 180),

    CONSTRAINT chk_road_length
        CHECK (length_m > 0),

    CONSTRAINT chk_road_speed
        CHECK (speed_limit_kmph > 0)
);

-- 9. TRAFFIC READINGS
CREATE TABLE traffic_readings (
    reading_id       INTEGER PRIMARY KEY,
    segment_id       INTEGER NOT NULL,
    recorded_at      TIMESTAMPTZ NOT NULL,
    avg_speed_kmph   NUMERIC(6,2) NOT NULL,
    congestion_level VARCHAR(20) NOT NULL,

    CONSTRAINT fk_traffic_segment
        FOREIGN KEY (segment_id)
        REFERENCES road_segments(segment_id)
        ON DELETE CASCADE,

    CONSTRAINT uq_traffic_segment_time
        UNIQUE (segment_id, recorded_at),

    CONSTRAINT chk_traffic_speed
        CHECK (avg_speed_kmph >= 0),

    CONSTRAINT chk_traffic_congestion
        CHECK (congestion_level IN ('LOW', 'MODERATE', 'HEAVY'))
);

-- 10. NAVIGATION SESSIONS
CREATE TABLE navigation_sessions (
    session_id       INTEGER PRIMARY KEY,
    user_id          INTEGER,
    origin_place_id  INTEGER,
    origin_lat       NUMERIC(9,6) NOT NULL,
    origin_lng       NUMERIC(9,6) NOT NULL,
    dest_place_id    INTEGER NOT NULL,
    travel_mode      VARCHAR(20) NOT NULL,
    started_at       TIMESTAMPTZ NOT NULL,
    distance_km      NUMERIC(6,2) NOT NULL,
    eta_minutes      INTEGER NOT NULL,
    actual_minutes   INTEGER,
    rerouted_count   SMALLINT NOT NULL,
    status           VARCHAR(20) NOT NULL,

    CONSTRAINT fk_navigation_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_navigation_origin
        FOREIGN KEY (origin_place_id)
        REFERENCES places(place_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_navigation_destination
        FOREIGN KEY (dest_place_id)
        REFERENCES places(place_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_navigation_origin_lat
        CHECK (origin_lat BETWEEN -90 AND 90),

    CONSTRAINT chk_navigation_origin_lng
        CHECK (origin_lng BETWEEN -180 AND 180),

    CONSTRAINT chk_navigation_mode
        CHECK (travel_mode IN (
            'DRIVE', 'TRANSIT', 'TWO_WHEELER', 'WALK'
        )),

    CONSTRAINT chk_navigation_distance
        CHECK (distance_km > 0),

    CONSTRAINT chk_navigation_eta
        CHECK (eta_minutes > 0),

    CONSTRAINT chk_navigation_actual
        CHECK (actual_minutes IS NULL OR actual_minutes > 0),

    CONSTRAINT chk_navigation_reroutes
        CHECK (rerouted_count >= 0),

    CONSTRAINT chk_navigation_status
        CHECK (status IN ('COMPLETED', 'CANCELLED', 'IN_PROGRESS')),

    CONSTRAINT chk_navigation_actual_status
        CHECK (
            (status = 'COMPLETED' AND actual_minutes IS NOT NULL)
            OR
            (status IN ('CANCELLED', 'IN_PROGRESS')
             AND actual_minutes IS NULL)
        )
);

-- 11. INCIDENT REPORTS
CREATE TABLE incident_reports (
    report_id     INTEGER PRIMARY KEY,
    segment_id    INTEGER NOT NULL,
    user_id       INTEGER NOT NULL,
    incident_type VARCHAR(30) NOT NULL,
    reported_at   TIMESTAMPTZ NOT NULL,
    expires_at    TIMESTAMPTZ NOT NULL,
    upvotes       INTEGER NOT NULL,

    CONSTRAINT fk_incidents_segment
        FOREIGN KEY (segment_id)
        REFERENCES road_segments(segment_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_incidents_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_incident_type
        CHECK (incident_type IN (
            'ACCIDENT',
            'BREAKDOWN',
            'CLOSURE',
            'POLICE',
            'ROADWORK',
            'WATERLOGGING'
        )),

    CONSTRAINT chk_incident_expiry
        CHECK (expires_at > reported_at),

    CONSTRAINT chk_incident_upvotes
        CHECK (upvotes >= 0)
);

-- End of schema
