"""
precompute_scraped_matches.py
==============================
Matches every recipe in Recipes_Kaggle against scraped_ingredients
(multi-store catalog) and saves results to scraped_recipe_matches in Supabase.

Run ONCE (safe to re-run — skips already-processed recipes):
    cd Kaggle_Kroger
    source .venv/bin/activate
    caffeinate -is python precompute_scraped_matches.py
"""

import urllib.request
import urllib.parse
import json
import time
import pandas as pd
from Kaggle_Kroger.ingredient_matcher import (
    IngredientMatcher,
    parse_ingredient_list_string,
    normalize_catalog_text,
    normalize_spaces,
)

SUPABASE_URL = "https://vpmxdkrwqxgullnducey.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZwbXhka3J3cXhndWxsbmR1Y2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0NDQ5ODMsImV4cCI6MjA4NzAyMDk4M30.NYievlganIUF4tVQvgK8NAaMAk2_y6NHnijvbuiWKCw"

HEADERS = {
    "apikey":        SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type":  "application/json",
    "Prefer":        "return=minimal",
}


def sb_get(table: str, params: dict, retries=5, backoff=3.0) -> list:
    url = f"{SUPABASE_URL}/rest/v1/{table}?{urllib.parse.urlencode(params)}"
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except Exception as e:
            last_err = e
            wait = backoff * (attempt + 1)
            print(f"  ⚠️  Fetch failed (attempt {attempt+1}/{retries}): {e}")
            time.sleep(wait)
    raise last_err


def sb_post(table: str, rows: list, retries=5, backoff=3.0):
    if not rows:
        return
    data = json.dumps(rows).encode()
    last_err = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                f"{SUPABASE_URL}/rest/v1/{table}",
                data=data, headers=HEADERS, method="POST"
            )
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status
        except Exception as e:
            last_err = e
            wait = backoff * (attempt + 1)
            print(f"  ⚠️  Upload failed (attempt {attempt+1}/{retries}): {e}")
            time.sleep(wait)
    raise last_err


def fetch_all(table: str, columns: str, order: str) -> list:
    rows, offset = [], 0
    while True:
        batch = sb_get(table, {
            "select": columns, "limit": 1000,
            "offset": offset, "order": order,
        })
        rows.extend(batch)
        if len(batch) < 1000:
            break
        offset += 1000
    return rows


# ── Step 1: Load scraped_ingredients from Supabase ────────────────────────────
print("Loading scraped_ingredients from Supabase...")
products_raw = fetch_all(
    "scraped_ingredients",
    "id,taxonomy,store,name,price,price_raw,price_unit,quantity,image_url,out_of_stock",
    "id.asc"
)
print(f"  {len(products_raw):,} products")

df_catalog = pd.DataFrame(products_raw)

# Build matcher
m = IngredientMatcher.__new__(IngredientMatcher)
m.use_reranker = False
m._api_key = None
m.catalog_csv_path = "<supabase:scraped_ingredients>"
adapted = m._adapt_scraped_catalog_format(df_catalog)

required = ["productId", "brand", "description", "categories", "classifier", "search_keyword"]
for col in required:
    if col not in adapted.columns:
        adapted[col] = ""
    adapted[col] = adapted[col].fillna("")

for col in ["description", "brand", "categories", "search_keyword"]:
    adapted[col] = adapted[col].astype(str).str.replace("Â®", "®", regex=False).str.replace("â„¢", "™", regex=False)

adapted["description_norm"]    = adapted["description"].map(normalize_catalog_text)
adapted["brand_norm"]          = adapted["brand"].map(normalize_catalog_text)
adapted["categories_norm"]     = adapted["categories"].map(normalize_catalog_text)
adapted["classifier_norm"]     = adapted["classifier"].map(normalize_catalog_text)
adapted["search_keyword_norm"] = adapted["search_keyword"].map(normalize_catalog_text)
adapted["combined_text"] = (
    adapted["description_norm"] + " " + adapted["brand_norm"] + " " +
    adapted["categories_norm"] + " " + adapted["classifier_norm"] + " " +
    adapted["search_keyword_norm"]
).str.strip().str.replace(r"\s+", " ", regex=True)

m.df = adapted
m._index, m._prefix_index = m._build_index()
print(f"Matcher ready — {len(m.df):,} products indexed.\n")


# ── Step 2: Load recipes ──────────────────────────────────────────────────────
print("Loading recipes from Supabase...")
recipes_raw = fetch_all("Recipes_Kaggle", "id,Title,Cleaned_Ingredients", "id.asc")
print(f"  {len(recipes_raw):,} recipes\n")


# ── Step 3: Check already processed ──────────────────────────────────────────
print("Checking already-processed recipes...")
already_done = set()
offset = 0
while True:
    batch = sb_get("scraped_recipe_matches", {
        "select": "recipe_id", "limit": 1000,
        "offset": offset, "order": "recipe_id.asc",
    })
    for row in batch:
        already_done.add(row["recipe_id"])
    if len(batch) < 1000:
        break
    offset += 1000

remaining = [r for r in recipes_raw if r.get("id") not in already_done]
print(f"  {len(already_done):,} already done — skipping.")
print(f"  {len(remaining):,} left to process.\n")

if not remaining:
    print("All recipes already processed!")
    exit(0)


# ── Step 4: Match and upload ──────────────────────────────────────────────────
INSERT_EVERY = 10
rows_buffer = []
processed = 0
no_match_count = 0

print(f"Processing {len(remaining):,} recipes...\n")

for recipe in remaining:
    recipe_id = recipe.get("id")
    title     = recipe.get("Title", "")
    cleaned   = recipe.get("Cleaned_Ingredients", "")

    if not cleaned:
        continue

    ingredients = parse_ingredient_list_string(cleaned)
    if not ingredients:
        continue

    match_results = m.match_ingredients(ingredients, top_k=3)

    for result in match_results:
        if result.get("skipped"):
            continue

        raw_ing = result.get("raw_ingredient", "")
        matches = result.get("matches", [])

        if not matches:
            no_match_count += 1
            rows_buffer.append({
                "recipe_id":          recipe_id,
                "recipe_title":       title,
                "raw_ingredient":     raw_ing,
                "matched_name":       None,
                "matched_product_id": None,
                "matched_store":      None,
                "matched_image":      None,
                "matched_size":       None,
                "min_price":          None,
                "score":              None,
                "confidence":         None,
                "match_rank":         None,
            })
        else:
            for rank, match in enumerate(matches, start=1):
                rows_buffer.append({
                    "recipe_id":          recipe_id,
                    "recipe_title":       title,
                    "raw_ingredient":     raw_ing,
                    "matched_name":       match.get("description"),
                    "matched_product_id": match.get("productId"),
                    "matched_store":      match.get("brand"),   # brand = store name
                    "matched_image":      match.get("image_url"),
                    "matched_size":       match.get("size"),
                    "min_price":          match.get("min_price"),
                    "score":              match.get("score"),
                    "confidence":         match.get("confidence"),
                    "match_rank":         rank,
                })

    processed += 1

    if processed % INSERT_EVERY == 0:
        sb_post("scraped_recipe_matches", rows_buffer)
        rows_buffer = []
        print(f"  ✓ {processed:,}/{len(remaining):,} | "
              f"total done: {processed + len(already_done):,} | "
              f"no match: {no_match_count}")

if rows_buffer:
    sb_post("scraped_recipe_matches", rows_buffer)

print(f"\nDone!")
print(f"  Processed: {processed:,}")
print(f"  No match:  {no_match_count:,}")
