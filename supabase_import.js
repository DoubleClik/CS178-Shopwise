/**
 * supabase_import.js
 *
 * Reads the classified Walmart and Kroger CSVs and uploads them to Supabase.
 * This runs as a stage inside runner.js, but you can also call it directly
 * if you just want to re-upload without touching anything else:
 *
 *   node supabase_import.js --all
 *   node supabase_import.js --walmart
 *   node supabase_import.js --kroger
 *   node supabase_import.js --all --dry-run
 *
 * Before running, make sure:
 *   - SUPABASE_URL and SUPABASE_SERVICE_KEY are set in .env
 *     (needs the service role key, not the anon key — anon key will hit RLS)
 *   - You've run schema.sql in the Supabase SQL editor to create the tables
 *   - If you're re-importing, TRUNCATE the tables first to avoid duplicates
 */

import { createClient } from '@supabase/supabase-js';
import { parse } from 'csv-parse';
import { createReadStream, writeFileSync } from 'fs';
import fetch from 'node-fetch';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY;

// How many rows to send per API call. 1000 is a good balance between fewer
// round trips and not timing out on large payloads.
const BATCH_SIZE = 1000;

const TABLE_WALMART = 'walmart_ingredients';
const TABLE_KROGER = 'kroger_ingredients2';
const TABLE_STORES = 'kroger_locations';

const KROGER_TOKEN_URL = 'https://api.kroger.com/v1/connect/oauth2/token';
const KROGER_LOCATIONS_URL = 'https://api.kroger.com/v1/locations';

const DAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in environment');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// ── Helpers ───────────────────────────────────────────────────────────────────

// Splits a delimited string into a trimmed, filtered array.
// Used for comma-separated classifiers and semicolon-separated store IDs/prices.
function split(s, sep) {
  if (!s) return [];
  return s
    .split(sep)
    .map((x) => x.trim())
    .filter(Boolean);
}

// Returns a float or null — null means the field was empty/unparseable,
// which lets callers decide whether to skip the row.
function toFloat(s) {
  const n = parseFloat(s);
  return isNaN(n) ? null : n;
}

// Wraps a file path in a csv-parse stream so we can iterate rows with
// `for await`. The `columns: true` option uses the first row as header names.
function csvParser(filePath) {
  return createReadStream(filePath).pipe(
    parse({ columns: true, skip_empty_lines: true, trim: true }),
  );
}

// Sends one batch of rows to Supabase. In dry-run mode it just logs what
// it would have done instead of actually writing anything.
// Pass onConflict to upsert instead of insert (e.g. 'productId').
async function insertBatch(table, rows, dryRun, onConflict = null) {
  if (dryRun) {
    console.log(`  [dry-run] would upsert ${rows.length} rows → ${table}`);
    return;
  }
  const query = onConflict
    ? supabase.from(table).upsert(rows, { onConflict })
    : supabase.from(table).insert(rows);
  const { error } = await query;
  if (error) throw new Error(`${table} upsert failed: ${error.message}`);
}

// ── Walmart ───────────────────────────────────────────────────────────────────
// Reads classified_ingredients.csv and uploads only the rows where
// ingredient=True (everything else was filtered out by classify_ingredients.py).
// Rows missing a name or price are skipped since both are NOT NULL in the table.

export async function importWalmart({ dryRun = false } = {}) {
  const file = path.join(
    __dirname,
    'WalmartPipeline/classified_ingredients.csv',
  );
  console.log(`\n  Source: ${file}`);

  let batch = [];
  let totalInserted = 0;
  let skippedNonIngredient = 0;
  let skippedMissingFields = 0;

  // Sends the current batch to Supabase and resets it.
  async function flush() {
    if (!batch.length) return;
    await insertBatch(TABLE_WALMART, batch, dryRun);
    totalInserted += batch.length;
    batch = [];
    process.stdout.write(
      `\r  Inserted ${totalInserted.toLocaleString()} rows...`,
    );
  }

  for await (const row of csvParser(file)) {
    // Only import rows that the classifier marked as a cooking ingredient
    if (row.ingredient !== 'True') {
      skippedNonIngredient++;
      continue;
    }

    const price = toFloat(row.retail_price);

    // Both name and price are NOT NULL in the table, so drop the row if either is missing
    if (!row.name || price === null) {
      skippedMissingFields++;
      continue;
    }

    batch.push({
      name: row.name,
      brand: row.brandName || null,
      price,
      classifiers: split(row.classifiers, ','),
      image: row.thumbnailImage || null,
      size: row.size || '',
    });

    // Flush once we hit the batch limit to keep memory usage flat
    if (batch.length >= BATCH_SIZE) await flush();
  }

  // Flush whatever is left over after the loop finishes
  await flush();

  console.log(`\n  Done.`);
  console.log(`    Inserted               : ${totalInserted.toLocaleString()}`);
  console.log(
    `    Skipped (not ingredient): ${skippedNonIngredient.toLocaleString()}`,
  );
  console.log(
    `    Skipped (no name/price) : ${skippedMissingFields.toLocaleString()}`,
  );
}

// ── Kroger ────────────────────────────────────────────────────────────────────
// Reads food_catalogue.csv and uploads the full catalogue.
// The price and store_id columns in the CSV are semicolon-delimited lists
// (one entry per store). We take the first price as a representative value
// and store all the store IDs as an array.

export async function importKroger({ dryRun = false } = {}) {
  const file = path.join(
    __dirname,
    'kroger_output/catalogue/food_catalogue.csv',
  );
  console.log(`\n  Source: ${file}`);

  let batch = [];
  let totalInserted = 0;
  let skippedMissingFields = 0;

  async function flush() {
    if (!batch.length) return;
    await insertBatch(TABLE_KROGER, batch, dryRun, 'productId');
    totalInserted += batch.length;
    batch = [];
    process.stdout.write(
      `\r  Inserted ${totalInserted.toLocaleString()} rows...`,
    );
  }

  for await (const row of csvParser(file)) {
    // description is what we store as the product name — skip if it's blank
    if (!row.description) {
      skippedMissingFields++;
      continue;
    }

    // price is stored as-is (semicolon-delimited per-store prices).
    // Skip if completely empty since the column is NOT NULL.
    const price = row.price ? row.price.trim() : '';
    if (!price) {
      skippedMissingFields++;
      continue;
    }

    batch.push({
      productId: row.productId ? parseInt(row.productId, 10) : null,
      upc: row.upc ? parseInt(row.upc, 10) : null,
      brand: row.brand || null,
      name: row.description,
      categories: row.categories || null,
      countryOrigin: row.countryOrigin || null,
      aisleLocations: row.aisleLocations || null,
      image_url: row.image_url || null,
      itemId: row.itemId ? parseInt(row.itemId, 10) : null,
      size: row.size || '',
      soldBy: row.soldBy || null,
      classifier: row.classifier || null,
      search_keyword: row.search_keyword || null,
      store_ids: row.store_ids || null,
      price: String(price),
    });

    if (batch.length >= BATCH_SIZE) await flush();
  }

  await flush();

  console.log(`\n  Done.`);
  console.log(`    Inserted               : ${totalInserted.toLocaleString()}`);
  console.log(
    `    Skipped (no name/price): ${skippedMissingFields.toLocaleString()}`,
  );
}

// ── Kroger Stores ─────────────────────────────────────────────────────────────
// Fetches the N nearest Kroger-family stores for a given zip code via the
// Kroger Locations API and upserts them into kroger_stores. Using upsert
// (instead of insert) means re-running is safe — it just refreshes the data.

async function fetchKrogerToken(clientId, clientSecret) {
  const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString(
    'base64',
  );
  const res = await fetch(KROGER_TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization: `Basic ${credentials}`,
    },
    body: 'grant_type=client_credentials&scope=product.compact',
  });
  if (!res.ok)
    throw new Error(
      `Kroger token request failed (${res.status}): ${await res.text()}`,
    );
  const data = await res.json();
  return data.access_token;
}

export async function importKrogerStores({
  zipcode,
  stores = 10,
  dryRun = false,
} = {}) {
  if (!zipcode) throw new Error('importKrogerStores requires a zipcode');

  const clientId = process.env.KROGER_CLIENT_ID;
  const clientSecret = process.env.KROGER_CLIENT_SECRET;
  if (!clientId || !clientSecret)
    throw new Error('Missing KROGER_CLIENT_ID or KROGER_CLIENT_SECRET');

  console.log(`\n  Fetching ${stores} nearest stores to zip ${zipcode}...`);
  const token = await fetchKrogerToken(clientId, clientSecret);

  const params = new URLSearchParams({
    'filter.zipCode.near': zipcode,
    'filter.limit': stores,
    'filter.radiusInMiles': 50,
  });
  const res = await fetch(`${KROGER_LOCATIONS_URL}?${params}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
  });
  if (!res.ok)
    throw new Error(
      `Kroger locations API error (${res.status}): ${await res.text()}`,
    );

  const storeList = (await res.json())?.data ?? [];
  if (!storeList.length) {
    console.log(`  No stores found near ${zipcode}.`);
    return;
  }

  // Map each store object to the exact column names in kroger_stores
  const rows = storeList.map((s) => {
    const addr = s.address ?? {};
    const geo = s.geolocation ?? {};
    const hrs = s.hours ?? {};

    // phone comes back as "(555) 123-4567" — strip everything except digits for bigint
    const phoneDigits = s.phone
      ? parseInt(s.phone.replace(/\D/g, ''), 10)
      : null;

    const record = {
      locationId: s.locationId ? parseInt(s.locationId, 10) : null,
      name: s.name ?? null,
      chain: s.chain ?? null,
      phone: isNaN(phoneDigits) ? null : phoneDigits,
      address_line1: addr.addressLine1 ?? null,
      address_line2: addr.addressLine2 ?? null,
      address_city: addr.city ?? null,
      address_state: addr.state ?? null,
      address_zipCode: addr.zipCode ? parseInt(addr.zipCode, 10) : null,
      address_county: addr.county ?? null,
      geo_latitude: geo.latitude ?? null,
      geo_longitude: geo.longitude ?? null,
      hours_timezone: hrs.timezone ?? null,
      hours_gmtOffset: hrs.gmtOffset != null ? String(hrs.gmtOffset) : null,
      hours_open24: hrs.open24 ?? null,
    };

    // Flatten each day's open/close/open24 into individual columns
    for (const day of DAYS) {
      const d = hrs[day] ?? {};
      record[`hours_${day}_open`] = d.open ?? null;
      record[`hours_${day}_close`] = d.close ?? null;
      record[`hours_${day}_open24`] = d.open24 ?? null;
    }

    return record;
  });

  if (dryRun) {
    const schemaPath = path.join(__dirname, 'kroger_stores_schema.csv');
    const headers = Object.keys(rows[0]);
    // Escape a value for CSV — wrap in quotes if it contains commas, quotes, or newlines
    const esc = (v) => {
      if (v === null || v === undefined) return '';
      const s = String(v);
      return s.includes(',') || s.includes('"') || s.includes('\n')
        ? `"${s.replace(/"/g, '""')}"`
        : s;
    };
    const lines = [
      headers.join(','),
      ...rows.map((r) => headers.map((h) => esc(r[h])).join(',')),
    ];
    writeFileSync(schemaPath, lines.join('\n'), 'utf8');
    console.log(`  [dry-run] wrote ${rows.length} stores → ${schemaPath}`);
    return;
  }

  // Upsert so re-runs just refresh store data instead of erroring on duplicates
  const { error } = await supabase
    .from(TABLE_STORES)
    .upsert(rows, { onConflict: 'locationId' });
  if (error) throw new Error(`${TABLE_STORES} upsert failed: ${error.message}`);

  console.log(
    `  Upserted ${rows.length} stores near ${zipcode} → ${TABLE_STORES}`,
  );
}

// ── Entry point (when run directly) ──────────────────────────────────────────
// This block only runs when you call `node supabase_import.js` directly.
// When runner.js imports this file it just gets the exported functions above.

const argv = process.argv.slice(2);
const runAll = argv.includes('--all');
const runWalmart = argv.includes('--walmart') || runAll;
const runKroger = argv.includes('--kroger') || runAll;
const isDryRun = argv.includes('--dry-run');

async function main() {
  if (!runWalmart && !runKroger) {
    console.error(
      'Specify --walmart, --kroger, or --all\n' +
        'Example: node supabase_import.js --all --dry-run',
    );
    process.exit(1);
  }

  if (runWalmart) {
    console.log('\n[supabase:walmart] Importing Walmart ingredients...');
    await importWalmart({ dryRun: isDryRun });
  }

  if (runKroger) {
    console.log('\n[supabase:kroger] Importing Kroger ingredients...');
    await importKroger({ dryRun: isDryRun });
  }

  console.log('\nImport complete.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((err) => {
    console.error('Fatal:', err.message);
    process.exit(1);
  });
}
