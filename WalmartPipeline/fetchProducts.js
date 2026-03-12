/**
 * fetchProducts.js
 *
 * Pulls Walmart food products by category and saves them to CSVs.
 * You can import run() from another script or just run this file directly.
 *
 * Credentials go in .env:
 *   WM_CONSUMER_ID, WM_KEY_VERSION, WM_PRIVATE_KEY
 *
 * All the config options (page size, delays, dedup settings, etc.) have
 * defaults so calling run() with no arguments should just work.
 */

import dotenv from 'dotenv';
dotenv.config();
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);

const BASE = 'https://developer.api.walmart.com';
const PAGINATED_PATH = '/api-proxy/service/affil/product/v2/paginated/items';
const MAX_ERROR_BODY_CHARS = 1200;

// columns we actually care about for ingredient matching
// dropped a bunch of stuff (images, ratings, tracking URLs) that we don't need
// added size because it helps with dedup and matching later

const COLUMNS = [
  'item_id',
  'name',
  'brandName',
  'size',
  'retail_price',
  'upc',
  'subtree_name',
  'category_id',
  'category_name',
  'category_path',
  'shortDescription',
  'thumbnailImage',
];

function loadCredentials() {
  const consumerId = process.env.WM_CONSUMER_ID;
  const keyVer = process.env.WM_KEY_VERSION;
  const privateKeyPem = process.env.WM_PRIVATE_KEY;

  if (!consumerId || !keyVer || !privateKeyPem) {
    throw new Error(
      'Missing Walmart credentials in .env: WM_CONSUMER_ID, WM_KEY_VERSION, WM_PRIVATE_KEY',
    );
  }

  return { consumerId, keyVer, privateKeyPem };
}

// Walmart requires a signed auth header on every request
function buildAuthHeaders(creds) {
  const id = String(creds.consumerId).trim();
  const kv = String(creds.keyVer).trim();
  const ts = String(Date.now()).trim();

  const fields = {
    'WM_CONSUMER.ID': id,
    'WM_CONSUMER.INTIMESTAMP': ts,
    'WM_SEC.KEY_VERSION': kv,
  };

  const canonicalized =
    Object.keys(fields)
      .sort()
      .map((k) => fields[k])
      .join('\n') + '\n';

  const signature = crypto
    .sign('RSA-SHA256', Buffer.from(canonicalized, 'utf8'), {
      key: creds.privateKeyPem,
      padding: crypto.constants.RSA_PKCS1_PADDING,
    })
    .toString('base64');

  return {
    'WM_CONSUMER.ID': id,
    'WM_CONSUMER.INTIMESTAMP': ts,
    'WM_SEC.TIMESTAMP': ts,
    'WM_SEC.KEY_VERSION': kv,
    'WM_SEC.AUTH_SIGNATURE': signature,
    Accept: 'application/json',
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeCSV(value) {
  const s = String(value ?? '');
  return `"${s.replaceAll('"', '""')}"`;
}

function sanitizeFilename(value) {
  return (
    String(value ?? 'export')
      .trim()
      .replaceAll(/[^\w\-]+/g, '_')
      .replaceAll(/_+/g, '_')
      .replaceAll(/^_+|_+$/g, '')
      .slice(0, 160) || 'export'
  );
}

function formatISO(d) {
  return d.toISOString();
}

function msToHMS(ms) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m ${s % 60}s`;
}

function safeTruncate(s, n) {
  const str = String(s ?? '');
  if (str.length <= n) return str;
  return str.slice(0, n) + `... [truncated ${str.length - n} chars]`;
}

// simple CSV parser - handles quoted fields and escaped quotes
function parseCSV(text) {
  const rows = [];
  let i = 0;
  let field = '';
  let row = [];
  let inQuotes = false;

  while (i < text.length) {
    const c = text[i];

    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field += c;
      i++;
      continue;
    }

    if (c === '"') {
      inQuotes = true;
      i++;
      continue;
    }
    if (c === ',') {
      row.push(field);
      field = '';
      i++;
      continue;
    }
    if (c === '\n') {
      row.push(field);
      field = '';
      rows.push(row);
      row = [];
      i++;
      continue;
    }
    if (c === '\r') {
      i++;
      continue;
    }
    field += c;
    i++;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

function rowsToObjects(rows) {
  if (!rows.length) return [];
  const header = rows[0].map((h) => h.trim());
  return rows.slice(1).map((cols) => {
    const obj = {};
    header.forEach((h, i) => {
      obj[h] = cols[i] ?? '';
    });
    return obj;
  });
}

function getDepth(pathValue) {
  const s = String(pathValue ?? '').trim();
  if (!s) return Number.POSITIVE_INFINITY;
  return s.split('/').length;
}

function pickSubtreeRoot(objs) {
  const candidates = objs.filter(
    (o) => String(o.id ?? '').trim() && String(o.name ?? '').trim(),
  );
  if (!candidates.length) return null;

  candidates.sort((a, b) => {
    const da = getDepth(a.path);
    const db = getDepth(b.path);
    if (da !== db) return da - db;
    return String(a.path ?? '').length - String(b.path ?? '').length;
  });

  return candidates[0];
}

function isParentRow(allRows, row) {
  const p = String(row.path ?? '').trim();
  if (!p) return false;
  const prefix = p.endsWith('/') ? p : p + '/';
  return allRows.some((o) => String(o.path ?? '').startsWith(prefix));
}

function itemToRow(item, extra) {
  return {
    item_id: item?.itemId ?? '',
    name: item?.name ?? '',
    brandName: item?.brandName ?? '',
    size: item?.size ?? '',
    retail_price: item?.salePrice ?? '',
    upc: item?.upc ?? '',
    subtree_name: extra.subtree_name,
    category_id: extra.category_id,
    category_name: extra.category_name,
    category_path: extra.category_path,
    shortDescription: item?.shortDescription ?? '',
    thumbnailImage: item?.thumbnailImage ?? '',
  };
}

function csvHeader() {
  return COLUMNS.join(',') + '\n';
}

function rowToCSVLine(row) {
  return COLUMNS.map((k) => escapeCSV(row[k])).join(',') + '\n';
}

async function fetchPage(url, creds, attempts, retryBaseDelayMs) {
  for (let i = 0; i < attempts; i++) {
    const headers = buildAuthHeaders(creds);
    const res = await fetch(url, { headers });

    if (res.ok) return await res.json();

    const status = res.status;
    if (status === 429 || (status >= 500 && status <= 599)) {
      await sleep(retryBaseDelayMs * Math.pow(2, i));
      continue;
    }

    const body = await res.text().catch(() => '');
    const err = new Error(`HTTP ${status} ${res.statusText}`);
    Object.assign(err, {
      httpStatus: status,
      httpStatusText: res.statusText,
      url,
      responseBody: safeTruncate(body, MAX_ERROR_BODY_CHARS),
    });
    throw err;
  }

  const err = new Error(`Failed after ${attempts} attempts`);
  err.url = url;
  throw err;
}

async function fetchAllItemsForCategory(categoryId, creds, cfg) {
  let url = new URL(BASE + PAGINATED_PATH);
  url.searchParams.set('category', categoryId);
  url.searchParams.set('count', String(cfg.countPerPage));

  const allItems = [];

  while (true) {
    const data = await fetchPage(
      url.toString(),
      creds,
      cfg.fetchAttempts,
      cfg.retryBaseDelayMs,
    );
    const items = Array.isArray(data?.items) ? data.items : [];
    allItems.push(...items);

    if (!data?.nextPageExist || !data?.nextPage) break;

    url = new URL(
      data.nextPage.startsWith('http') ? data.nextPage : BASE + data.nextPage,
    );
    await sleep(cfg.requestDelayMs);
  }

  return allItems;
}

// write a JSON log file at the end so we can see what happened and debug failures
function writeRunLog(outPath, runState) {
  const endedAt = runState.endedAt ?? new Date();
  const elapsed = endedAt.getTime() - runState.startedAt.getTime();
  const logName = `run_log_${sanitizeFilename(formatISO(runState.startedAt))}.json`;
  const payload = {
    startedAt: formatISO(runState.startedAt),
    endedAt: formatISO(endedAt),
    elapsed: msToHMS(elapsed),
    exitReason: runState.exitReason,
    counts: {
      subtreeFilesProcessed: runState.subtreeFilesProcessed,
      categoryRowsAttempted: runState.categoryRowsAttempted,
      categoryRowsSucceeded: runState.categoryRowsSucceeded,
      categoryRowsFailed: runState.categoryRowsFailed,
    },
    failures: runState.failures,
  };
  fs.writeFileSync(
    path.join(outPath, logName),
    JSON.stringify(payload, null, 2),
    'utf8',
  );
  console.log(`Log written: ${logName}`);
}

export async function run(config = {}) {
  const cfg = {
    categoriesDir: config.categoriesDir ?? 'WalmartPipeline/Categories',
    outDir: config.outDir ?? 'WalmartPipeline/walmart_CSVs',
    countPerPage: config.countPerPage ?? 500,
    requestDelayMs: config.requestDelayMs ?? 25,
    categoryDelayMs: config.categoryDelayMs ?? 25,
    fetchAttempts: config.fetchAttempts ?? 5,
    retryBaseDelayMs: config.retryBaseDelayMs ?? 50,
    exportParentRows: config.exportParentRows ?? false,
    dedupeWithinCategory: config.dedupeWithinCategory ?? true,
    dedupeWithinSubtree: config.dedupeWithinSubtree ?? true,
    dedupeMaster: config.dedupeMaster ?? false,
  };

  const creds = loadCredentials();

  const categoriesPath = path.resolve(process.cwd(), cfg.categoriesDir);
  const outPath = path.resolve(process.cwd(), cfg.outDir);

  if (!fs.existsSync(categoriesPath)) {
    throw new Error(`Missing categories folder: ${categoriesPath}`);
  }
  if (!fs.existsSync(outPath)) {
    fs.mkdirSync(outPath, { recursive: true });
  }

  const subtreeFiles = fs
    .readdirSync(categoriesPath)
    .filter((f) => f.toLowerCase().endsWith('.csv'));

  if (!subtreeFiles.length) {
    throw new Error(`No .csv files found in ${categoriesPath}`);
  }

  const runState = {
    startedAt: new Date(),
    endedAt: null,
    exitReason: 'completed',
    subtreeFilesProcessed: 0,
    categoryRowsAttempted: 0,
    categoryRowsSucceeded: 0,
    categoryRowsFailed: 0,
    failures: [],
  };

  const masterFile = path.join(outPath, 'ALL_SUBTREES_PRODUCTS.csv');
  const masterStream = fs.createWriteStream(masterFile, { encoding: 'utf8' });
  masterStream.write(csvHeader());

  const seenMaster = cfg.dedupeMaster ? new Set() : null;
  let masterCount = 0;

  try {
    for (const file of subtreeFiles) {
      const subtreeCsvPath = path.join(categoriesPath, file);
      const text = fs.readFileSync(subtreeCsvPath, 'utf8');
      const parsed = parseCSV(text);
      const objsRaw = rowsToObjects(parsed);

      if (!objsRaw.length) continue;

      const root = pickSubtreeRoot(objsRaw);
      const subtree_name = root?.name ?? path.basename(file, '.csv');
      const subtree_id = root?.id ?? '';
      const subtreeLabel = sanitizeFilename(
        `${subtree_name}_${subtree_id || 'unknown'}`,
      );

      const subtreeAggFile = path.join(outPath, `${subtreeLabel}__ALL.csv`);
      const subtreeAggStream = fs.createWriteStream(subtreeAggFile, {
        encoding: 'utf8',
      });
      subtreeAggStream.write(csvHeader());

      const seenSubtreeAgg = cfg.dedupeWithinSubtree ? new Set() : null;
      let subtreeAggCount = 0;

      const rows = objsRaw
        .map((o) => ({
          id: String(o.id ?? '').trim(),
          name: String(o.name ?? '').trim(),
          path: String(o.path ?? '').trim(),
        }))
        .filter((o) => o.id && o.name);

      for (const row of rows) {
        if (!cfg.exportParentRows && isParentRow(rows, row)) continue;

        runState.categoryRowsAttempted++;
        await sleep(cfg.categoryDelayMs);

        let items;
        try {
          items = await fetchAllItemsForCategory(row.id, creds, cfg);
          runState.categoryRowsSucceeded++;
        } catch (e) {
          runState.categoryRowsFailed++;
          runState.failures.push({
            type: 'categoryFetchFailed',
            subtreeFile: file,
            subtreeName: subtree_name,
            categoryId: row.id,
            categoryName: row.name,
            categoryPath: row.path,
            message: String(e?.message ?? e),
            httpStatus: e?.httpStatus ?? null,
            url: e?.url ?? null,
            responseBody: e?.responseBody ?? null,
            when: formatISO(new Date()),
          });
          console.error(
            `Failed category ${row.id} (${row.name}): ${e.message}`,
          );
          continue;
        }

        const categoryLabel = sanitizeFilename(
          `${subtree_name}_${subtree_id}__${row.name}_${row.id}`,
        );
        const categoryFile = path.join(outPath, `${categoryLabel}.csv`);
        const categoryStream = fs.createWriteStream(categoryFile, {
          encoding: 'utf8',
        });
        categoryStream.write(csvHeader());

        const seenCategory = cfg.dedupeWithinCategory ? new Set() : null;
        let categoryCount = 0;

        for (const item of items) {
          const itemId = String(item?.itemId ?? '');
          if (!itemId) continue;

          if (seenCategory) {
            if (seenCategory.has(itemId)) continue;
            seenCategory.add(itemId);
          }

          const outRow = itemToRow(item, {
            subtree_name,
            category_id: row.id,
            category_name: row.name,
            category_path: row.path,
          });

          categoryStream.write(rowToCSVLine(outRow));
          categoryCount++;

          if (seenSubtreeAgg) {
            if (!seenSubtreeAgg.has(itemId)) {
              seenSubtreeAgg.add(itemId);
              subtreeAggStream.write(rowToCSVLine(outRow));
              subtreeAggCount++;
            }
          } else {
            subtreeAggStream.write(rowToCSVLine(outRow));
            subtreeAggCount++;
          }

          if (seenMaster) {
            if (!seenMaster.has(itemId)) {
              seenMaster.add(itemId);
              masterStream.write(rowToCSVLine(outRow));
              masterCount++;
            }
          } else {
            masterStream.write(rowToCSVLine(outRow));
            masterCount++;
          }
        }

        await new Promise((resolve) => categoryStream.end(resolve));
        if (categoryCount > 0) {
          console.log(
            `Wrote ${path.basename(categoryFile)} (${categoryCount} rows)`,
          );
        }
      }

      await new Promise((resolve) => subtreeAggStream.end(resolve));
      runState.subtreeFilesProcessed++;
      console.log(
        `Wrote ${path.basename(subtreeAggFile)} (${subtreeAggCount} rows)`,
      );
    }
  } finally {
    await new Promise((resolve) => masterStream.end(resolve));
    runState.endedAt = new Date();
    writeRunLog(outPath, runState);
  }

  console.log(`Wrote ${path.basename(masterFile)} (${masterCount} rows)`);

  return {
    subtreeFilesProcessed: runState.subtreeFilesProcessed,
    categoryRowsAttempted: runState.categoryRowsAttempted,
    categoryRowsSucceeded: runState.categoryRowsSucceeded,
    categoryRowsFailed: runState.categoryRowsFailed,
  };
}

// run directly if called as a script (not imported)
if (process.argv[1] === __filename) {
  run().catch((err) => {
    console.error(err.message ?? err);
    process.exit(1);
  });
}
