"""
scraper.py  —  Instacart pipeline scraper
==========================================

Architecture
------------
  1. Load credentials from CS178-Shopwise/.env
        SUPABASE_URL, SUPABASE_SERVICE_KEY

  2. Fetch all rows from the Supabase `taxonomy` table (column: `ingredient`)
     Ingredient format — two cases:
       "eggs"             -> single word: search "eggs", keep ALL results
       "cabbage, red"     -> word + descriptor: search "cabbage, red" (full phrase),
                            keep only products whose name contains "red"

  3. For each ingredient:
       a. Parse into (search_term, filter_word | None)
            - search_term  = full ingredient string (e.g. "cabbage, red")
            - filter_word  = text after the comma (e.g. "red"), or None
       b. Open Instacart cross-retailer search: instacart.com/store/s?k=<search_term>
       c. Expand every store's product carousel (Phase 1: Discovery)
       d. Click each card, open the detail dialog; extract all fields in one JS call
          (Phase 2: Scraping). Fields per product:
            store, name, price, price_unit, quantity, image_url, description, out_of_stock
       e. If filter_word is set, drop products whose name does not contain it
          (case-insensitive substring match)

  4. Upsert all collected products to the Supabase `ingredients` table.
     Columns: id, taxonomy, store, name, price, price_unit, quantity,
              image_url, description, out_of_stock

  Single Playwright browser session is reused across all ingredients so that
  Instacart's session/location cookies persist between queries.

Usage
-----
  python scraper.py

Output
------
  Supabase table: ingredients
"""

import argparse
import asyncio
import os
import re
import uuid
from pathlib import Path
from urllib.parse import quote_plus

from dotenv import load_dotenv
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
from supabase import create_client

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_ENV_PATH = Path(__file__).parent.parent / ".env"
load_dotenv(_ENV_PATH)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_KEY")

BASE_URL = "https://www.instacart.com/store/s?k={query}"

# How long to wait for the product grid to appear (ms).
GRID_WAIT_MS = 5_000


# ---------------------------------------------------------------------------
# Confirmed Instacart DOM selectors (verified against live DOM)
# ---------------------------------------------------------------------------

STORE_ROW_SELECTOR    = '[data-testid="CrossRetailerResultRowWrapper"]'
ITEM_CARD_SELECTOR    = '[data-testid^="item_list_item_"]'
NEXT_PAGE_SELECTOR    = '[aria-label="Next page"]'
DETAIL_DIALOG_SELECTOR = '[role="dialog"][aria-label="item details"]'
DETAIL_NAME_SELECTOR   = '[aria-label="item details"] h2'
LOGIN_MODAL_SELECTOR   = (
    '[role="dialog"] input[type="email"], [role="dialog"] input[type="password"], '
    '[aria-modal="true"] input[type="email"], [aria-modal="true"] input[type="password"]'
)

# Maximum carousel pages to advance per store row.
MAX_CAROUSEL_PAGES = 10

# ---------------------------------------------------------------------------
# Ingredient parsing
# ---------------------------------------------------------------------------

def parse_ingredient(ingredient: str) -> tuple[str, str | None]:
    """
    Parse a taxonomy ingredient string into (search_term, filter_word).

    The full ingredient string is always used as the search term so that
    Instacart receives the most specific query possible.

    Examples:
      "eggs"            → ("eggs",         None)
      "cabbage, red"    → ("cabbage, red",  "red")
    """
    parts = [p.strip() for p in ingredient.split(",", 1)]
    search_term  = ingredient          # search the full phrase
    filter_word  = parts[1] if len(parts) > 1 else None
    return search_term, filter_word


def apply_name_filter(products: list[dict], filter_word: str | None) -> list[dict]:
    """Keep only products whose name contains filter_word (case-insensitive)."""
    if not filter_word:
        return products
    fw = filter_word.lower()
    return [p for p in products if p["name"] and fw in p["name"].lower()]

# ---------------------------------------------------------------------------
# Core scraper
# ---------------------------------------------------------------------------

async def scrape_query(page, query: str) -> list[dict]:
    """
    Scrape all product cards for *query* on the Instacart cross-retailer page.
    Returns a list of product dicts (fields match CSV_FIELDS minus 'taxonomy').
    Returns an empty list if navigation fails or the grid is not found.
    """
    url = BASE_URL.format(query=quote_plus(query))

    # -- Navigate ----------------------------------------------------------
    try:
        response = await page.goto(url, wait_until="domcontentloaded", timeout=30_000)
        if response and response.status >= 400:
            print(f"  [ERROR] HTTP {response.status} for query '{query}'")
            return []
    except PlaywrightTimeoutError:
        print(f"  [ERROR] Navigation timeout for query '{query}'")
        return []
    except Exception as exc:
        print(f"  [ERROR] Navigation error for query '{query}': {exc}")
        return []

    # -- Block detection ---------------------------------------------------
    try:
        body_text = (await page.inner_text("body")).lower()
    except Exception:
        body_text = ""

    blocked_patterns = [
        "access denied", "403", "robot", "captcha",
        "verify you are human", "unusual traffic", "too many requests", "rate limit",
    ]
    if any(p in body_text for p in blocked_patterns):
        print(f"  [WARN] Bot-detection page detected for query '{query}' — skipping")
        return []

    if await page.query_selector(LOGIN_MODAL_SELECTOR):
        print(f"  [WARN] Login modal detected for query '{query}' — skipping")
        return []

    # -- Wait for store rows -----------------------------------------------
    try:
        await page.wait_for_selector(STORE_ROW_SELECTOR, timeout=GRID_WAIT_MS)
    except PlaywrightTimeoutError:
        print(f"  [WARN] No store grid found for query '{query}' after {GRID_WAIT_MS}ms")
        return []

    # -- Discovery + Scraping (merged) — process each carousel page inline --
    # Cards are clicked immediately while their carousel page is active,
    # so ElementHandles never become stale from carousel advancement.
    store_rows = await page.query_selector_all(STORE_ROW_SELECTOR)

    if not store_rows:
        print(f"  [WARN] No product cards found for query '{query}'")
        return []

    products = []
    total_card_index = 0

    for row in store_rows:
        try:
            store_name = await page.evaluate("""
                (row) => {
                    const lines = (row.innerText || '').split('\\n')
                        .map(s => s.trim()).filter(Boolean);
                    return lines[0] || 'Unknown Store';
                }
            """, row)
        except Exception:
            store_name = "Unknown Store"

        seen_testids: set[str] = set()

        for _ in range(MAX_CAROUSEL_PAGES + 1):
            cards_now = await row.query_selector_all(ITEM_CARD_SELECTOR)

            # Scrape each new card on this carousel page immediately (before advancing)
            for card in cards_now:
                try:
                    testid = await card.get_attribute("data-testid") or ""
                except Exception:
                    testid = ""
                if testid in seen_testids:
                    continue
                seen_testids.add(testid)

                i = total_card_index
                total_card_index += 1

                name_text    = None
                price_text   = None
                price_unit   = None
                quantity     = None
                image_url    = None
                description  = None
                out_of_stock = False
                item_error   = None

                try:
                    await card.scroll_into_view_if_needed()
                    await card.click()
                    await page.wait_for_selector(DETAIL_DIALOG_SELECTOR, timeout=6_000)
                except PlaywrightTimeoutError:
                    item_error = f"Card {i}: timed out waiting for detail dialog"
                except Exception as exc:
                    item_error = f"Card {i}: click error: {exc}"

                if item_error:
                    print(f"  [WARN] {item_error}")
                    products.append(_empty_product(store_name))
                    continue

                # Extract all fields from the open dialog in a single JS round-trip.
                try:
                    _data = await page.evaluate("""
                        () => {
                            const dialog = document.querySelector(
                                '[role="dialog"][aria-label="item details"]'
                            );
                            if (!dialog) return null;

                            // Name — first h2 in dialog
                            const nameEl = dialog.querySelector('h2');
                            const name = nameEl ? nameEl.textContent.trim() : null;

                            // Price header span + sibling unit span
                            // DOM patterns:
                            //   <span>$1.99 /lb</span> <span>per lb</span>  → rate → price_unit
                            //   <span>$3.99</span>      <span>18 ct</span>  → pkg  → quantity
                            //   <span>$9.07</span>      <span>each</span>   → fixed → both null
                            let priceText = '', unitText = '', isRate = false;
                            const itemDetails = dialog.querySelector('#item_details');
                            for (const span of dialog.querySelectorAll('span')) {
                                if (itemDetails && itemDetails.contains(span)) continue;
                                if (span.childElementCount !== 0) continue;
                                const t = span.textContent.trim();
                                if (!/^\\$[\\d.,]+/.test(t)) continue;
                                const parent = span.parentElement;
                                if (!parent) continue;
                                const siblings = Array.from(parent.children)
                                    .filter(el => el.tagName === 'SPAN');
                                const idx = siblings.indexOf(span);
                                unitText = (idx !== -1 && siblings[idx + 1])
                                    ? siblings[idx + 1].textContent.trim() : '';
                                isRate = /\\//.test(t) || /^per\\s/i.test(unitText);
                                priceText = t;
                                break;
                            }

                            // Price — screen-reader span or first $X.XX span
                            let price = null;
                            const spans = dialog.querySelectorAll('span');
                            for (const s of spans) {
                                if (s.childElementCount !== 0) continue;
                                const t = s.textContent.trim();
                                if (t.startsWith('Current price:')) {
                                    const full = t.replace('Current price:', '').trim();
                                    const m = full.match(/^(\\$[\\d.,]+)/);
                                    price = m ? m[1] : full;
                                    break;
                                }
                            }
                            if (!price) {
                                for (const s of spans) {
                                    if (s.childElementCount !== 0) continue;
                                    const t = s.textContent.trim();
                                    const m = t.match(/^(\\$[\\d.,]+)/);
                                    if (m) { price = m[1]; break; }
                                }
                            }

                            // Image — .ic-image-zoomer img, fallback img[alt]; null if placeholder
                            let imageUrl = null;
                            const zoomer = dialog.querySelector('.ic-image-zoomer img');
                            if (zoomer && zoomer.src) imageUrl = zoomer.src;
                            else {
                                const fb = dialog.querySelector('img[alt]');
                                if (fb) imageUrl = fb.src;
                            }
                            if (imageUrl && imageUrl.includes('missing-item')) imageUrl = null;

                            // Description — <p> inside container whose sibling h2 is "Details"
                            let description = null;
                            for (const h of dialog.querySelectorAll('h2')) {
                                if (h.textContent.trim() === 'Details') {
                                    const c = h.closest('[tabindex="-1"]') || h.parentElement;
                                    const p = c ? c.querySelector('p') : null;
                                    if (p) description = p.textContent.trim();
                                    break;
                                }
                            }

                            // Out of stock — h2 text "out of stock"
                            let outOfStock = false;
                            for (const h of dialog.querySelectorAll('h2')) {
                                if (h.textContent.trim().toLowerCase() === 'out of stock') {
                                    outOfStock = true; break;
                                }
                            }

                            return { name, priceText, unitText, isRate, price,
                                     imageUrl, description, outOfStock };
                        }
                    """)
                except Exception:
                    _data = None

                if _data:
                    name_text    = _data.get("name") or None
                    price_text   = _data.get("price") or None
                    image_url    = _data.get("imageUrl") or None
                    description  = _data.get("description") or None
                    out_of_stock = bool(_data.get("outOfStock"))

                    _price_raw = _data.get("priceText", "")
                    _unit_text = _data.get("unitText", "")
                    if _data.get("isRate"):
                        _slash = _price_raw.find("/")
                        if _slash != -1:
                            _after = _price_raw[_slash + 1:].strip()
                            if re.match(r'^\d', _after):
                                quantity = _after
                            elif _after and re.match(
                                r'^(?:lb|lbs|oz|fl\.?\s*oz|g|kg|ml|L|gal)\b',
                                _after, re.IGNORECASE
                            ):
                                price_unit = _after
                        elif _unit_text:
                            _norm = re.sub(
                                r'^(?:per\s+|/)', '', _unit_text, flags=re.IGNORECASE
                            ).strip()
                            if _norm and not re.match(r'^\d', _norm):
                                price_unit = _norm
                    elif _unit_text and not re.match(
                        r'^\d*\s*each$', _unit_text, re.IGNORECASE
                    ):
                        quantity = _unit_text

                # Regex fallback for quantity: two-pass — prefer count patterns
                # (e.g. "12-count", "6 pk") over weight/volume so multi-pack items
                # resolve to the pack count rather than the per-unit weight.
                if quantity is None and price_unit is None and name_text:
                    m = re.search(
                        r'\d+(?:[./]\d+)?[\s-]*(?:ct|count|pk|pack)\b',
                        name_text, re.IGNORECASE
                    )
                    if not m:
                        m = re.search(
                            r'\d+(?:[./]\d+)?[\s-]*'
                            r'(?:oz|fl\.?\s*oz|lb|lbs|g|kg|ml|L|gal)\b',
                            name_text, re.IGNORECASE
                        )
                    if m:
                        quantity = m.group(0).strip()

                # Close dialog before moving to next card
                try:
                    await page.keyboard.press("Escape")
                    await page.wait_for_selector(
                        DETAIL_DIALOG_SELECTOR, state="hidden", timeout=1_500
                    )
                except Exception:
                    pass  # dialog may have already closed; continue regardless

                product_id = testid.removeprefix("item_list_item_") or str(uuid.uuid4())
                products.append({
                    "id":           product_id,
                    "store":        store_name,
                    "name":         name_text,
                    "price":        price_text,
                    "price_unit":   price_unit,
                    "quantity":     quantity,
                    "image_url":    image_url,
                    "description":  description,
                    "out_of_stock": out_of_stock,
                })

            # Advance carousel after all cards on this page are processed
            try:
                next_btn = await row.query_selector(NEXT_PAGE_SELECTOR)
                if not next_btn or not await next_btn.is_visible():
                    break
                await next_btn.click()
                await page.wait_for_timeout(150)
            except Exception:
                break

    return products


def _empty_product(store_name: str) -> dict:
    return {
        "id": str(uuid.uuid4()), "store": store_name, "name": None, "price": None,
        "price_unit": None, "quantity": None, "image_url": None,
        "description": None, "out_of_stock": False,
    }

# ---------------------------------------------------------------------------
# Pipeline entry point
# ---------------------------------------------------------------------------

async def run_pipeline(limit: int | None = None) -> None:
    """
    Full pipeline: fetch taxonomy → scrape Instacart → upsert to Supabase.
    limit: if set, only process the first N ingredients (for test runs).
    """
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise RuntimeError(
            "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in .env"
        )

    # -- Fetch taxonomy ----------------------------------------------------
    print("Fetching taxonomy from Supabase...")
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    response = supabase.table("taxonomy").select("ingredient").execute()
    ingredients = [row["ingredient"] for row in response.data]
    if limit is not None:
        ingredients = ingredients[:limit]
        print(f"  {len(ingredients)} ingredients loaded (limited to first {limit}).")
    else:
        print(f"  {len(ingredients)} ingredients loaded.")

    total_upserted = 0

    # -- Scrape ------------------------------------------------------------
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=False,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/122.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 900},
        )
        page = await context.new_page()

        for ingredient in ingredients:
            search_term, filter_word = parse_ingredient(ingredient)
            print(f"\n[{ingredient}]  search='{search_term}'  filter={filter_word!r}")

            products = await scrape_query(page, search_term)
            products = apply_name_filter(products, filter_word)

            rows = [{"taxonomy": ingredient, **p} for p in products]

            if rows:
                supabase.table("ingredients").upsert(rows, on_conflict="id").execute()
                total_upserted += len(rows)

            print(f"  → {len(rows)} products upserted")

        await browser.close()

    print(f"\nDone. {total_upserted} total rows upserted to Supabase.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Instacart pipeline scraper")
    parser.add_argument(
        "--limit", type=int, default=None, metavar="N",
        help="Only process the first N taxonomy ingredients (e.g. --limit 3 for a test run)",
    )
    args = parser.parse_args()
    asyncio.run(run_pipeline(limit=args.limit))
