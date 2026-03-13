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
import { createReadStream } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY;

// How many rows to send per API call. 1000 is a good balance between fewer
// round trips and not timing out on large payloads.
const BATCH_SIZE = 1000;

const TABLE_WALMART = 'walmart_ingredients';
const TABLE_KROGER = 'kroger_ingredients';

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
  return s.split(sep).map((x) => x.trim()).filter(Boolean);
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
async function insertBatch(table, rows, dryRun) {
  if (dryRun) {
    console.log(`  [dry-run] would insert ${rows.length} rows → ${table}`);
    return;
  }
  const { error } = await supabase.from(table).insert(rows);
  if (error) throw new Error(`${table} insert failed: ${error.message}`);
}

// ── Walmart ───────────────────────────────────────────────────────────────────
// Reads classified_ingredients.csv and uploads only the rows where
// ingredient=True (everything else was filtered out by classify_ingredients.py).
// Rows missing a name or price are skipped since both are NOT NULL in the table.

export async function importWalmart({ dryRun = false } = {}) {
  const file = path.join(__dirname, 'WalmartPipeline/classified_ingredients.csv');
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
    process.stdout.write(`\r  Inserted ${totalInserted.toLocaleString()} rows...`);
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
  console.log(`    Skipped (not ingredient): ${skippedNonIngredient.toLocaleString()}`);
  console.log(`    Skipped (no name/price) : ${skippedMissingFields.toLocaleString()}`);
}

// ── Kroger ────────────────────────────────────────────────────────────────────
// Reads food_catalogue.csv and uploads the full catalogue.
// The price and store_id columns in the CSV are semicolon-delimited lists
// (one entry per store). We take the first price as a representative value
// and store all the store IDs as an array.

export async function importKroger({ dryRun = false } = {}) {
  const file = path.join(__dirname, 'kroger_output/catalogue/food_catalogue.csv');
  console.log(`\n  Source: ${file}`);

  let batch = [];
  let totalInserted = 0;
  let skippedMissingFields = 0;

  async function flush() {
    if (!batch.length) return;
    await insertBatch(TABLE_KROGER, batch, dryRun);
    totalInserted += batch.length;
    batch = [];
    process.stdout.write(`\r  Inserted ${totalInserted.toLocaleString()} rows...`);
  }

  for await (const row of csvParser(file)) {
    // description is what we store as the product name — skip if it's blank
    if (!row.description) {
      skippedMissingFields++;
      continue;
    }

    // The price column looks like "2.99;3.49;2.99" — one price per store.
    // We just grab the first one as a representative price for the product.
    const price = toFloat(split(row.price, ';')[0]);
    if (price === null) {
      skippedMissingFields++;
      continue;
    }

    batch.push({
      name: row.description,
      brand: row.brand || null,
      price,
      // classifier is a single tag like "PRODUCE" — wrap it in an array
      // to match the classifiers column type on the Walmart table
      classifiers: row.classifier ? [row.classifier] : [],
      image: row.image_url || null,
      size: row.size || '',
      // store_ids looks like "70400786;70400343" — split into an array
      store_id: split(row.store_ids, ';'),
    });

    if (batch.length >= BATCH_SIZE) await flush();
  }

  await flush();

  console.log(`\n  Done.`);
  console.log(`    Inserted               : ${totalInserted.toLocaleString()}`);
  console.log(`    Skipped (no name/price): ${skippedMissingFields.toLocaleString()}`);
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
