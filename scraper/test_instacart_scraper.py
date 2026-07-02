"""
test_instacart_scraper.py
--------------------------
Diagnostic test script for the Instacart Playwright scraper.
Runs in headful mode against a small set of test ingredients, logs raw output
to test_output/, and reports on common failure points.

Run directly:
    python test_instacart_scraper.py

Or import and call from a runner:
    import asyncio
    from test_instacart_scraper import run_diagnostics
    asyncio.run(run_diagnostics())

Output
------
  test_output/raw_<query>.json   — raw scraped data + page diagnostics per query
  test_output/summary.json       — final summary across all queries

CONFIRMED SELECTORS (verified against live DOM)
------------------------------------------------
  STORE_ROW_SELECTOR    '[data-testid="CrossRetailerResultRowWrapper"]'
  ITEM_CARD_SELECTOR    '[data-testid^="item_list_item_"]'
  NEXT_PAGE_SELECTOR    '[aria-label="Next page"]'
  DETAIL_DIALOG_SEL     '[role="dialog"][aria-label="item details"]'
  DETAIL_NAME_SEL       '[aria-label="item details"] h2'  (first h2 in dialog)
  price (in-stock)      leaf <span> starting with "Current price:" inside dialog
  price (out-of-stock)  first leaf <span> matching /^\\$[\\d.,]+/ in dialog header
  price_unit            set when price is a RATE (variable weight/measure):
                          "$1.99 /lb" + "per lb" → price_unit="lb", quantity=null
                        Null for fixed-package items and "each" items
  quantity              set when price covers a FIXED PACKAGE with a known count:
                          "$3.99" + "18 ct"  → quantity="18 ct",  price_unit=null
                          "$9.07" + "each"   → both null (single item, qty in name)
                        Null for rate-priced and single-each items
                        Fallback: regex extracted from product name
  image_url             .ic-image-zoomer img src (fallback: first img[alt] in dialog)
  description           <p> inside the container whose sibling <h2> reads "Details"
"""

import asyncio
import json
import re
import sys
from datetime import datetime
from pathlib import Path

from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

TEST_INGREDIENTS = [
    "chicken breast",
    "olive oil",
    "milk",
    "eggs",
    "pasta",
]

BASE_URL = "https://www.instacart.com/store/s?k={query}"

# How long to wait for the product grid to appear (ms).
# Instacart can be slow on first load — increase if you see timeout failures.
GRID_WAIT_MS = 8_000

OUTPUT_DIR = Path(__file__).parent / "test_output"

# One row per store on the cross-retailer search page.
STORE_ROW_SELECTOR = '[data-testid="CrossRetailerResultRowWrapper"]'

# Confirmed by DOM probe: item cards use a unique testid per item with this prefix.
# Pattern: item_list_item_items_{store_id}-{product_id}
ITEM_CARD_SELECTOR = '[data-testid^="item_list_item_"]'

# "Next page" button inside each store's product carousel.
NEXT_PAGE_SELECTOR = '[aria-label="Next page"]'

# Maximum number of carousel pages to advance per store (guards against infinite loops).
MAX_CAROUSEL_PAGES = 10

# ⚠ Selectors for the product DETAIL overlay — unverified, needs manual DOM check.
# After clicking a card the URL changes to /products/{id}-{slug}?retailerSlug=...
# and an overlay renders the product info.
#
# Confirmed from inspect-element on the live dialog:
#   - The overlay is role="dialog" aria-label="item details" (NOT a page nav)
#   - Product name lives in an <h2> inside that dialog (the only h1 on the
#     page is a hidden "Carts" dialog title — hence the previous timeouts)
#   - Price has no aria-label; the most stable hook is the screen-reader-only
#     <span> whose text starts with "Current price:" inside the same dialog
DETAIL_DIALOG_SELECTOR = '[role="dialog"][aria-label="item details"]'
DETAIL_NAME_SELECTOR   = '[aria-label="item details"] h2'

# Selector for a login modal/dialog that is actually blocking the page.
# Checks for a visible dialog containing an email or password input field.
# Avoids false positives from the "Log in" nav link that is always present.
LOGIN_MODAL_SELECTOR = '[role="dialog"] input[type="email"], [role="dialog"] input[type="password"], [aria-modal="true"] input[type="email"], [aria-modal="true"] input[type="password"]'

# Text patterns for a location interstitial — these are specific enough that
# they won't appear in normal nav/header text.
LOCATION_WALL_PATTERNS = [
    "enter your address",
    "enter a zip",
    "set your location",
    "choose a store",
    "select a store",
]
BLOCKED_PATTERNS = [
    "access denied",
    "403",
    "robot",
    "captcha",
    "verify you are human",
    "unusual traffic",
    "too many requests",
    "rate limit",
]


# ---------------------------------------------------------------------------
# Core diagnostic scrape
# ---------------------------------------------------------------------------

async def scrape_query(page, query: str) -> dict:
    """
    Navigate to the Instacart cross-retailer search page for *query* and collect
    diagnostic data. Returns a dict ready for JSON serialisation.
    """
    url = BASE_URL.format(query=query.replace(" ", "+"))  # produces ?k=chicken+breast
    result = {
        "query":          query,
        "url":            url,
        "timestamp":      datetime.utcnow().isoformat() + "Z",
        "login_wall":     False,
        "location_wall":  False,
        "blocked":        False,
        "grid_found":     False,
        "store_count":    0,
        "card_count":     0,
        "products":       [],
        "errors":         [],
        "page_title":     "",
        "page_text_snippet": "",
    }

    # -- Navigate --------------------------------------------------------
    try:
        response = await page.goto(url, wait_until="domcontentloaded", timeout=30_000)
        if response and response.status >= 400:
            result["errors"].append(f"HTTP {response.status} on initial navigation")
            result["blocked"] = True
            return result
    except PlaywrightTimeoutError:
        result["errors"].append("Navigation timeout (domcontentloaded)")
        return result
    except Exception as exc:
        result["errors"].append(f"Navigation error: {exc}")
        return result

    result["page_title"] = await page.title()

    # -- Check for interstitials before waiting for the grid --------------
    try:
        body_text = (await page.inner_text("body")).lower()
    except Exception:
        body_text = ""

    # Keep a snippet for the log so we can eyeball what loaded.
    # 1500 chars gives enough context to see whether search results appear.
    result["page_text_snippet"] = body_text[:1500].replace("\n", " ")

    # Login wall: check for a visible modal containing an email/password input,
    # not just the nav-bar "Log in" link which is always present on the page.
    if await page.query_selector(LOGIN_MODAL_SELECTOR):
        result["login_wall"] = True
        result["errors"].append("Login modal detected (email/password input visible in dialog)")

    if any(p in body_text for p in LOCATION_WALL_PATTERNS):
        result["location_wall"] = True
        result["errors"].append("Location/address wall detected on page load")

    if any(p in body_text for p in BLOCKED_PATTERNS):
        result["blocked"] = True
        result["errors"].append("Bot-detection / access-denied page detected")

    # If already blocked, bail early — no point waiting for a grid.
    if result["blocked"]:
        return result

    # -- Wait for store rows ----------------------------------------------
    try:
        await page.wait_for_selector(STORE_ROW_SELECTOR, timeout=GRID_WAIT_MS)
        result["grid_found"] = True
    except PlaywrightTimeoutError:
        result["errors"].append(
            f"Timed out waiting for store rows after {GRID_WAIT_MS}ms."
        )
        return result

    # Re-check for interstitials now that the grid has loaded.
    try:
        body_text = (await page.inner_text("body")).lower()
    except Exception:
        pass
    if await page.query_selector(LOGIN_MODAL_SELECTOR):
        result["login_wall"] = True
        result["errors"].append("Login modal appeared after grid wait")
    if any(p in body_text for p in LOCATION_WALL_PATTERNS):
        result["location_wall"] = True
        result["errors"].append("Location wall appeared after grid wait")

    # -- Phase 1: Discovery — expand each store carousel, collect cards --
    # We collect (store_name, card_element) pairs up-front so we can iterate
    # them cleanly in Phase 2 without re-querying the DOM mid-loop.
    store_rows = await page.query_selector_all(STORE_ROW_SELECTOR)
    result["store_count"] = len(store_rows)

    card_queue = []  # list of (store_name, card_element)

    for row in store_rows:
        # Store name: first non-empty line of the row's visible text.
        # This picks up "Stater Bros." / "Walmart" / etc. from the row header.
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

        # Expand the carousel — keep clicking "Next page" until it disappears
        # or we hit MAX_CAROUSEL_PAGES, ensuring we see all items in the row.
        for _ in range(MAX_CAROUSEL_PAGES):
            try:
                next_btn = await row.query_selector(NEXT_PAGE_SELECTOR)
                if not next_btn or not await next_btn.is_visible():
                    break
                await next_btn.click()
                await page.wait_for_timeout(400)  # let carousel animate
            except Exception:
                break

        # Collect all card elements now visible in this row.
        cards_in_row = await row.query_selector_all(ITEM_CARD_SELECTOR)
        for card in cards_in_row:
            card_queue.append((store_name, card))

    result["card_count"] = len(card_queue)

    if result["card_count"] == 0:
        result["errors"].append("No product cards found across any store row.")

    # -- Phase 2: Scraping — click each card, open dialog, extract data --
    # scroll_into_view_if_needed() ensures the card is clickable even if the
    # carousel left it off-screen after the "Next page" expansions.
    for i, (store_name, card) in enumerate(card_queue):
        name_text    = None
        price_text   = None
        price_unit   = None
        quantity     = None
        image_url    = None
        description  = None
        out_of_stock = False
        detail_html_snippet = None
        item_error   = None

        try:
            await card.scroll_into_view_if_needed()
            await card.click()
            # Wait for the detail dialog to become visible — faster than
            # waiting for the URL, and works regardless of URL behaviour.
            await page.wait_for_selector(DETAIL_DIALOG_SELECTOR, timeout=6_000)
        except PlaywrightTimeoutError:
            item_error = f"Card {i}: timed out waiting for detail dialog after click"
            result["errors"].append(item_error)
        except Exception as exc:
            item_error = f"Card {i}: click/navigation error: {exc}"
            result["errors"].append(item_error)

        if item_error is None:
            # Name: first h2 scoped to the item-details dialog.
            # (Confirmed from inspect element — product name is in an h2, not h1.)
            try:
                name_el = await page.wait_for_selector(DETAIL_NAME_SELECTOR, timeout=4_000)
                name_text = (await name_el.inner_text()).strip() or None
            except Exception as exc:
                result["errors"].append(f"Card {i}: name read error: {exc}")

            # Price unit vs quantity: both read from the mini-header price container
            # (the div above #item_details). Structure:
            #   <span>$1.99 /lb</span> <span>per lb</span>  → rate  → price_unit="lb"
            #   <span>$3.99</span>     <span>18 ct</span>   → pkg   → quantity="18 ct"
            #   <span>$9.07</span>     <span>each</span>    → fixed → both null
            #
            # Rate signal: price span contains "/" (e.g. "$1.99 /lb") OR unit span
            # starts with "per ". Otherwise it's a package quantity.
            # "each" → single fixed-price item, both fields stay null.
            try:
                _unit_info = await page.evaluate("""
                    () => {
                        const dialog = document.querySelector(
                            '[role="dialog"][aria-label="item details"]'
                        );
                        if (!dialog) return null;
                        const itemDetails = dialog.querySelector('#item_details');
                        for (const span of dialog.querySelectorAll('span')) {
                            if (itemDetails && itemDetails.contains(span)) continue;
                            if (span.childElementCount !== 0) continue;
                            const priceText = span.textContent.trim();
                            if (!/^\\$[\\d.,]+/.test(priceText)) continue;
                            const parent = span.parentElement;
                            if (!parent) continue;
                            const siblings = Array.from(parent.children)
                                .filter(el => el.tagName === 'SPAN');
                            const idx = siblings.indexOf(span);
                            const unitText = (idx !== -1 && siblings[idx + 1])
                                ? siblings[idx + 1].textContent.trim()
                                : '';
                            // Rate: price span has "/" (e.g. "$3.99 /lb")
                            // OR unit span starts with "per " (e.g. "per lb")
                            const isRate = /\\//.test(priceText)
                                || /^per\\s/i.test(unitText);
                            return { priceText, unitText, isRate };
                        }
                        return null;
                    }
                """)
                if _unit_info:
                    _price_raw = _unit_info.get("priceText", "")
                    _unit_text = _unit_info.get("unitText", "")
                    if _unit_info.get("isRate"):
                        # Rate item: the reliable unit is the text after "/" in the
                        # price span (e.g. "$3.99 /lb" → "lb"). The sibling span for
                        # rate items often shows a UI label ("1 each") that is not the
                        # unit — always prefer the "/" extraction.
                        _slash = _price_raw.find("/")
                        if _slash != -1:
                            _after_slash = _price_raw[_slash + 1:].strip()
                            if re.match(r'^\d', _after_slash):
                                quantity = _after_slash     # "/5.6 lb" → pkg weight
                            elif _after_slash and re.match(
                                r'^(?:lb|lbs|oz|fl\.?\s*oz|g|kg|ml|L|gal)\b',
                                _after_slash, re.IGNORECASE
                            ):
                                price_unit = _after_slash   # "/lb" → rate unit
                            # else: "/pkg (est.)" or other non-unit text → both null
                        elif _unit_text:
                            # Fallback: "per lb" style (no "/" in price span)
                            _norm = re.sub(
                                r'^(?:per\s+|/)', '', _unit_text, flags=re.IGNORECASE
                            ).strip()
                            if _norm and not re.match(r'^\d', _norm):
                                price_unit = _norm
                    elif _unit_text and not re.match(
                        r'^\d*\s*each$', _unit_text, re.IGNORECASE
                    ):
                        # Fixed package with a meaningful quantity (e.g. "18 ct", "24 oz").
                        # Skip "each" / "1 each" — single fixed-price item, qty in name.
                        quantity = _unit_text
                    # "each" / "1 each" → both fields stay null
            except Exception:
                pass

            # Regex fallback for quantity: extract package size from the product name
            # when the mini-header unit span is absent or returned "each".
            # Two-pass: prefer count/pack descriptors (e.g. "12-count", "6 pk") over
            # weight/volume (e.g. "2.05 oz") so multi-pack Costco items resolve
            # to the pack count rather than the per-unit size.
            # The separator allows optional whitespace OR a hyphen ("12-count").
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

            # Image URL: the main product image lives inside .ic-image-zoomer
            # (a stable non-obfuscated class). Falls back to the first <img> with
            # a non-empty alt attribute if the zoomer is absent.
            # Instacart's "missing-item" placeholder is not a real image — null it out.
            image_url = await page.evaluate("""
                () => {
                    const dialog = document.querySelector(
                        '[role="dialog"][aria-label="item details"]'
                    );
                    if (!dialog) return null;
                    const zoomer = dialog.querySelector('.ic-image-zoomer img');
                    if (zoomer && zoomer.src) return zoomer.src;
                    const fallback = dialog.querySelector('img[alt]');
                    return fallback ? fallback.src : null;
                }
            """)
            if image_url and "missing-item" in image_url:
                image_url = None

            # Description: inside the container whose sibling <h2> reads "Details".
            # Structure confirmed from inspect element:
            #   <div tabindex="-1" id="item_details-...-Details">
            #     <h2>Details</h2>
            #     <div><p>description text</p></div>
            #   </div>
            description = await page.evaluate("""
                () => {
                    const dialog = document.querySelector(
                        '[role="dialog"][aria-label="item details"]'
                    );
                    if (!dialog) return null;
                    for (const h of dialog.querySelectorAll('h2')) {
                        if (h.textContent.trim() === 'Details') {
                            const container = h.closest('[tabindex="-1"]') || h.parentElement;
                            const p = container ? container.querySelector('p') : null;
                            return p ? p.textContent.trim() : null;
                        }
                    }
                    return null;
                }
            """)

            # Out-of-stock detection: an <h2> inside the dialog reads "Out of stock"
            # when the item is unavailable. The "Current price:" span is absent in
            # this state, so we fall back to a different price extraction path.
            try:
                out_of_stock = await page.evaluate("""
                    () => {
                        const dialog = document.querySelector(
                            '[role="dialog"][aria-label="item details"]'
                        );
                        if (!dialog) return false;
                        for (const h of dialog.querySelectorAll('h2')) {
                            if (h.textContent.trim().toLowerCase() === 'out of stock')
                                return true;
                        }
                        return false;
                    }
                """)
            except Exception:
                pass

            # Price extraction:
            # In-stock: look for screen-reader-only leaf <span> starting with
            #   "Current price:" — e.g. "Current price: $1.99 /lb".
            # Out-of-stock: that span is absent; fall back to the first leaf
            #   <span> in the dialog whose text matches /^$[\d.,]+/ (the visible
            #   price shown in the dialog header, e.g. "$5.97").
            try:
                price_text = await page.evaluate("""
                    () => {
                        const dialog = document.querySelector(
                            '[role="dialog"][aria-label="item details"]'
                        );
                        if (!dialog) return null;
                        const spans = dialog.querySelectorAll('span');

                        // Primary: screen-reader-only "Current price:" span (in-stock).
                        // Extract just the dollar amount (e.g. "$1.99") — the unit
                        // qualifier is captured separately in price_unit.
                        for (const s of spans) {
                            if (s.childElementCount !== 0) continue;
                            const t = s.textContent.trim();
                            if (t.startsWith('Current price:')) {
                                const full = t.replace('Current price:', '').trim();
                                const m = full.match(/^(\\$[\\d.,]+)/);
                                return m ? m[1] : full;
                            }
                        }

                        // Fallback: first leaf span that looks like a bare price
                        // (out-of-stock items show the last known price this way).
                        for (const s of spans) {
                            if (s.childElementCount !== 0) continue;
                            const t = s.textContent.trim();
                            const m = t.match(/^(\\$[\\d.,]+)/);
                            if (m) return m[1];
                        }

                        return null;
                    }
                """)
            except Exception as exc:
                result["errors"].append(f"Card {i}: price read error: {exc}")

            # If either field is still missing, grab the detail overlay HTML for inspection.
            if name_text is None or price_text is None:
                try:
                    detail_html_snippet = (await page.inner_html("main"))[:1200]
                except Exception:
                    detail_html_snippet = "(could not read detail HTML)"

            # Close the dialog with Escape — much faster than go_back() because
            # the dialog is an overlay; the search results page never unloaded.
            try:
                await page.keyboard.press("Escape")
                await page.wait_for_selector(
                    DETAIL_DIALOG_SELECTOR, state="hidden", timeout=3_000
                )
            except PlaywrightTimeoutError:
                result["errors"].append(f"Card {i}: dialog did not close after Escape")
                break
            except Exception as exc:
                result["errors"].append(f"Card {i}: dialog close error: {exc}")
                break

        result["products"].append({
            "store":               store_name,
            "name":                name_text,
            "price":               price_text,
            "price_unit":          price_unit,
            "quantity":            quantity,
            "image_url":           image_url,
            "description":         description,
            "out_of_stock":        out_of_stock,
            "name_missing":        name_text is None,
            "price_missing":       price_text is None,
            "detail_html_snippet": detail_html_snippet,
        })

    return result


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

async def run_diagnostics(
    ingredients: list[str] | None = None,
    output_dir: Path | None = None,
) -> dict:
    """
    Run diagnostic scrapes for each ingredient and write results to output_dir.
    Returns the summary dict (also written to output_dir/summary.json).

    Parameters
    ----------
    ingredients : list of query strings (defaults to TEST_INGREDIENTS)
    output_dir  : directory for output files (defaults to ./test_output/)
    """
    queries    = ingredients or TEST_INGREDIENTS
    out        = output_dir or OUTPUT_DIR
    out.mkdir(parents=True, exist_ok=True)

    all_results = []

    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=False,  # headful so we can see what's happening
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

        # Single page reused across queries to preserve any session cookies
        # set after the first navigation (e.g. location cookie).
        page = await context.new_page()

        for query in queries:
            print(f"\n{'='*60}")
            print(f"  Testing query: '{query}'")
            print(f"{'='*60}")

            result = await scrape_query(page, query)
            all_results.append(result)

            # Write per-query raw output.
            safe_name = re.sub(r"[^\w]+", "_", query)
            raw_path  = out / f"raw_{safe_name}.json"
            raw_path.write_text(json.dumps(result, indent=2))
            print(f"  -> Saved: {raw_path}")

            # Quick console report.
            _print_query_report(result)

        await browser.close()

    summary = _build_summary(queries, all_results)
    summary_path = out / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))

    _print_final_summary(summary)
    print(f"\nFull summary -> {summary_path}")

    return summary


# ---------------------------------------------------------------------------
# Reporting helpers
# ---------------------------------------------------------------------------

def _print_query_report(r: dict) -> None:
    print(f"  Page title    : {r['page_title']!r}")
    print(f"  Login wall    : {r['login_wall']}")
    print(f"  Location wall : {r['location_wall']}")
    print(f"  Blocked       : {r['blocked']}")
    print(f"  Grid found    : {r['grid_found']}")
    print(f"  Cards found   : {r['card_count']}")

    products    = r["products"]
    complete    = sum(1 for p in products if not p["name_missing"] and not p["price_missing"])
    no_name     = sum(1 for p in products if p["name_missing"])
    no_price    = sum(1 for p in products if p["price_missing"])
    oos         = sum(1 for p in products if p.get("out_of_stock"))

    print(f"  Products      : {len(products)} total, {complete} complete, "
          f"{no_name} missing name, {no_price} missing price, {oos} out of stock")

    if r["errors"]:
        print("  Errors:")
        for e in r["errors"]:
            print(f"    ✗ {e}")
    else:
        print("  Errors        : none")


def _build_summary(queries: list[str], results: list[dict]) -> dict:
    per_query = []
    for r in results:
        products = r["products"]
        complete = sum(
            1 for p in products
            if not p["name_missing"] and not p["price_missing"]
        )
        per_query.append({
            "query":           r["query"],
            "login_wall":      r["login_wall"],
            "location_wall":   r["location_wall"],
            "blocked":         r["blocked"],
            "grid_found":      r["grid_found"],
            "card_count":      r["card_count"],
            "complete_count":  complete,
            "errors":          r["errors"],
        })

    any_login    = any(r["login_wall"]    for r in results)
    any_location = any(r["location_wall"] for r in results)
    any_blocked  = any(r["blocked"]       for r in results)
    all_grids    = all(r["grid_found"]    for r in results)
    total_cards  = sum(r["card_count"]    for r in results)
    total_complete = sum(q["complete_count"] for q in per_query)

    return {
        "run_timestamp":      datetime.utcnow().isoformat() + "Z",
        "queries_tested":     queries,
        "selectors_used": {
            "item_card":    ITEM_CARD_SELECTOR,
            "detail_dialog": DETAIL_DIALOG_SELECTOR,
            "detail_name":  DETAIL_NAME_SELECTOR,
            "detail_price": "JS: span[text^='Current price:'] inside dialog",
        },
        "flags": {
            "any_login_wall":    any_login,
            "any_location_wall": any_location,
            "any_blocked":       any_blocked,
            "all_grids_found":   all_grids,
        },
        "totals": {
            "total_cards":    total_cards,
            "total_complete": total_complete,
        },
        "per_query": per_query,
    }


def _print_final_summary(s: dict) -> None:
    print("\n" + "="*60)
    print("  DIAGNOSTIC SUMMARY")
    print("="*60)
    flags = s["flags"]
    print(f"  Login wall encountered  : {flags['any_login_wall']}")
    print(f"  Location wall encountered: {flags['any_location_wall']}")
    print(f"  Request blocked          : {flags['any_blocked']}")
    print(f"  All grids loaded         : {flags['all_grids_found']}")
    totals = s["totals"]
    print(f"  Total product cards      : {totals['total_cards']}")
    print(f"  Complete (name+price)    : {totals['total_complete']}")
    print()
    print(f"  {'Query':<20}  {'Cards':>6}  {'Complete':>8}  {'Walls/Blocked'}")
    print(f"  {'-'*20}  {'-'*6}  {'-'*8}  {'-'*20}")
    for q in s["per_query"]:
        flags_str = ", ".join(filter(None, [
            "login"    if q["login_wall"]    else "",
            "location" if q["location_wall"] else "",
            "blocked"  if q["blocked"]       else "",
            "no-grid"  if not q["grid_found"] else "",
        ])) or "ok"
        print(f"  {q['query']:<20}  {q['card_count']:>6}  {q['complete_count']:>8}  {flags_str}")
    print("="*60)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    asyncio.run(run_diagnostics())
