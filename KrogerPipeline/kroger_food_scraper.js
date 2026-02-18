/**
 * kroger_food_scraper.js
 *
 * Pulls food-related products from the Kroger Public API and saves them
 * to CSV files split by food category.
 *
 * SETUP:
 *   npm install node-fetch@2 dotenv
 *
 *   Create a .env file (or export env vars) with:
 *     KROGER_CLIENT_ID=your_client_id
 *     KROGER_CLIENT_SECRET=your_client_secret
 *     KROGER_LOCATION_ID=          ← optional: hard-code a specific store ID
 *
 *   Register at: https://developer.kroger.com  |  Scope needed: product.compact
 *
 * USAGE:
 *   node kroger_food_scraper.js [flags]
 *
 * FLAGS:
 *   --zipcode=90210        Look up the nearest Kroger store and use its ID
 *   --radius=15            Search radius in miles for zipcode lookup (default: 10)
 *   --location=XXXXXXXX   Hard-code an 8-char store ID (skips zipcode lookup)
 *   --dry-run              Fetch only the first page per term (quick test)
 *   --categories=a,b,c    Comma-separated subset of categories to run
 *   --out=./my-output      Output directory (default: ./kroger_output)
 *
 * PRIORITY: --location > --zipcode > KROGER_LOCATION_ID env var
 *
 * EXAMPLES:
 *   node kroger_food_scraper.js --zipcode=30301
 *   node kroger_food_scraper.js --zipcode=10001 --radius=20 --dry-run
 *   node kroger_food_scraper.js --zipcode=77001 --categories=produce,dairy_eggs
 *   node kroger_food_scraper.js --location=01400413
 */

import "dotenv/config";
import fetch from "node-fetch";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ─── Configuration ─────────────────────────────────────────────────────────────

const BASE_URL      = "https://api.kroger.com/v1";
const TOKEN_URL     = `${BASE_URL}/connect/oauth2/token`;
const PRODUCTS_URL  = `${BASE_URL}/products`;
const LOCATIONS_URL = `${BASE_URL}/locations`;

const PAGE_LIMIT       = 50;    // max results per Kroger API page
const MAX_PAGES        = 20;    // 20 × 50 = 1,000 results per search term
const REQUEST_DELAY_MS = 350;   // pause between requests to stay under rate limits
const MAX_RETRIES      = 3;
const RETRY_DELAY_MS   = 2000;

// ─── CLI Args ──────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);

function getArg(prefix) {
  return (args.find((a) => a.startsWith(prefix)) ?? "").replace(prefix, "") || "";
}

const isDryRun        = args.includes("--dry-run");
const outDir          = getArg("--out=")        || "./kroger_output";
const locationArgRaw  = getArg("--location=");
const zipcodeArg      = getArg("--zipcode=");
const radiusArg       = parseInt(getArg("--radius=") || "10", 10);
const categoryFilter  = getArg("--categories=");

// ─── Helpers ───────────────────────────────────────────────────────────────────

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Validates an 8-char alphanumeric Kroger location ID. Returns "" if invalid. */
function validateLocationId(id) {
  if (!id) return "";
  if (/^[a-zA-Z0-9]{8}$/.test(id)) return id;
  console.warn(
    `\n  WARNING: Location ID "${id}" is not a valid 8-character alphanumeric ID — ignoring it.\n`
  );
  return "";
}

/** Validates a 5-digit US zip code. */
function validateZipCode(zip) {
  if (!zip) return "";
  if (/^\d{5}$/.test(zip)) return zip;
  console.error(`\n  ERROR: "${zip}" is not a valid 5-digit US zip code.\n`);
  process.exit(1);
}

// ─── Token Manager ─────────────────────────────────────────────────────────────

class TokenManager {
  constructor(clientId, clientSecret) {
    if (!clientId || !clientSecret) {
      throw new Error(
        "Missing KROGER_CLIENT_ID or KROGER_CLIENT_SECRET.\n" +
        "Set them in a .env file or as environment variables."
      );
    }
    this.credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    this.accessToken = null;
    this.expiresAt   = 0;
  }

  async getToken() {
    if (this.accessToken && Date.now() < this.expiresAt - 60_000) {
      return this.accessToken;
    }
    console.log("  Fetching new OAuth2 token...");
    const res = await fetch(TOKEN_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${this.credentials}`,
      },
      body: "grant_type=client_credentials&scope=product.compact",
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Token request failed (${res.status}): ${body}`);
    }
    const data = await res.json();
    this.accessToken = data.access_token;
    this.expiresAt   = Date.now() + data.expires_in * 1000;
    console.log(`  Token valid for ${Math.round(data.expires_in / 60)} minutes`);
    return this.accessToken;
  }
}

// ─── Location Lookup ───────────────────────────────────────────────────────────

/**
 * Given a zip code, calls GET /v1/locations to find nearby Kroger-family stores,
 * prints a numbered list, and returns the locationId of the first result.
 *
 * The function prefers stores whose chain name includes "KROGER", but will fall
 * back to any store in the results if no Kroger-branded store is found.
 *
 * @param {string} zipCode   - 5-digit US zip code
 * @param {number} radius    - search radius in miles (default 10)
 * @param {TokenManager} tokenMgr
 * @returns {Promise<string>} - 8-char locationId
 */
async function resolveLocationFromZip(zipCode, radius, tokenMgr) {
  console.log(`\n  Looking up stores near zip code ${zipCode} (radius: ${radius} miles)...`);

  const token = await tokenMgr.getToken();
  const params = new URLSearchParams({
    "filter.zipCode.near": zipCode,
    "filter.radiusInMiles": radius,
    "filter.limit": 10,
  });

  const res = await fetch(`${LOCATIONS_URL}?${params}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
    },
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Location lookup failed (${res.status}): ${body}`);
  }

  const data = await res.json();
  const stores = data?.data ?? [];

  if (stores.length === 0) {
    throw new Error(
      `No stores found within ${radius} miles of zip code ${zipCode}.\n` +
      `  Try increasing the radius with --radius=25`
    );
  }

  // Print all found stores so the user knows what was found
  console.log(`\n  Found ${stores.length} store(s) near ${zipCode}:\n`);
  stores.forEach((s, i) => {
    const addr = s.address ?? {};
    console.log(
      `    ${String(i + 1).padStart(2)}. [${s.locationId}] ${s.name} (${s.chain})\n` +
      `        ${addr.addressLine1}, ${addr.city}, ${addr.state} ${addr.zipCode}`
    );
  });

  // Pick the first Kroger-branded store, or fall back to the closest (index 0)
  const preferred = stores.find((s) => /kroger/i.test(s.chain)) ?? stores[0];
  const addr = preferred.address ?? {};
  console.log(
    `\n  Using: [${preferred.locationId}] ${preferred.name}\n` +
    `         ${addr.addressLine1}, ${addr.city}, ${addr.state} ${addr.zipCode}\n` +
    `  (Pass --location=${preferred.locationId} to use this store without a lookup next time)\n`
  );

  return preferred.locationId;
}

// ─── API Fetch Helpers ─────────────────────────────────────────────────────────

async function fetchWithRetry(url, headers, retries = MAX_RETRIES) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const res = await fetch(url, { headers });

    if (res.status === 429) {
      const wait = RETRY_DELAY_MS * attempt;
      console.warn(`    Rate limited (429). Waiting ${wait / 1000}s (retry ${attempt}/${retries})...`);
      await sleep(wait);
      continue;
    }
    if (res.status === 401) {
      throw Object.assign(new Error("Unauthorized (401)"), { code: "UNAUTHORIZED" });
    }
    if (!res.ok) {
      const body = await res.text();
      if (attempt < retries) {
        console.warn(`    HTTP ${res.status} on attempt ${attempt}. Retrying...`);
        await sleep(RETRY_DELAY_MS);
        continue;
      }
      throw new Error(`Request failed (${res.status}): ${body}`);
    }
    return res.json();
  }
  throw new Error(`Failed after ${retries} retries: ${url}`);
}

async function fetchProductsForTerm(term, locationId, tokenMgr, dryRun) {
  const products   = [];
  const totalPages = dryRun ? 1 : MAX_PAGES;

  for (let page = 0; page < totalPages; page++) {
    const params = new URLSearchParams({
      "filter.term":  term,
      "filter.limit": PAGE_LIMIT,
      "filter.start": page * PAGE_LIMIT + 1,
    });
    if (locationId) params.set("filter.locationId", locationId);

    let token = await tokenMgr.getToken();
    let data;

    try {
      data = await fetchWithRetry(`${PRODUCTS_URL}?${params}`, {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      });
    } catch (err) {
      if (err.code === "UNAUTHORIZED") {
        tokenMgr.expiresAt = 0;
        token = await tokenMgr.getToken();
        data = await fetchWithRetry(`${PRODUCTS_URL}?${params}`, {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        });
      } else {
        throw err;
      }
    }

    const items = data?.data ?? [];
    products.push(...items);
    if (items.length < PAGE_LIMIT) break;
    await sleep(REQUEST_DELAY_MS);
  }

  return products;
}

// ─── CSV Utilities ─────────────────────────────────────────────────────────────

function csvEscape(value) {
  if (value === null || value === undefined) return "";
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

const CSV_HEADERS = [
  "productId", "upc", "aisleLocations", "brand", "categories",
  "countryOrigin", "description", "images", "itemsFacets", "temperature",
  "soldInStore", "priceRegular", "pricePromo", "priceSaleEndDate",
  "size", "soldBy", "stock",
  "fulfillment_inStore", "fulfillment_shipToHome", "fulfillment_delivery",
];

function productToRow(p) {
  const items       = p.items?.[0] ?? {};
  const price       = items.price ?? {};
  const fulfillment = items.fulfillment ?? {};

  return [
    p.productId,
    p.upc,
    (p.aisleLocations ?? []).map((a) => a.description).join("; "),
    p.brand,
    (p.categories ?? []).join("; "),
    p.countryOrigin,
    p.description,
    (p.images ?? [])
      .filter((img) => img.perspective === "front" && img.featured)
      .map((img) => {
        const large = (img.sizes ?? []).find((s) => s.id === "large");
        return large?.url ?? img.sizes?.[0]?.url ?? "";
      })
      .join("; "),
    (p.itemsFacets ?? []).join("; "),
    items.temperature?.indicator,
    items.soldInStore,
    price.regular,
    price.promo,
    price.saleEndDate,
    items.size,
    items.soldBy,
    items.inventory?.stockLevel,
    fulfillment.inStore,
    fulfillment.shipToHome,
    fulfillment.delivery,
  ].map(csvEscape).join(",");
}

function writeCsv(filePath, rows) {
  fs.writeFileSync(filePath, [CSV_HEADERS.join(","), ...rows].join("\n"), "utf8");
}

// ─── Food Categories ───────────────────────────────────────────────────────────

const FOOD_CATEGORIES = {
  produce: [
    "fresh vegetables", "fresh fruit", "salad greens", "herbs", "mushrooms",
    "apples", "bananas", "berries", "citrus", "grapes", "avocado",
    "tomatoes", "potatoes", "onions", "peppers", "broccoli", "carrots",
  ],
  meat_seafood: [
    "chicken breast", "ground beef", "pork chops", "steak", "salmon",
    "shrimp", "tilapia", "turkey", "sausage", "bacon", "deli meat",
    "lamb", "crab", "lobster", "tuna steak",
  ],
  dairy_eggs: [
    "milk", "eggs", "butter", "cheese", "yogurt", "cream", "sour cream",
    "cream cheese", "cottage cheese", "half and half", "whipping cream",
    "shredded cheese", "sliced cheese",
  ],
  bakery_bread: [
    "bread", "bagels", "muffins", "rolls", "tortillas", "croissant",
    "pita bread", "buns", "english muffins", "crackers", "flatbread",
  ],
  frozen_foods: [
    "frozen pizza", "frozen vegetables", "frozen meals", "frozen chicken",
    "ice cream", "frozen fish", "frozen burritos", "frozen waffles",
    "frozen fruit", "frozen shrimp", "pot pie",
  ],
  pantry_staples: [
    "rice", "pasta", "canned tomatoes", "canned beans", "olive oil",
    "flour", "sugar", "salt", "vinegar", "broth", "canned soup",
    "canned tuna", "peanut butter", "jelly", "honey", "syrup",
  ],
  snacks: [
    "potato chips", "pretzels", "popcorn", "trail mix", "granola bars",
    "crackers snack", "cookies", "nuts snack", "rice cakes", "jerky",
    "fruit snacks", "cheese crackers",
  ],
  beverages: [
    "juice", "soda", "sparkling water", "coffee", "tea", "energy drink",
    "sports drink", "lemonade", "almond milk", "oat milk", "soy milk",
    "coconut water", "hot chocolate",
  ],
  breakfast: [
    "cereal", "oatmeal", "pancake mix", "granola", "breakfast bars",
    "orange juice", "frozen waffles breakfast", "grits", "cream of wheat",
    "instant oatmeal",
  ],
  condiments_sauces: [
    "ketchup", "mustard", "mayonnaise", "salad dressing", "hot sauce",
    "soy sauce", "pasta sauce", "bbq sauce", "salsa", "hummus",
    "ranch dressing", "teriyaki sauce", "sriracha",
  ],
  deli: [
    "deli chicken", "deli cheese", "deli turkey", "deli ham", "deli salads",
    "prepared meals", "rotisserie chicken", "lunch meat",
  ],
  baking: [
    "baking powder", "baking soda", "yeast", "chocolate chips", "cocoa",
    "vanilla extract", "powdered sugar", "brown sugar", "cornstarch",
    "cake mix", "brownie mix", "pie crust",
  ],
  international: [
    "asian noodles", "tortilla chips", "salsa verde", "kimchi",
    "indian curry", "thai sauce", "hummus dip", "pita chips",
    "mexican spices", "ramen noodles",
  ],
  organic: [
    "organic milk", "organic eggs", "organic vegetables", "organic fruit",
    "organic chicken", "organic salad", "organic yogurt", "organic cereal",
  ],
  health_wellness: [
    "protein powder", "vitamins", "supplements", "protein bars",
    "vegan cheese", "plant based meat", "gluten free bread",
    "keto snacks", "low sodium", "sugar free",
  ],
};

// ─── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const clientId     = process.env.KROGER_CLIENT_ID;
  const clientSecret = process.env.KROGER_CLIENT_SECRET;
  const tokenMgr     = new TokenManager(clientId, clientSecret);

  // ── Resolve location ID (priority: --location > --zipcode > env var) ────────
  let locationId = "";

  if (locationArgRaw) {
    // Hard-coded via --location flag
    locationId = validateLocationId(locationArgRaw);
  } else if (zipcodeArg) {
    // Zip code lookup via --zipcode flag
    const zip = validateZipCode(zipcodeArg);
    locationId = await resolveLocationFromZip(zip, radiusArg, tokenMgr);
  } else if (process.env.KROGER_LOCATION_ID) {
    // Fall back to .env value
    locationId = validateLocationId(process.env.KROGER_LOCATION_ID);
  }

  if (!locationId) {
    console.log(
      "\n  No location ID provided. Products will be fetched without store-specific\n" +
      "  pricing or stock data. Use --zipcode=XXXXX to enable pricing.\n"
    );
  }

  // ── Category selection ──────────────────────────────────────────────────────
  const categoryKeys = categoryFilter
    ? categoryFilter.split(",").map((s) => s.trim()).filter((k) => FOOD_CATEGORIES[k])
    : Object.keys(FOOD_CATEGORIES);

  if (categoryFilter && categoryKeys.length === 0) {
    console.error(
      `None of the specified categories are valid.\nValid keys: ${Object.keys(FOOD_CATEGORIES).join(", ")}`
    );
    process.exit(1);
  }

  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  console.log(`\nKroger Food Product Scraper`);
  console.log(`  Output dir:  ${path.resolve(outDir)}`);
  console.log(`  Location ID: ${locationId || "(none - pricing/stock columns will be empty)"}`);
  console.log(`  Categories:  ${categoryKeys.join(", ")}`);
  console.log(`  Dry run:     ${isDryRun}\n`);

  // ── Scrape loop ─────────────────────────────────────────────────────────────
  const stats = { totalProducts: 0, totalRequests: 0, categories: {} };

  for (const categoryKey of categoryKeys) {
    const terms = FOOD_CATEGORIES[categoryKey];
    console.log(`\nCategory: ${categoryKey} (${terms.length} terms)`);

    const productMap = new Map(); // productId → product (dedup within category)

    for (const term of terms) {
      process.stdout.write(`  Searching "${term}" ... `);
      try {
        const products = await fetchProductsForTerm(term, locationId, tokenMgr, isDryRun);
        let newCount = 0;
        for (const p of products) {
          if (!productMap.has(p.productId)) {
            productMap.set(p.productId, p);
            newCount++;
          }
        }
        stats.totalRequests += isDryRun ? 1 : Math.ceil(products.length / PAGE_LIMIT) || 1;
        process.stdout.write(`${products.length} fetched, ${newCount} new\n`);
      } catch (err) {
        process.stdout.write(`\n  ERROR: ${err.message}\n`);
      }
      await sleep(REQUEST_DELAY_MS);
    }

    const csvPath = path.join(outDir, `${categoryKey}.csv`);
    writeCsv(csvPath, Array.from(productMap.values()).map(productToRow));

    stats.categories[categoryKey] = productMap.size;
    stats.totalProducts += productMap.size;
    console.log(`  Saved ${productMap.size} unique products -> ${csvPath}`);
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  const summaryRows = [
    "category,unique_products",
    ...Object.entries(stats.categories).map(([k, v]) => `${k},${v}`),
  ];
  fs.writeFileSync(path.join(outDir, "_summary.csv"), summaryRows.join("\n"), "utf8");

  console.log(`\n${"─".repeat(55)}`);
  console.log(`Done!`);
  console.log(`  Total unique products : ${stats.totalProducts.toLocaleString()}`);
  console.log(`  Approximate API calls : ${stats.totalRequests.toLocaleString()}`);
  console.log(`  Output files          : ${path.resolve(outDir)}`);
  console.log(`${"─".repeat(55)}\n`);
}

main().catch((err) => {
  console.error(`\nFatal error: ${err.message}`);
  process.exit(1);
});