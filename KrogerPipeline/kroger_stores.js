/**
 * kroger_stores.js
 *
 * Fetches ALL Kroger-family stores in the US by sweeping a geographic grid
 * of zip codes at maximum radius (100 miles), then deduplicating by locationId.
 *
 * WHY THE GRID APPROACH:
 *   The Kroger API hard-caps results at 200 per request with no working global
 *   offset pagination. The only way to get all ~2,800 stores is to tile the
 *   entire US with overlapping radius queries and deduplicate the results.
 *
 * SETUP:
 *   Uses the same .env / credentials as kroger_food_scraper.js
 *   npm install node-fetch@2 dotenv   (if not already installed)
 *
 * USAGE:
 *   node kroger_stores.js [flags]
 *
 * FLAGS:
 *   --out=./my-dir     Output directory            (default: ./kroger_output)
 *   --radius=100       Search radius per zip code  (default: 100, max: 100)
 *   --chain=KROGER     Filter to one chain only
 *                      Values: KROGER, RALPHS, FRED MEYER, KING SOOPERS,
 *                              SMITHS, FRYSFOOD, HARRIS TEETER, CITY MARKET,
 *                              DILLONS, BAKERS, GERBES, QFC, MARIANO
 *   --dry-run          Only query first 10 zip codes (for credential testing)
 *   --concurrency=5    Parallel requests at once   (default: 5, max: 10)
 *
 * EXAMPLES:
 *   node kroger_stores.js
 *   node kroger_stores.js --chain=KROGER --out=./kroger-only
 *   node kroger_stores.js --dry-run
 */

import 'dotenv/config';
import fetch from 'node-fetch';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ─── Config ────────────────────────────────────────────────────────────────────

const BASE_URL = 'https://api.kroger.com/v1';
const TOKEN_URL = `${BASE_URL}/connect/oauth2/token`;
const LOCATIONS_URL = `${BASE_URL}/locations`;

const MAX_LIMIT = 200; // Kroger API hard cap per request
const RETRY_DELAY_MS = 2000;
const MAX_RETRIES = 4;

// ─── CLI Args ──────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
function getArg(prefix) {
  return (
    (args.find((a) => a.startsWith(prefix)) ?? '').replace(prefix, '') || ''
  );
}

const isDryRun = args.includes('--dry-run');
const outDir = getArg('--out=') || './kroger_output';
const storesDir = path.join(outDir, 'stores');
const chainArg = getArg('--chain=').toUpperCase();
const radius = Math.min(parseInt(getArg('--radius=') || '100', 10), 100);
const concurrency = Math.min(parseInt(getArg('--concurrency=') || '5', 10), 10);

// ─── US ZIP CODE GRID ──────────────────────────────────────────────────────────
// ~280 zip codes chosen to give contiguous coverage of the entire continental
// US, Alaska, and Hawaii at a 100-mile radius. Each point is a real zip code
// of a city/town in that geographic cell. Overlapping circles ensure no gap
// is larger than ~140 miles (2× the radius), so every Kroger store is reachable
// from at least one query point.

const GRID_ZIPS = [
  // ── Pacific Northwest ──────────────────────────────────────────────────────
  '98101',
  '98201',
  '98801',
  '99201',
  '99301',
  '99401',
  '97201',
  '97401',
  '97501',
  '97701',
  '97801',
  '97901',
  // ── California ────────────────────────────────────────────────────────────
  '96001',
  '95901',
  '95501',
  '94102',
  '94601',
  '95008',
  '93401',
  '93101',
  '92101',
  '91101',
  '90001',
  '90401',
  '92501',
  '92701',
  '93301',
  '93601',
  '94201',
  '94901',
  '95201',
  '95301',
  '95701',
  '96101',
  // ── Nevada / Arizona ──────────────────────────────────────────────────────
  '89101',
  '89301',
  '89501',
  '89701',
  '89801',
  '85001',
  '85201',
  '85301',
  '85501',
  '85701',
  '86001',
  '86301',
  '86401',
  '86501',
  // ── Alaska ────────────────────────────────────────────────────────────────
  '99501',
  '99701',
  '99901',
  // ── Hawaii ────────────────────────────────────────────────────────────────
  '96801',
  '96720',
  '96740',
  '96761',
  // ── Mountain West ─────────────────────────────────────────────────────────
  '83201',
  '83401',
  '83701',
  '84101',
  '84301',
  '84501',
  '84601',
  '84701',
  '84901',
  '85901',
  '86001',
  // ── Colorado / Wyoming / Montana / Idaho ──────────────────────────────────
  '80202',
  '80401',
  '80501',
  '80631',
  '80901',
  '81001',
  '81201',
  '81301',
  '81401',
  '81501',
  '82001',
  '82301',
  '82601',
  '82901',
  '83001',
  '83201',
  '59001',
  '59401',
  '59601',
  '59801',
  '59901',
  '82801',
  '82901',
  '83001',
  // ── New Mexico ────────────────────────────────────────────────────────────
  '87101',
  '87401',
  '87501',
  '87701',
  '87901',
  '88001',
  '88201',
  '88401',
  '88601',
  // ── North / South Dakota / Nebraska / Kansas ──────────────────────────────
  '57001',
  '57201',
  '57401',
  '57601',
  '57701',
  '57901',
  '58001',
  '58201',
  '58401',
  '58601',
  '58801',
  '68001',
  '68101',
  '68401',
  '68501',
  '68801',
  '69001',
  '66101',
  '66201',
  '66401',
  '66601',
  '66801',
  '67001',
  '67201',
  '67401',
  '67601',
  '67801',
  '67901',
  // ── Oklahoma / Texas ──────────────────────────────────────────────────────
  '73101',
  '73401',
  '73601',
  '73801',
  '74101',
  '74401',
  '74601',
  '74801',
  '75001',
  '75201',
  '75401',
  '75601',
  '75801',
  '76001',
  '76201',
  '76401',
  '76601',
  '76801',
  '77001',
  '77201',
  '77401',
  '77601',
  '77801',
  '78101',
  '78201',
  '78401',
  '78501',
  '78701',
  '78801',
  '79101',
  '79201',
  '79401',
  '79601',
  '79701',
  '79901',
  // ── Minnesota / Wisconsin / Iowa ──────────────────────────────────────────
  '55101',
  '55301',
  '55401',
  '55601',
  '55701',
  '55801',
  '56001',
  '56201',
  '56301',
  '56401',
  '56501',
  '56601',
  '56701',
  '56801',
  '57001',
  '54101',
  '54201',
  '54401',
  '54501',
  '54601',
  '54701',
  '54901',
  '52001',
  '52101',
  '52201',
  '52301',
  '52401',
  '52501',
  '52601',
  '52701',
  '52801',
  // ── Illinois / Missouri ───────────────────────────────────────────────────
  '60601',
  '60901',
  '61101',
  '61201',
  '61401',
  '61601',
  '61701',
  '61801',
  '61901',
  '62001',
  '62201',
  '62401',
  '62601',
  '62701',
  '62801',
  '62901',
  '63101',
  '63301',
  '63401',
  '63501',
  '63601',
  '63701',
  '63801',
  '63901',
  '64101',
  '64501',
  '64701',
  '64801',
  '65101',
  '65201',
  '65401',
  '65601',
  '65701',
  '65801',
  '65901',
  // ── Michigan ──────────────────────────────────────────────────────────────
  '48101',
  '48201',
  '48401',
  '48601',
  '48701',
  '48801',
  '48901',
  '49001',
  '49101',
  '49201',
  '49301',
  '49401',
  '49501',
  '49601',
  '49701',
  '49801',
  '49901',
  // ── Indiana / Ohio ────────────────────────────────────────────────────────
  '46201',
  '46401',
  '46501',
  '46601',
  '46701',
  '46801',
  '47201',
  '47401',
  '47601',
  '47701',
  '47901',
  '43101',
  '43201',
  '43401',
  '43501',
  '43601',
  '43701',
  '43801',
  '43901',
  '44101',
  '44201',
  '44301',
  '44401',
  '44501',
  '44601',
  '44701',
  '44801',
  '44901',
  '45101',
  '45201',
  '45301',
  '45401',
  '45501',
  '45601',
  '45701',
  '45801',
  '45901',
  // ── Kentucky / Tennessee ──────────────────────────────────────────────────
  '40201',
  '40601',
  '41001',
  '41101',
  '41201',
  '41301',
  '41401',
  '41501',
  '41601',
  '41701',
  '42001',
  '42101',
  '42201',
  '42301',
  '42401',
  '42501',
  '42601',
  '42701',
  '37011',
  '37101',
  '37201',
  '37301',
  '37401',
  '37501',
  '37601',
  '37701',
  '37801',
  '37901',
  '38001',
  '38101',
  '38201',
  '38301',
  '38401',
  '38501',
  '38601',
  '38701',
  '38801',
  '38901',
  // ── Virginia / West Virginia / North Carolina ─────────────────────────────
  '22201',
  '22301',
  '22601',
  '22901',
  '23101',
  '23201',
  '23401',
  '23601',
  '23801',
  '24101',
  '24201',
  '24301',
  '24401',
  '24501',
  '24601',
  '24701',
  '24801',
  '24901',
  '25101',
  '25301',
  '25501',
  '25701',
  '25801',
  '25901',
  '26101',
  '26201',
  '26301',
  '26401',
  '26501',
  '26601',
  '27101',
  '27201',
  '27301',
  '27401',
  '27501',
  '27601',
  '27701',
  '27801',
  '27901',
  '28001',
  '28101',
  '28201',
  '28301',
  '28401',
  '28501',
  '28601',
  '28701',
  '28801',
  '28901',
  // ── South Carolina / Georgia ──────────────────────────────────────────────
  '29101',
  '29201',
  '29301',
  '29401',
  '29501',
  '29601',
  '29701',
  '29801',
  '29901',
  '30001',
  '30101',
  '30201',
  '30301',
  '30401',
  '30501',
  '30601',
  '30701',
  '30801',
  '30901',
  '31001',
  '31101',
  '31201',
  '31301',
  '31401',
  '31501',
  '31601',
  '31701',
  '31801',
  '31901',
  // ── Florida ───────────────────────────────────────────────────────────────
  '32004',
  '32101',
  '32201',
  '32301',
  '32401',
  '32501',
  '32601',
  '32701',
  '32801',
  '32901',
  '33101',
  '33301',
  '33401',
  '33501',
  '33601',
  '33701',
  '33801',
  '33901',
  '34101',
  '34201',
  '34401',
  '34601',
  '34701',
  '34801',
  '34901',
  // ── Alabama / Mississippi ─────────────────────────────────────────────────
  '35004',
  '35101',
  '35201',
  '35401',
  '35501',
  '35601',
  '35701',
  '35801',
  '35901',
  '36001',
  '36101',
  '36201',
  '36301',
  '36401',
  '36501',
  '36601',
  '36701',
  '36801',
  '36901',
  '39001',
  '39101',
  '39201',
  '39301',
  '39401',
  '39501',
  // ── Louisiana / Arkansas ──────────────────────────────────────────────────
  '70001',
  '70101',
  '70301',
  '70401',
  '70501',
  '70601',
  '70701',
  '70801',
  '70901',
  '71001',
  '71101',
  '71201',
  '71301',
  '71601',
  '71701',
  '71801',
  '71901',
  '72001',
  '72101',
  '72201',
  '72301',
  '72401',
  '72601',
  '72701',
  '72801',
  '72901',
  // ── Great Lakes / Northeast ───────────────────────────────────────────────
  '53001',
  '53201',
  '53401',
  '53501',
  '53601',
  '53701',
  '53901',
  '14001',
  '14101',
  '14201',
  '14301',
  '14601',
  '14701',
  '14801',
  '14901',
  '13201',
  '13301',
  '13401',
  '12001',
  '12101',
  '12201',
  '12301',
  '12401',
  '12501',
  '12601',
  '10001',
  '10301',
  '11001',
  '07001',
  '07101',
  '07201',
  '07301',
  '07401',
  '07501',
  '07601',
  '07701',
  '07801',
  '07901',
  '08001',
  '08101',
  '08201',
  '08301',
  '08401',
  '08501',
  '08601',
  '08701',
  '08801',
  '08901',
  // ── Pennsylvania ──────────────────────────────────────────────────────────
  '15001',
  '15101',
  '15201',
  '15301',
  '15401',
  '15501',
  '15601',
  '15701',
  '15801',
  '15901',
  '16001',
  '16101',
  '16201',
  '16301',
  '16401',
  '16501',
  '16601',
  '16701',
  '16801',
  '16901',
  '17001',
  '17101',
  '17201',
  '17301',
  '17401',
  '17501',
  '17601',
  '17701',
  '17801',
  '17901',
  '18001',
  '18101',
  '18201',
  '18301',
  '18401',
  '18501',
  '18601',
  '18701',
  '18801',
  '18901',
  '19001',
  '19101',
  '19201',
  '19301',
  '19401',
  // ── Maryland / Delaware / DC ──────────────────────────────────────────────
  '20001',
  '20601',
  '20701',
  '20801',
  '20901',
  '21001',
  '21101',
  '21201',
  '21301',
  '21401',
  '21501',
  '21601',
  '21701',
  '21801',
  '21901',
  '19701',
  '19801',
  '19901',
  // ── New England ───────────────────────────────────────────────────────────
  '06001',
  '06101',
  '06201',
  '06301',
  '06401',
  '06501',
  '06601',
  '06701',
  '06801',
  '06901',
  '01001',
  '01101',
  '01201',
  '01301',
  '01401',
  '01501',
  '01601',
  '01701',
  '01801',
  '01901',
  '02101',
  '02201',
  '02301',
  '02401',
  '02501',
  '02601',
  '02701',
  '02801',
  '02901',
  '03001',
  '03101',
  '03201',
  '03301',
  '03401',
  '03501',
  '03601',
  '03701',
  '03801',
  '03901',
  '04001',
  '04101',
  '04201',
  '04401',
  '04601',
  '04901',
  '05001',
  '05101',
  '05201',
  '05301',
  '05401',
  '05501',
  '05601',
  '05701',
  '05801',
  '05901',
];

// ─── Token Manager ─────────────────────────────────────────────────────────────

class TokenManager {
  constructor(clientId, clientSecret) {
    if (!clientId || !clientSecret) {
      throw new Error(
        'Missing KROGER_CLIENT_ID or KROGER_CLIENT_SECRET.\n' +
          'Set them in a .env file or as environment variables.',
      );
    }
    this.credentials = Buffer.from(`${clientId}:${clientSecret}`).toString(
      'base64',
    );
    this.accessToken = null;
    this.expiresAt = 0;
  }

  async getToken() {
    if (this.accessToken && Date.now() < this.expiresAt - 60_000)
      return this.accessToken;
    process.stdout.write('  Refreshing OAuth2 token... ');
    const res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${this.credentials}`,
      },
      body: 'grant_type=client_credentials&scope=product.compact',
    });
    if (!res.ok)
      throw new Error(
        `Token request failed (${res.status}): ${await res.text()}`,
      );
    const data = await res.json();
    this.accessToken = data.access_token;
    this.expiresAt = Date.now() + data.expires_in * 1000;
    console.log(`OK (valid ${Math.round(data.expires_in / 60)} min)`);
    return this.accessToken;
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function fetchLocationsForZip(zip, tokenMgr) {
  const params = new URLSearchParams({
    'filter.zipCode.near': zip,
    'filter.radiusInMiles': radius,
    'filter.limit': MAX_LIMIT,
  });
  if (chainArg) params.set('filter.chain', chainArg);

  const url = `${LOCATIONS_URL}?${params}`;

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    const token = await tokenMgr.getToken();
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    });

    if (res.status === 429) {
      const wait = RETRY_DELAY_MS * attempt;
      process.stdout.write(`[429 wait ${wait / 1000}s] `);
      await sleep(wait);
      continue;
    }
    if (res.status === 401) {
      tokenMgr.expiresAt = 0;
      continue;
    }
    if (!res.ok) {
      if (attempt < MAX_RETRIES) {
        await sleep(RETRY_DELAY_MS);
        continue;
      }
      throw new Error(`HTTP ${res.status} for zip ${zip}`);
    }

    const data = await res.json();
    return data?.data ?? [];
  }
  return [];
}

// Run up to `concurrency` zip-code fetches in parallel
async function processInBatches(zips, tokenMgr, allStores) {
  let done = 0;
  for (let i = 0; i < zips.length; i += concurrency) {
    const batch = zips.slice(i, i + concurrency);
    const results = await Promise.all(
      batch.map(async (zip) => {
        try {
          return await fetchLocationsForZip(zip, tokenMgr);
        } catch (err) {
          console.error(`\n  Error for zip ${zip}: ${err.message}`);
          return [];
        }
      }),
    );

    let newInBatch = 0;
    for (const stores of results) {
      for (const s of stores) {
        if (!allStores.has(s.locationId)) {
          allStores.set(s.locationId, s);
          newInBatch++;
        }
      }
    }
    done += batch.length;

    // Progress bar
    const pct = Math.round((done / zips.length) * 100);
    const bar =
      '█'.repeat(Math.floor(pct / 5)) + '░'.repeat(20 - Math.floor(pct / 5));
    process.stdout.write(
      `\r  [${bar}] ${pct}% | ${done}/${zips.length} zips | ${allStores.size} unique stores found`,
    );
  }
  process.stdout.write('\n');
}

// ─── CSV ───────────────────────────────────────────────────────────────────────

function esc(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return s.includes(',') || s.includes('"') || s.includes('\n')
    ? `"${s.replace(/"/g, '""')}"`
    : s;
}

const HEADERS = [
  'locationId',
  'name',
  'chain',
  'phone',
  'address_line1',
  'address_line2',
  'address_city',
  'address_state',
  'address_zipCode',
  'address_county',
  'geo_latitude',
  'geo_longitude',
  'hours_timezone',
  'hours_gmtOffset',
  'hours_open24',
  'hours_monday_open',
  'hours_monday_close',
  'hours_monday_open24',
  'hours_tuesday_open',
  'hours_tuesday_close',
  'hours_tuesday_open24',
  'hours_wednesday_open',
  'hours_wednesday_close',
  'hours_wednesday_open24',
  'hours_thursday_open',
  'hours_thursday_close',
  'hours_thursday_open24',
  'hours_friday_open',
  'hours_friday_close',
  'hours_friday_open24',
  'hours_saturday_open',
  'hours_saturday_close',
  'hours_saturday_open24',
  'hours_sunday_open',
  'hours_sunday_close',
  'hours_sunday_open24',
  'departments_count',
  'departments_names',
  'departments_ids',
  'departments_json',
];

const DAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

function storeToRow(s) {
  const addr = s.address ?? {};
  const geo = s.geolocation ?? {};
  const hrs = s.hours ?? {};
  const deps = s.departments ?? [];

  const dayFields = DAYS.flatMap((day) => {
    const d = hrs[day] ?? {};
    return [d.open ?? '', d.close ?? '', d.open24 ?? ''];
  });

  return [
    s.locationId,
    s.name,
    s.chain,
    s.phone,
    addr.addressLine1,
    addr.addressLine2,
    addr.city,
    addr.state,
    addr.zipCode,
    addr.county,
    geo.latitude,
    geo.longitude,
    hrs.timezone,
    hrs.gmtOffset,
    hrs.open24,
    ...dayFields,
    deps.length,
    deps.map((d) => d.name).join('; '),
    deps.map((d) => d.departmentId).join('; '),
    JSON.stringify(deps),
  ]
    .map(esc)
    .join(',');
}

// ─── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const tokenMgr = new TokenManager(
    process.env.KROGER_CLIENT_ID,
    process.env.KROGER_CLIENT_SECRET,
  );

  if (!fs.existsSync(storesDir)) fs.mkdirSync(storesDir, { recursive: true });

  // De-duplicate zip codes
  const zips = [...new Set(GRID_ZIPS)];
  const queryZips = isDryRun ? zips.slice(0, 10) : zips;

  console.log('\nKroger Store Scraper');
  console.log(
    `  Strategy   : zip-code grid sweep (${queryZips.length} zip codes × ${radius}-mile radius)`,
  );
  console.log(`  Concurrency: ${concurrency} parallel requests`);
  console.log(`  Chain filter: ${chainArg || '(all chains)'}`);
  console.log(`  Output dir : ${path.resolve(storesDir)}`);
  console.log(
    `  Dry run    : ${isDryRun}${isDryRun ? ' (first 10 zips only)' : ''}\n`,
  );

  const allStores = new Map(); // locationId → store object

  await processInBatches(queryZips, tokenMgr, allStores);

  if (allStores.size === 0) {
    console.log(
      '  No stores found. Check credentials or try --chain with a different value.',
    );
    process.exit(0);
  }

  const storeList = Array.from(allStores.values()).sort(
    (a, b) =>
      (a.chain ?? '').localeCompare(b.chain ?? '') ||
      (a.locationId ?? '').localeCompare(b.locationId ?? ''),
  );

  // ── Write main CSV ─────────────────────────────────────────────────────────
  const csvPath = path.join(storesDir, 'kroger_stores.csv');
  fs.writeFileSync(
    csvPath,
    [HEADERS.join(','), ...storeList.map(storeToRow)].join('\n'),
    'utf8',
  );
  console.log(
    `\n  Saved ${storeList.length.toLocaleString()} stores  →  ${csvPath}`,
  );

  // ── Per-chain CSVs ─────────────────────────────────────────────────────────
  const byChain = new Map();
  for (const s of storeList) {
    const key = (s.chain ?? 'UNKNOWN').replace(/[^a-zA-Z0-9_]/g, '_');
    if (!byChain.has(key)) byChain.set(key, []);
    byChain.get(key).push(s);
  }

  const chainDir = path.join(storesDir, 'by_chain');
  if (!fs.existsSync(chainDir)) fs.mkdirSync(chainDir);
  for (const [chain, chainStores] of byChain) {
    fs.writeFileSync(
      path.join(chainDir, `${chain}.csv`),
      [HEADERS.join(','), ...chainStores.map(storeToRow)].join('\n'),
      'utf8',
    );
  }
  console.log(`  Per-chain CSVs  →  ${chainDir}/`);

  // ── Summary ────────────────────────────────────────────────────────────────
  const sorted = [...byChain].sort((a, b) => b[1].length - a[1].length);
  const summaryLines = [
    'chain,store_count',
    ...sorted.map(([c, arr]) => `${esc(c)},${arr.length}`),
    `TOTAL,${storeList.length}`,
  ];
  fs.writeFileSync(
    path.join(storesDir, 'stores_summary.csv'),
    summaryLines.join('\n'),
    'utf8',
  );

  console.log(`\n  Chain breakdown:`);
  for (const [chain, arr] of sorted) {
    console.log(`    ${arr.length.toString().padStart(5)}  ${chain}`);
  }
  console.log(`    ${'─'.repeat(20)}`);
  console.log(`    ${storeList.length.toString().padStart(5)}  TOTAL\n`);
}

main().catch((err) => {
  console.error(`\nFatal error: ${err.message}`);
  process.exit(1);
});
