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
  store_id    TEXT[]      NOT NULL
);

CREATE INDEX IF NOT EXISTS kroger_ingredients_classifiers_idx
  ON kroger_ingredients USING GIN (classifiers);

CREATE INDEX IF NOT EXISTS kroger_ingredients_store_id_idx
  ON kroger_ingredients USING GIN (store_id);
