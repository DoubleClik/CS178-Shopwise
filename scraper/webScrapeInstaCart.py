from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
import asyncio, json

STORE_ROW_SELECTOR   = '[data-testid="CrossRetailerResultRowWrapper"]'
ITEM_CARD_SELECTOR   = '[data-testid^="item_list_item_"]'
NEXT_PAGE_SELECTOR   = '[aria-label="Next page"]'
DETAIL_DIALOG_SEL    = '[role="dialog"][aria-label="item details"]'
DETAIL_NAME_SEL      = '[aria-label="item details"] h2'
MAX_CAROUSEL_PAGES   = 10

async def scrape_instacart(query: str):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/122.0.0.0 Safari/537.36"
            )
        )
        page = await context.new_page()

        await page.goto(
            f"https://www.instacart.com/store/s?k={query.replace(' ', '+')}",
            wait_until="domcontentloaded",
        )
        await page.wait_for_selector(STORE_ROW_SELECTOR, timeout=8_000)

        # Phase 1: collect (store_name, card_element) from all store rows,
        # expanding each carousel fully before moving on.
        store_rows = await page.query_selector_all(STORE_ROW_SELECTOR)
        card_queue = []

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

            for _ in range(MAX_CAROUSEL_PAGES):
                try:
                    btn = await row.query_selector(NEXT_PAGE_SELECTOR)
                    if not btn or not await btn.is_visible():
                        break
                    await btn.click()
                    await page.wait_for_timeout(400)
                except Exception:
                    break

            for card in await row.query_selector_all(ITEM_CARD_SELECTOR):
                card_queue.append((store_name, card))

        # Phase 2: click each card, scrape name + price from the detail dialog.
        results = []
        for store_name, card in card_queue:
            try:
                await card.scroll_into_view_if_needed()
                await card.click()
                await page.wait_for_selector(DETAIL_DIALOG_SEL, timeout=6_000)
            except PlaywrightTimeoutError:
                continue

            name_text = price_text = None

            try:
                name_el   = await page.wait_for_selector(DETAIL_NAME_SEL, timeout=4_000)
                name_text = (await name_el.inner_text()).strip() or None
            except Exception:
                pass

            try:
                price_text = await page.evaluate("""
                    () => {
                        const spans = document.querySelectorAll(
                            '[role="dialog"][aria-label="item details"] span'
                        );
                        for (const s of spans) {
                            if (s.childElementCount !== 0) continue;
                            const t = s.textContent.trim();
                            if (t.startsWith('Current price:')) {
                                return t.replace('Current price:', '').trim();
                            }
                        }
                        return null;
                    }
                """)
            except Exception:
                pass

            results.append({"store": store_name, "name": name_text, "price": price_text})

            try:
                await page.keyboard.press("Escape")
                await page.wait_for_selector(DETAIL_DIALOG_SEL, state="hidden", timeout=3_000)
            except Exception:
                break

        await browser.close()
        return results

if __name__ == "__main__":
    results = asyncio.run(scrape_instacart("chicken breast"))
    print(json.dumps(results, indent=2))
