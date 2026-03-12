/**
 * kroger_catalogue.js
 *
 * Finds Kroger stores near a zip code, searches all food categories at
 * each store, and writes the results to food_catalogue.csv.
 *
 * Each product gets a price column (semicolon-separated) that matches the
 * store_ids column order - so price[0] is the price at store_ids[0], etc.
 *
 * Usage:
 *   node kroger_catalogue.js --zipcode=90210
 *   node kroger_catalogue.js --zipcode=90210 --stores=5
 *   node kroger_catalogue.js --zipcode=90210 --dry-run
 *
 * Flags:
 *   --zipcode=XXXXX   (required) zip code to find stores near
 *   --stores=10       max stores to query (default: 10, or "all")
 *   --radius=25       search radius in miles (default: 25)
 *   --dry-run         only do 3 terms per category, good for testing
 *   --status          print catalogue stats and exit
 */

import dotenv from 'dotenv';
dotenv.config();
import fetch from 'node-fetch';
import fs from 'fs';
import path from 'path';
import readline from 'readline';

// --- Configuration ---
const BASE_URL = 'https://api.kroger.com/v1';
const TOKEN_URL = `${BASE_URL}/connect/oauth2/token`;
const PRODUCTS_URL = `${BASE_URL}/products`;
const LOCATIONS_URL = `${BASE_URL}/locations`;

const PAGE_LIMIT = 50;
const MAX_PAGES = 20;
const REQUEST_DELAY_MS = 350;
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 2000;

// --- CLI Args ---
const args = process.argv.slice(2);
function getArg(prefix) {
  return (
    (args.find((a) => a.startsWith(prefix)) ?? '').replace(prefix, '') || ''
  );
}

const outRoot = getArg('--out=') || './kroger_output';
const zipcodeArg = getArg('--zipcode=');
const storesArg = getArg('--stores='); // number or "all"
const radiusArg = parseInt(getArg('--radius=') || '25', 10);
const categoryFilter = getArg('--categories=');
const isDryRun = args.includes('--dry-run');
const statusOnly = args.includes('--status');

const catalogueDir = path.join(outRoot, 'catalogue');
const catalogueFile = path.join(catalogueDir, 'food_catalogue.csv');

const maxStores =
  storesArg === 'all' ? Infinity : parseInt(storesArg || '10', 10);

// --- Food Categories ---
// --- Search Terms - aligned with Walmart pipeline classifier tags ---
// Keys ARE the classifier tags written to the CSV `classifier` column.
// Terms are drawn directly from the INGREDIENT_RULES keyword sets in the
// Walmart classifier, pruned to terms broad enough to return Kroger results.

const FOOD_CATEGORIES = {
  PRODUCE: [
    'fresh vegetable',
    'fresh fruit',
    'organic vegetable',
    'organic fruit',
    'broccoli',
    'cauliflower',
    'spinach',
    'kale',
    'romaine',
    'mixed greens',
    'brussels sprout',
    'cabbage',
    'carrot',
    'celery',
    'cucumber',
    'zucchini',
    'bell pepper',
    'jalapeño',
    'cherry tomato',
    'roma tomato',
    'red onion',
    'yellow onion',
    'shallot',
    'scallion',
    'leek',
    'garlic bulb',
    'portobello',
    'shiitake',
    'cremini mushroom',
    'asparagus',
    'artichoke',
    'beet',
    'turnip',
    'parsnip',
    'sweet potato',
    'russet potato',
    'red potato',
    'yukon gold',
    'corn on cob',
    'green bean',
    'snap pea',
    'snow pea',
    'eggplant',
    'fennel',
    'radish',
    'apple',
    'pear',
    'orange',
    'lemon',
    'lime',
    'banana',
    'mango',
    'pineapple',
    'papaya',
    'kiwi',
    'strawberry',
    'blueberry',
    'raspberry',
    'blackberry',
    'watermelon',
    'cantaloupe',
    'peach',
    'nectarine',
    'plum',
    'cherry',
    'avocado',
    'pomegranate',
  ],

  FRESH_HERB: [
    'fresh basil',
    'fresh parsley',
    'fresh cilantro',
    'fresh thyme',
    'fresh rosemary',
    'fresh mint',
    'fresh dill',
    'fresh chives',
    'fresh tarragon',
    'fresh oregano',
    'fresh sage',
    'fresh lemongrass',
    'fresh ginger root',
  ],

  PROTEIN: [
    'chicken breast',
    'chicken thigh',
    'chicken wing',
    'chicken drumstick',
    'ground chicken',
    'whole chicken',
    'ground turkey',
    'turkey breast',
    'ground beef',
    'beef chuck',
    'beef brisket',
    'ribeye',
    'sirloin',
    'flank steak',
    'skirt steak',
    'beef roast',
    'beef short rib',
    'pork chop',
    'pork loin',
    'pork belly',
    'pork shoulder',
    'pork tenderloin',
    'baby back rib',
    'spiral ham',
    'ham steak',
    'lamb chop',
    'lamb leg',
    'ground lamb',
    'salmon fillet',
    'tuna fillet',
    'tilapia',
    'cod fillet',
    'halibut',
    'mahi mahi',
    'sea bass',
    'trout',
    'catfish',
    'shrimp',
    'scallop',
    'lobster tail',
    'crab leg',
    'crab meat',
    'clam',
    'mussel',
    'oyster',
    'bacon',
    'pancetta',
    'prosciutto',
    'salami',
    'pepperoni',
    'chorizo',
    'andouille',
    'bratwurst',
    'italian sausage',
    'breakfast sausage',
    'deli turkey',
    'deli ham',
    'deli roast beef',
    'deli chicken',
    'lunch meat',
    'extra firm tofu',
    'silken tofu',
    'tempeh',
    'seitan',
    'edamame',
    'black bean',
    'pinto bean',
    'kidney bean',
    'chickpea',
    'lentil',
    'split pea',
    'navy bean',
    'cannellini bean',
    'large eggs',
    'cage free egg',
    'organic egg',
    'egg whites',
  ],

  DAIRY: [
    'whole milk',
    'skim milk',
    '2% milk',
    'lactose free milk',
    'organic milk',
    'buttermilk',
    'evaporated milk',
    'condensed milk',
    'powdered milk',
    'heavy cream',
    'heavy whipping cream',
    'half and half',
    'light cream',
    'sour cream',
    'creme fraiche',
    'cream cheese',
    'mascarpone',
    'ricotta',
    'cottage cheese',
    'fresh mozzarella',
    'burrata',
    'cheddar cheese',
    'parmesan',
    'romano cheese',
    'asiago',
    'gruyere',
    'swiss cheese',
    'gouda',
    'havarti',
    'fontina',
    'provolone',
    'brie',
    'camembert',
    'gorgonzola',
    'blue cheese',
    'feta cheese',
    'queso fresco',
    'monterey jack',
    'pepper jack',
    'unsalted butter',
    'salted butter',
    'european butter',
    'ghee',
    'greek yogurt',
    'plain yogurt',
    'whole milk yogurt',
    'skyr',
    'kefir',
  ],

  GRAIN: [
    'all purpose flour',
    'bread flour',
    'whole wheat flour',
    'cake flour',
    'almond flour',
    'coconut flour',
    'oat flour',
    'rye flour',
    'chickpea flour',
    'rice flour',
    'cassava flour',
    'white rice',
    'brown rice',
    'jasmine rice',
    'basmati rice',
    'arborio rice',
    'wild rice',
    'spaghetti',
    'penne',
    'rigatoni',
    'fusilli',
    'farfalle',
    'linguine',
    'fettuccine',
    'angel hair',
    'orzo',
    'macaroni',
    'lasagna noodle',
    'egg noodle',
    'ramen noodle',
    'soba noodle',
    'udon noodle',
    'rice noodle',
    'rolled oats',
    'quick oats',
    'steel cut oats',
    'cornmeal',
    'polenta',
    'grits',
    'semolina',
    'panko',
    'plain breadcrumb',
    'sandwich bread',
    'whole wheat bread',
    'sourdough bread',
    'french bread',
    'pita bread',
    'naan',
    'flatbread',
    'flour tortilla',
    'corn tortilla',
    'quinoa',
    'farro',
    'bulgur',
    'couscous',
    'barley',
    'millet',
  ],

  BAKING: [
    'baking soda',
    'baking powder',
    'cream of tartar',
    'active dry yeast',
    'instant yeast',
    'vanilla extract',
    'almond extract',
    'peppermint extract',
    'cocoa powder',
    'dutch process cocoa',
    'chocolate chips',
    'white chocolate chips',
    'baking chocolate',
    'powdered sugar',
    'granulated sugar',
    'cane sugar',
    'brown sugar',
    'turbinado sugar',
    'demerara sugar',
    'corn syrup',
    'molasses',
    'cake mix',
    'brownie mix',
    'pancake mix',
    'waffle mix',
    'muffin mix',
  ],

  SPICE: [
    'black pepper',
    'white pepper',
    'peppercorn',
    'sea salt',
    'kosher salt',
    'himalayan salt',
    'garlic salt',
    'garlic powder',
    'onion powder',
    'cumin',
    'paprika',
    'smoked paprika',
    'chili powder',
    'cayenne',
    'red pepper flake',
    'cinnamon',
    'nutmeg',
    'oregano',
    'thyme',
    'rosemary',
    'basil dried',
    'bay leaf',
    'turmeric',
    'coriander',
    'fennel seed',
    'cardamom',
    'clove',
    'allspice',
    'ground ginger',
    'mustard seed',
    'ground mustard',
    'fenugreek',
    'sumac',
    "za'atar",
    'herbs de provence',
    'italian seasoning',
    'cajun seasoning',
    'taco seasoning',
    'curry powder',
    'garam masala',
    'ras el hanout',
    'five spice',
    'lemon pepper',
    'steak seasoning',
    'bbq rub',
    'vanilla bean',
    'saffron',
    'dill weed',
    'marjoram',
  ],

  OIL_FAT: [
    'olive oil',
    'extra virgin olive oil',
    'vegetable oil',
    'canola oil',
    'sunflower oil',
    'safflower oil',
    'corn oil',
    'soybean oil',
    'peanut oil',
    'grapeseed oil',
    'avocado oil',
    'coconut oil',
    'sesame oil',
    'toasted sesame oil',
    'walnut oil',
    'flaxseed oil',
    'truffle oil',
    'cooking spray',
    'nonstick spray',
    'shortening',
    'lard',
    'duck fat',
    'beef tallow',
    'vegan butter',
  ],

  CONDIMENT: [
    'soy sauce',
    'tamari',
    'liquid aminos',
    'coconut aminos',
    'fish sauce',
    'oyster sauce',
    'hoisin sauce',
    'worcestershire sauce',
    'hot sauce',
    'sriracha',
    'tabasco',
    'cholula',
    'sambal oelek',
    'gochujang',
    'apple cider vinegar',
    'white vinegar',
    'red wine vinegar',
    'white wine vinegar',
    'balsamic vinegar',
    'rice vinegar',
    'malt vinegar',
    'dijon mustard',
    'whole grain mustard',
    'yellow mustard',
    'ketchup',
    'mayonnaise',
    'relish',
    'bbq sauce',
    'barbecue sauce',
    'steak sauce',
    'buffalo sauce',
    'teriyaki sauce',
    'ponzu sauce',
    'sweet chili sauce',
    'stir fry sauce',
    'tahini',
    'miso paste',
    'tomato paste',
    'marinara sauce',
    'pasta sauce',
    'alfredo sauce',
    'pesto',
    'enchilada sauce',
    'salsa verde',
    'salsa jar',
    'pickle',
    'dill pickle',
    'pickled jalapeno',
    'giardiniera',
    'capers',
    'sun dried tomato',
    'roasted red pepper',
    'horseradish',
    'wasabi paste',
  ],

  CANNED_GOOD: [
    'canned tomato',
    'diced tomato',
    'crushed tomato',
    'whole peeled tomato',
    'san marzano',
    'fire roasted tomato',
    'canned black bean',
    'canned chickpea',
    'canned kidney bean',
    'canned pinto bean',
    'canned navy bean',
    'canned cannellini',
    'canned corn',
    'canned pumpkin',
    'canned artichoke',
    'canned mushroom',
    'canned water chestnut',
    'canned green bean',
    'coconut milk can',
    'coconut cream',
    'chicken broth',
    'beef broth',
    'vegetable broth',
    'chicken stock',
    'beef stock',
    'bone broth',
    'canned tuna',
    'canned salmon',
    'canned sardine',
    'canned anchovy',
    'canned crab',
    'canned clam',
    'chipotle in adobo',
    'green chili can',
  ],

  SWEETENER: [
    'honey',
    'raw honey',
    'manuka honey',
    'maple syrup',
    'pure maple syrup',
    'agave nectar',
    'date syrup',
    'stevia',
    'monk fruit sweetener',
    'erythritol',
  ],

  NUT_SEED: [
    'raw almonds',
    'sliced almonds',
    'slivered almonds',
    'walnut halves',
    'pecans',
    'cashews',
    'pistachios',
    'pine nuts',
    'hazelnuts',
    'macadamia nut',
    'brazil nut',
    'peanut butter',
    'almond butter',
    'cashew butter',
    'sunflower seed',
    'pumpkin seed',
    'pepita',
    'sesame seed',
    'chia seed',
    'flaxseed',
    'hemp seed',
    'poppy seed',
  ],

  THICKENER: [
    'cornstarch',
    'arrowroot powder',
    'tapioca starch',
    'unflavored gelatin',
    'agar agar',
    'xanthan gum',
    'guar gum',
    'pectin',
  ],

  ALCOHOL: [
    'cooking wine',
    'dry sherry',
    'mirin',
    'sake',
    'rice wine',
    'shaoxing wine',
  ],

  OTHER_INGR: [
    'nutritional yeast',
    'dried mushroom',
    'nori sheet',
    'kombu',
    'wakame',
    'dashi',
    'bonito flake',
    'matcha powder',
    'rose water',
    'liquid smoke',
    'raisins',
    'dried cranberry',
    'dried apricot',
    'dried fig',
    'dried mango',
    'dried date',
    'canned peach',
    'canned pear',
    'canned pineapple',
    'lemon juice',
    'lime juice',
    'jam',
    'jelly',
    'fruit preserves',
    'marmalade',
    'chutney',
    'caramel sauce',
    'sweetened condensed milk',
    'cream of mushroom soup',
    'cream of chicken soup',
    'harissa',
    'red curry paste',
    'green curry paste',
    'yellow curry paste',
    'coconut butter',
    'cacao nibs',
    'vital wheat gluten',
    'citric acid',
  ],
};

// --- CSV Schema ---
const CSV_HEADERS = [
  'productId',
  'upc',
  'brand',
  'description',
  'categories',
  'size',
  'soldBy',
  'temperature',
  'soldInStore',
  'countryOrigin',
  'aisleLocations',
  'itemsFacets',
  'image_url',
  'classifier', // ← Walmart classifier tag (PRODUCE, PROTEIN, DAIRY, etc.)
  'search_keyword', // ← the specific term that first found this product
  'store_ids', // ← semicolon-separated locationIds (in order found)
  'price', // ← semicolon-separated prices matching store_ids order
];

// --- Token Manager ---
class TokenManager {
  constructor(clientId, clientSecret) {
    if (!clientId || !clientSecret)
      throw new Error(
        'Missing KROGER_CLIENT_ID or KROGER_CLIENT_SECRET in .env',
      );
    this.credentials = Buffer.from(`${clientId}:${clientSecret}`).toString(
      'base64',
    );
    this.accessToken = null;
    this.expiresAt = 0;
  }

  async getToken() {
    if (this.accessToken && Date.now() < this.expiresAt - 60_000)
      return this.accessToken;
    process.stdout.write('  Refreshing token... ');
    const res = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Authorization: `Basic ${this.credentials}`,
      },
      body: 'grant_type=client_credentials&scope=product.compact',
    });
    if (!res.ok)
      throw new Error(`Token failed (${res.status}): ${await res.text()}`);
    const data = await res.json();
    this.accessToken = data.access_token;
    this.expiresAt = Date.now() + data.expires_in * 1000;
    console.log(`OK (${Math.round(data.expires_in / 60)} min)`);
    return this.accessToken;
  }
}

// --- Helpers ---
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function esc(v) {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return s.includes(',') || s.includes('"') || s.includes('\n')
    ? `"${s.replace(/"/g, '""')}"`
    : s;
}

function parseCsvLine(line) {
  const cols = [];
  let cur = '',
    inQ = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (inQ && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else inQ = !inQ;
    } else if (ch === ',' && !inQ) {
      cols.push(cur);
      cur = '';
    } else cur += ch;
  }
  cols.push(cur);
  return cols;
}

async function* streamCsvRows(filePath) {
  const rl = readline.createInterface({
    input: fs.createReadStream(filePath),
    crlfDelay: Infinity,
  });
  let headers = null;
  for await (const line of rl) {
    if (!line.trim()) continue;
    const cols = parseCsvLine(line);
    if (!headers) {
      headers = cols;
      continue;
    }
    const row = {};
    headers.forEach((h, i) => {
      row[h] = cols[i] ?? '';
    });
    yield row;
  }
}

function productToFields(p, classifier = '', searchKeyword = '') {
  const items = p.items?.[0] ?? {};
  const frontImg = (p.images ?? []).find(
    (img) => img.perspective === 'front' && img.featured,
  );
  const imgUrl = frontImg
    ? ((frontImg.sizes ?? []).find((s) => s.id === 'large')?.url ??
      frontImg.sizes?.[0]?.url ??
      '')
    : '';

  return {
    productId: p.productId ?? '',
    upc: p.upc ?? '',
    brand: p.brand ?? '',
    description: p.description ?? '',
    categories: (p.categories ?? []).join('; '),
    size: items.size ?? '',
    soldBy: items.soldBy ?? '',
    temperature: items.temperature?.indicator ?? '',
    soldInStore: items.soldInStore ?? '',
    countryOrigin: p.countryOrigin ?? '',
    aisleLocations: (p.aisleLocations ?? [])
      .map((a) => a.description)
      .join('; '),
    itemsFacets: (p.itemsFacets ?? []).join('; '),
    image_url: imgUrl,
    classifier: classifier, // e.g. PRODUCE, PROTEIN, DAIRY …
    search_keyword: searchKeyword, // e.g. "chicken breast", "raw almonds" …
    store_ids: '', // filled in per store during collection
    price: '', // filled in per store during collection
  };
}

function rowToCsv(row) {
  return CSV_HEADERS.map((h) => esc(row[h])).join(',');
}

// --- API: Fetch products for a single search term ---
async function fetchProductsForTerm(term, locationId, tokenMgr, dryRun) {
  const products = [];
  const maxPages = dryRun ? 1 : MAX_PAGES;

  for (let page = 0; page < maxPages; page++) {
    const params = new URLSearchParams({
      'filter.term': term,
      'filter.limit': PAGE_LIMIT,
    });
    // Only send filter.start for pages after the first - some Kroger
    // endpoints reject start=1 even though it should be a valid value
    if (page > 0) params.set('filter.start', page * PAGE_LIMIT + 1);
    if (locationId) params.set('filter.locationId', locationId);

    let token = await tokenMgr.getToken();
    let data;
    let pageOk = false;

    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      let res;
      try {
        res = await fetch(`${PRODUCTS_URL}?${params}`, {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: 'application/json',
          },
        });
      } catch (networkErr) {
        if (attempt < MAX_RETRIES) {
          await sleep(RETRY_DELAY_MS * attempt);
          continue;
        }
        throw networkErr;
      }

      if (res.status === 400) {
        // Bad request - Kroger rejects certain terms or parameter combos.
        // Not retryable; skip this term entirely.
        const body = await res.text().catch(() => '');
        throw Object.assign(
          new Error(
            `Skipped (400 Bad Request)${body ? ': ' + body.slice(0, 120) : ''}`,
          ),
          { code: 'BAD_REQUEST' },
        );
      }

      if (res.status === 401) {
        tokenMgr.expiresAt = 0;
        token = await tokenMgr.getToken();
        continue;
      }

      if (res.status === 429) {
        const wait = RETRY_DELAY_MS * attempt;
        process.stdout.write(`[rate-limited, waiting ${wait / 1000}s] `);
        await sleep(wait);
        continue;
      }

      if (res.status === 500 || res.status === 503) {
        if (attempt < MAX_RETRIES) {
          await sleep(RETRY_DELAY_MS * attempt);
          continue;
        }
        throw new Error(
          `Server error ${res.status} after ${MAX_RETRIES} retries`,
        );
      }

      if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new Error(`HTTP ${res.status}: ${body.slice(0, 120)}`);
      }

      data = await res.json();
      pageOk = true;
      break;
    }

    if (!pageOk) break;

    const items = data?.data ?? [];
    products.push(...items);
    if (items.length < PAGE_LIMIT) break;
    await sleep(REQUEST_DELAY_MS);
  }

  return products;
}

// --- API: Look up stores near a zip code ---
async function fetchStoresNearZip(zip, tokenMgr) {
  // Validate zip
  if (!/^\d{5}$/.test(zip)) {
    throw new Error(`"${zip}" is not a valid 5-digit zip code`);
  }

  const params = new URLSearchParams({
    'filter.zipCode.near': zip,
    'filter.radiusInMiles': Math.min(radiusArg, 100),
    'filter.limit': 200,
  });

  const token = await tokenMgr.getToken();
  const res = await fetch(`${LOCATIONS_URL}?${params}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
  });
  if (!res.ok)
    throw new Error(
      `Location lookup failed (${res.status}): ${await res.text()}`,
    );

  const data = await res.json();
  const stores = (data?.data ?? []).slice(
    0,
    maxStores === Infinity ? undefined : maxStores,
  );

  if (stores.length === 0) {
    throw new Error(
      `No stores found within ${radiusArg} miles of ${zip}. Try --radius=50`,
    );
  }

  return stores.map((s) => ({
    locationId: s.locationId,
    name: s.name ?? '',
    chain: s.chain ?? '',
    address:
      `${s.address?.addressLine1 ?? ''}, ${s.address?.city ?? ''}, ${s.address?.state ?? ''} ${s.address?.zipCode ?? ''}`.trim(),
  }));
}

// --- Catalogue I/O ---
/** Load existing catalogue CSV into a Map: productId -> row object */
async function loadCatalogue() {
  const catalogue = new Map();
  if (!fs.existsSync(catalogueFile)) return catalogue;

  for await (const row of streamCsvRows(catalogueFile)) {
    if (row.productId) catalogue.set(row.productId, row);
  }
  return catalogue;
}

/** Write the full catalogue Map to disk */
function saveCatalogue(catalogue) {
  const header = CSV_HEADERS.join(',');
  const rows = Array.from(catalogue.values()).map(rowToCsv);
  fs.writeFileSync(catalogueFile, [header, ...rows].join('\n'), 'utf8');
}

// --- Core: Run search terms and collect results ---
async function runSearchTerms(locationId, tokenMgr) {
  const categoryKeys = categoryFilter
    ? categoryFilter
        .split(',')
        .map((s) => s.trim())
        .filter((k) => FOOD_CATEGORIES[k])
    : Object.keys(FOOD_CATEGORIES);

  // productId -> { product, classifier, search_keyword }
  const results = new Map();

  for (const classifier of categoryKeys) {
    let terms = FOOD_CATEGORIES[classifier];
    if (isDryRun) terms = terms.slice(0, 3);

    process.stdout.write(`\n  [${classifier}]\n`);

    for (const term of terms) {
      process.stdout.write(`    "${term}" ... `);
      try {
        const products = await fetchProductsForTerm(
          term,
          locationId,
          tokenMgr,
          isDryRun,
        );
        let newCount = 0;
        for (const p of products) {
          if (p.productId && !results.has(p.productId)) {
            // Tag with the classifier and exact term that first found this product
            results.set(p.productId, {
              product: p,
              classifier,
              search_keyword: term,
            });
            newCount++;
          }
        }
        process.stdout.write(`${products.length} fetched, ${newCount} new\n`);
        await sleep(REQUEST_DELAY_MS);
      } catch (err) {
        if (err.code === 'BAD_REQUEST') {
          process.stdout.write(`skipped (400)\n`);
        } else {
          process.stdout.write(`ERROR: ${err.message}\n`);
        }
        await sleep(REQUEST_DELAY_MS * 2);
      }
    }
  }

  return results;
}

// --- Status ---
async function printStatus() {
  if (!fs.existsSync(catalogueFile)) {
    console.log(
      '\n  No catalogue found yet. Run with --zipcode to build one.\n',
    );
    return;
  }

  const catalogue = await loadCatalogue();
  const storeIdSet = new Set();
  let withStores = 0;

  for (const row of catalogue.values()) {
    if (row.store_ids) {
      withStores++;
      row.store_ids
        .split(';')
        .map((s) => s.trim())
        .filter(Boolean)
        .forEach((id) => storeIdSet.add(id));
    }
  }

  console.log(`\nCatalogue Status`);
  console.log(`  File             : ${catalogueFile}`);
  console.log(`  Total products   : ${catalogue.size.toLocaleString()}`);
  console.log(`  With store data  : ${withStores.toLocaleString()} products`);
  console.log(
    `  Stores indexed   : ${storeIdSet.size.toLocaleString()} unique store IDs`,
  );
  console.log(
    `  Coverage         : ${catalogue.size ? Math.round((withStores / catalogue.size) * 100) : 0}% of products have at least 1 store\n`,
  );
}

// finds stores near a zip, queries each one, and compiles the results into food_catalogue.csv
// price[i] corresponds to store_ids[i] - they're kept in the same order
async function buildCatalogue(tokenMgr) {
  const zip = zipcodeArg;
  console.log(`\nBuilding food catalogue for stores near ${zip}`);
  console.log(`  Output: ${catalogueFile}`);
  if (isDryRun) console.log(`  Dry run: 3 terms per category only\n`);

  // 1. Find stores near zip
  console.log(`\n  Finding stores within ${radiusArg} miles of ${zip}...`);
  const stores = await fetchStoresNearZip(zip, tokenMgr);

  const storeLimit =
    maxStores === Infinity ? stores.length : Math.min(maxStores, stores.length);
  console.log(
    `\n  Found ${stores.length} store(s) - querying ${storeLimit}:\n`,
  );
  stores.slice(0, storeLimit).forEach((s, i) => {
    console.log(
      `    ${String(i + 1).padStart(2)}. [${s.locationId}] ${s.name} (${s.chain})`,
    );
    console.log(`        ${s.address}`);
  });

  // 2. Load any existing catalogue so a crashed run can be resumed
  const catalogue = await loadCatalogue();
  if (catalogue.size > 0) {
    console.log(
      `\n  Resuming from existing catalogue (${catalogue.size.toLocaleString()} products already saved).`,
    );
  }

  let totalNew = 0,
    totalUpdated = 0;

  // 3. Query each store and record price + store_id together
  for (let i = 0; i < storeLimit; i++) {
    const store = stores[i];
    console.log(
      `\n  [${i + 1}/${storeLimit}] Searching store [${store.locationId}] ${store.name}...`,
    );

    const storeProducts = await runSearchTerms(store.locationId, tokenMgr);

    let newThisStore = 0,
      updatedThisStore = 0;

    for (const [
      productId,
      { product: p, classifier, search_keyword },
    ] of storeProducts) {
      const price = String(p.items?.[0]?.price?.regular ?? '');

      if (catalogue.has(productId)) {
        // already seen from an earlier store - append this store's id and price
        const row = catalogue.get(productId);
        const existingStores = row.store_ids
          ? row.store_ids.split(';').filter(Boolean)
          : [];
        if (!existingStores.includes(store.locationId)) {
          row.store_ids = [...existingStores, store.locationId].join(';');
          row.price = row.price ? `${row.price};${price}` : price;
        }
        updatedThisStore++;
      } else {
        // first time we've seen this product
        const fields = productToFields(p, classifier, search_keyword);
        fields.store_ids = store.locationId;
        fields.price = price;
        catalogue.set(productId, fields);
        newThisStore++;
      }
    }

    totalNew += newThisStore;
    totalUpdated += updatedThisStore;

    console.log(
      `\n  Store [${store.locationId}] done: ${storeProducts.size.toLocaleString()} products, ${newThisStore.toLocaleString()} new, ${updatedThisStore.toLocaleString()} updated`,
    );

    // save after every store so we don't lose progress if something crashes
    saveCatalogue(catalogue);
    console.log(
      `  Catalogue saved (${catalogue.size.toLocaleString()} total products)`,
    );
  }

  console.log(
    `\n-- Done -------------------------------------------------------------------`,
  );
  console.log(`  Stores searched   : ${storeLimit}`);
  console.log(`  New products      : ${totalNew.toLocaleString()}`);
  console.log(`  Updated products  : ${totalUpdated.toLocaleString()}`);
  console.log(`  Total in catalogue: ${catalogue.size.toLocaleString()}`);
  console.log(`  Saved to: ${catalogueFile}\n`);
}

// --- Main ---
async function main() {
  if (!fs.existsSync(catalogueDir))
    fs.mkdirSync(catalogueDir, { recursive: true });

  if (statusOnly) {
    await printStatus();
    return;
  }

  if (!zipcodeArg) {
    console.error('\n  Error: --zipcode=XXXXX is required.\n');
    console.error('  Example: node kroger_catalogue.js --zipcode=90210\n');
    process.exit(1);
  }

  const tokenMgr = new TokenManager(
    process.env.KROGER_CLIENT_ID,
    process.env.KROGER_CLIENT_SECRET,
  );

  await buildCatalogue(tokenMgr);
}

main().catch((err) => {
  console.error(`\nFatal error: ${err.message}`);
  process.exit(1);
});
