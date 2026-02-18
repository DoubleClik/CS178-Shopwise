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
 *     KROGER_LOCATION_ID=          ← leave blank, or use a real 8-char ID
 *
 *   Register at: https://developer.kroger.com
 *   Scope needed: product.compact
 *
 * USAGE:
 *   node kroger_food_scraper.js
 *
 *   Optional flags:
 *     --dry-run          Fetch only the first page of each category (for testing)
 *     --categories=a,b   Comma-separated list of category keys to run
 *                        (see FOOD_CATEGORIES below for valid keys)
 *     --location=xxxxx   Override store location ID (must be 8 alphanumeric chars)
 *     --out=./my-output  Output directory (default: ./kroger_output)
 */

import "dotenv/config";
import fetch from "node-fetch";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ─── Configuration ────────────────────────────────────────────────────────────

const BASE_URL = "https://api.kroger.com/v1";
const TOKEN_URL = `${BASE_URL}/connect/oauth2/token`;
const PRODUCTS_URL = `${BASE_URL}/products`;

const PAGE_LIMIT = 50;        // max allowed by Kroger API
const MAX_PAGES = 20;         // 20 pages x 50 = 1,000 results per term (API ceiling)
const REQUEST_DELAY_MS = 350; // stay comfortably under rate limits
const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 2000;

// ─── CLI Args ─────────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
const isDryRun = args.includes("--dry-run");
const outDir = (args.find((a) => a.startsWith("--out=")) || "").replace("--out=", "") || "./kroger_output";
const locationArgRaw = (args.find((a) => a.startsWith("--location=")) || "").replace("--location=", "") || "";
const categoryFilter = (args.find((a) => a.startsWith("--categories=")) || "").replace("--categories=", "");

/**
 * Validates that a location ID is exactly 8 alphanumeric characters.
 * Silently returns "" for empty input.
 * Warns and returns "" if a non-empty but invalid value is provided
 * (e.g. the unfilled .env placeholder "optional_store_location_id").
 */
function validateLocationId(id) {
  if (!id) return "";
  if (/^[a-zA-Z0-9]{8}$/.test(id)) return id;
  console.warn(
    `\n  Location ID "${id}" is not a valid 8-character alphanumeric ID.` +
    `\n  Ignoring it — products will still be fetched without pricing/stock data.` +
    `\n  To use pricing: find a real ID with:` +
    `\n    curl -H "Authorization: Bearer <token>" \\` +
    `\n      "https://api.kroger.com/v1/locations?filter.zipCode=YOUR_ZIP&filter.limit=1"` +
    `\n  then set KROGER_LOCATION_ID=<8charId> in your .env (or leave it blank).\n`
  );
  return "";
}

// ─── Food Categories ──────────────────────────────────────────────────────────

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

// ─── Token Manager ────────────────────────────────────────────────────────────

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
    this.expiresAt = 0;
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
    this.expiresAt = Date.now() + data.expires_in * 1000;
    console.log(`  Token valid for ${Math.round(data.expires_in / 60)} minutes`);
    return this.accessToken;
  }
}

// ─── API Helpers ──────────────────────────────────────────────────────────────

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchWithRetry(url, headers, retries = MAX_RETRIES) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    const res = await fetch(url, { headers });

    if (res.status === 429) {
      const wait = RETRY_DELAY_MS * attempt;
      console.warn(`    Rate limited (429). Waiting ${wait / 1000}s before retry ${attempt}/${retries}...`);
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

// ─── Product Fetcher ──────────────────────────────────────────────────────────

async function fetchProductsForTerm(term, locationId, tokenMgr, dryRun) {
  const products = [];
  const totalPages = dryRun ? 1 : MAX_PAGES;

  for (let page = 0; page < totalPages; page++) {
    const start = page * PAGE_LIMIT + 1;
    const params = new URLSearchParams({
      "filter.term": term,
      "filter.limit": PAGE_LIMIT,
      "filter.start": start,
    });
    if (locationId) params.set("filter.locationId", locationId);

    const url = `${PRODUCTS_URL}?${params}`;

    let token = await tokenMgr.getToken();

    let data;
    try {
      data = await fetchWithRetry(url, {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      });
    } catch (err) {
      if (err.code === "UNAUTHORIZED") {
        tokenMgr.expiresAt = 0;
        token = await tokenMgr.getToken();
        data = await fetchWithRetry(url, {
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

// ─── CSV Utilities ────────────────────────────────────────────────────────────

function csvEscape(value) {
  if (value === null || value === undefined) return "";
  const str = String(value);
  if (str.includes(",") || str.includes('"') || str.includes("\n")) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

const CSV_HEADERS = [
  "productId",
  "upc",
  "aisleLocations",
  "brand",
  "categories",
  "countryOrigin",
  "description",
  "images",
  "itemsFacets",
  "temperature",
  "soldInStore",
  "priceRegular",
  "pricePromo",
  "priceSaleEndDate",
  "size",
  "soldBy",
  "stock",
  "fulfillment_inStore",
  "fulfillment_shipToHome",
  "fulfillment_delivery",
];

function productToRow(p) {
  const items = p.items?.[0] ?? {};
  const price = items.price ?? {};
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
  const header = CSV_HEADERS.join(",");
  const content = [header, ...rows].join("\n");
  fs.writeFileSync(filePath, content, "utf8");
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const clientId = process.env.KROGER_CLIENT_ID;
  const clientSecret = process.env.KROGER_CLIENT_SECRET;

  // Validate location ID — must be exactly 8 alphanumeric chars or empty
  const locationId = validateLocationId(
    locationArgRaw || process.env.KROGER_LOCATION_ID || ""
  );

  const tokenMgr = new TokenManager(clientId, clientSecret);

  const categoryKeys = categoryFilter
    ? categoryFilter.split(",").map((s) => s.trim()).filter((k) => FOOD_CATEGORIES[k])
    : Object.keys(FOOD_CATEGORIES);

  if (categoryFilter && categoryKeys.length === 0) {
    console.error(
      `None of the specified categories are valid. Valid keys:\n  ${Object.keys(FOOD_CATEGORIES).join(", ")}`
    );
    process.exit(1);
  }

  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });

  console.log(`\nKroger Food Product Scraper`);
  console.log(`  Output dir:  ${path.resolve(outDir)}`);
  console.log(`  Location ID: ${locationId || "(none - pricing/stock columns will be empty)"}`);
  console.log(`  Categories:  ${categoryKeys.join(", ")}`);
  console.log(`  Dry run:     ${isDryRun}\n`);

  const stats = { totalProducts: 0, totalRequests: 0, categories: {} };

  for (const categoryKey of categoryKeys) {
    const terms = FOOD_CATEGORIES[categoryKey];
    console.log(`\nCategory: ${categoryKey} (${terms.length} terms)`);

    const productMap = new Map();

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

    const rows = Array.from(productMap.values()).map(productToRow);
    const csvPath = path.join(outDir, `${categoryKey}.csv`);
    writeCsv(csvPath, rows);

    stats.categories[categoryKey] = productMap.size;
    stats.totalProducts += productMap.size;
    console.log(`  Saved ${productMap.size} unique products -> ${csvPath}`);
  }

  const summaryPath = path.join(outDir, "_summary.csv");
  const summaryRows = [
    "category,unique_products",
    ...Object.entries(stats.categories).map(([k, v]) => `${k},${v}`),
  ];
  fs.writeFileSync(summaryPath, summaryRows.join("\n"), "utf8");

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