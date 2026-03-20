# Shopwise

A grocery price comparison app. The Instacart scraper collects product data from multiple retailers and stores it in Supabase, which the iOS frontend reads to display prices.

## Project Structure

```
CS178-Shopwise/
├── PlayWright/
│   └── scraper.py          # Instacart scraper -> Supabase
├── SWFrontUI/              # iOS app (Xcode)
└── .env                    # Credentials (not committed)
```

## Prerequisites

- Python 3.11+
- Xcode 15+ (for the iOS app)
- A Supabase project with the `taxonomy` and `ingredients` tables (see below)

## Environment Setup

Create a `.env` file at `CS178-Shopwise/.env` with the following:

```
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_KEY=your_supabase_service_role_key
```

## Supabase Tables

The scraper reads from `taxonomy` and writes to `ingredients`.

**`taxonomy`** — ingredient list that drives all scraping:
```sql
create table taxonomy (
  ingredient text primary key
);
```

**`ingredients`** — scraped product results:
```sql
create table ingredients (
  id           text primary key,
  taxonomy     text,
  store        text,
  name         text,
  price        text,
  price_unit   text,
  quantity     text,
  image_url    text,
  description  text,
  out_of_stock boolean
);
```

## Running the Scraper

### Install dependencies

```bash
cd CS178-Shopwise/PlayWright
pip install playwright python-dotenv supabase
playwright install chromium
```

### Full run

Scrapes all ingredients in the taxonomy table and upserts results to Supabase:

```bash
python scraper.py
```

### Test run (first N ingredients only)

```bash
python scraper.py --limit 3
```

The browser runs in headed mode (visible) so Instacart's session/location cookies persist across queries. Do not close the browser window while the scraper is running.

## iOS App

Open `SWFrontUI/ShopwiseFrontEndUI.xcodeproj` in Xcode and run on a simulator or device. The app reads from the Supabase `ingredients` table.
