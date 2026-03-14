-- Shopwise Supabase schema
-- Run this once in the Supabase SQL editor before running the import stage.
-- If you already created the tables via the dashboard, you can skip this.

-- ── Walmart ingredients ──────────────────────────────────────────────────────
-- Only ingredient=True rows are imported. Re-runs require TRUNCATE first.

CREATE TABLE IF NOT EXISTS walmart_ingredients (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  name        TEXT        NOT NULL,
  brand       TEXT,
  price       NUMERIC     NOT NULL,
  classifiers TEXT[]      NOT NULL,
  image       TEXT,
  size        TEXT        NOT NULL
);

CREATE INDEX IF NOT EXISTS walmart_ingredients_classifiers_idx
  ON walmart_ingredients USING GIN (classifiers);


-- ── Kroger ingredients ───────────────────────────────────────────────────────
-- Full food catalogue. Re-runs require TRUNCATE first.
-- store_id holds the semicolon-delimited store IDs as an array.
-- price holds the first available price across stores.

CREATE TABLE IF NOT EXISTS kroger_ingredients (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  name        TEXT        NOT NULL,
  brand       TEXT,
  price       NUMERIC     NOT NULL,
  classifiers TEXT[]      NOT NULL,
  image       TEXT,
  size        TEXT        NOT NULL,
  store_id        TEXT[]      NOT NULL,
  search_keyword  TEXT
);

CREATE INDEX IF NOT EXISTS kroger_ingredients_classifiers_idx
  ON kroger_ingredients USING GIN (classifiers);

CREATE INDEX IF NOT EXISTS kroger_ingredients_store_id_idx
  ON kroger_ingredients USING GIN (store_id);


-- ── Kroger stores ─────────────────────────────────────────────────────────────
-- Populated by kroger:stores stage (requires --zipcode).
-- Upserts on locationId so re-runs just refresh the data.

CREATE TABLE IF NOT EXISTS kroger_locations (
  "locationId"            BIGINT      NOT NULL UNIQUE,
  name                    TEXT,
  chain                   TEXT,
  phone                   BIGINT,
  address_line1           TEXT,
  address_line2           TEXT,
  address_city            TEXT,
  address_state           TEXT,
  "address_zipCode"       BIGINT,
  address_county          TEXT,
  geo_latitude            DOUBLE PRECISION,
  geo_longitude           DOUBLE PRECISION,
  hours_timezone          TEXT,
  "hours_gmtOffset"       TEXT,
  hours_open24            BOOLEAN,
  hours_monday_open       TEXT,
  hours_monday_close      TEXT,
  hours_monday_open24     BOOLEAN,
  hours_tuesday_open      TEXT,
  hours_tuesday_close     TEXT,
  hours_tuesday_open24    BOOLEAN,
  hours_wednesday_open    TEXT,
  hours_wednesday_close   TEXT,
  hours_wednesday_open24  BOOLEAN,
  hours_thursday_open     TEXT,
  hours_thursday_close    TEXT,
  hours_thursday_open24   BOOLEAN,
  hours_friday_open       TEXT,
  hours_friday_close      TEXT,
  hours_friday_open24     BOOLEAN,
  hours_saturday_open     TEXT,
  hours_saturday_close    TEXT,
  hours_saturday_open24   BOOLEAN,
  hours_sunday_open       TEXT,
  hours_sunday_close      TEXT,
  hours_sunday_open24     BOOLEAN
);
