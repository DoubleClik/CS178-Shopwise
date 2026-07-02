# Shopwise

Shopwise is a grocery price-comparison app built for UC Riverside students. Groceries near
campus are spread across a dozen different chains (Ralphs, Food4Less, Stater Bros., Walmart,
Sprouts, ALDI, and more around Riverside, CA), each with its own app and no easy way to compare
them. Shopwise scrapes live per-store prices from Instacart's cross-retailer search for stores
in the Riverside/UCR area, stores them in Supabase, and gives the iOS app a fast way to answer
"which store has this cheapest right now" — including turning a whole recipe into the cheapest
(or fewest-stores) shopping trip. The goal is simple: save students time, hassle, and money on
groceries.

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────────────┐     ┌────────────────┐
│  taxonomy     │ --> │  Instacart        │ --> │  Supabase              │ --> │  iOS app        │
│  (search      │     │  scraper          │     │  (Postgres + Auth +    │     │  (SwiftUI, raw  │
│  terms table) │     │  (Playwright)     │     │  PostgREST)            │     │  REST calls)    │
└──────────────┘     └──────────────────┘     └───────────────────────┘     └────────────────┘
                                                        ▲
                                                        │
                                            ┌───────────────────────┐
                                            │  Kaggle_Matcher         │
                                            │  (offline recipe <->    │
                                            │  product fuzzy matcher) │
                                            └───────────────────────┘
```

1. The `taxonomy` table holds the list of ingredient search terms that drive scraping.
2. `scraper/scraper.py` opens one long-lived Instacart session and scrapes per-store prices
   for every taxonomy term.
3. Scraped results land in Supabase, keyed against `ingredients` — a curated set of bucket
   ingredient categories — so a search resolves against a fast, pre-classified set of products
   instead of raw scrape output.
4. `Kaggle_Matcher` is a separate, offline batch job: it fuzzy-matches a Kaggle recipes dataset
   (`Recipes_Kaggle`) against scraped products and precomputes `scraped_recipe_matches`, so the
   app can show "here's what this recipe costs at each store" without matching ingredients live
   on every request.
5. The iOS app talks to Supabase directly over REST (PostgREST + Supabase Auth) — no backend
   server in between.

## Project structure

```
shopwise/
├── scraper/          # Python: Instacart scraper (Playwright) -> Supabase
├── Kaggle_Matcher/    # Python: offline recipe <-> product fuzzy matcher (see below)
├── ios/               # iOS app (Swift/SwiftUI, Xcode project)
└── package.json       # reserved for future JS/TS tooling; no JS source currently in the repo
```

## Screenshots

_Placeholders — drop screenshots in `docs/screenshots/` (or wherever you prefer) and reference
them here. Suggested shots:_

- Onboarding survey (diet/allergy picker)
- Search view with results across multiple stores
- A recipe expanded, showing matched ingredients and the "Value" vs "Time Save" toggle
- Cart view, grouped by store
- Shopping list / checkout checklist
- Map view with nearby stores

## Tech stack

- **Scraper:** Python 3.11+, [Playwright](https://playwright.dev/python/) (Chromium), `supabase-py`
- **Ingredient/recipe matching:** Python, [rapidfuzz](https://github.com/rapidfuzz/RapidFuzz),
  optional LLM reranking via the Claude API
- **Database/backend:** [Supabase](https://supabase.com/) (Postgres, Auth, PostgREST, RPC functions)
- **iOS app:** Swift, SwiftUI, MapKit, CoreLocation — talks to Supabase via hand-rolled
  `URLSession` REST calls (no supabase-swift SDK)

## Setup

### Prerequisites

- Python 3.11+
- Xcode 15+ (for the iOS app)
- A Supabase project with the tables described below

### Environment variables

Create a `.env` file at the repo root:

```
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_KEY=your_supabase_service_role_key
```

### Supabase tables

**`taxonomy`** — ingredient search terms that drive scraping:
```sql
create table taxonomy (
  ingredient text primary key
);
```

**`ingredients`** — bucket ingredient categories used to classify/organize scraped products:
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

**`scraped_ingredients`** — the table the app and `Kaggle_Matcher` actually query for live,
per-store priced products (columns as read in `AuthManager.swift` /
`precompute_scraped_matches.py`):
```sql
create table scraped_ingredients (
  id           text primary key,
  taxonomy     text,
  store        text,
  name         text,
  price        numeric,
  price_raw    text,
  price_unit   text,
  quantity     text,
  image_url    text,
  out_of_stock boolean
);
```

**`scraped_recipe_matches`** — precomputed recipe-ingredient → product matches, produced by
`Kaggle_Matcher/precompute_scraped_matches.py` and read by the Recipes screen:
```sql
create table scraped_recipe_matches (
  id                  bigint primary key generated always as identity,
  recipe_id           bigint,
  recipe_title        text,
  raw_ingredient       text,
  matched_name         text,
  matched_product_id   text,
  matched_store        text,
  matched_image        text,
  matched_size         text,
  min_price            numeric,
  score                numeric,
  confidence           text,
  match_rank           int
);
```

Also used: `Recipes_Kaggle` (the source recipe dataset), `user_preferences` (diet/allergy
choices from onboarding), and `kroger_locations` (Kroger-family store locations — currently
unpopulated; the Map view falls back to a hardcoded list for those stores until it is).

### Running the scraper

```bash
cd scraper
pip install -r requirements.txt
playwright install chromium
python scraper.py            # full run: every taxonomy ingredient
python scraper.py --limit 3  # test run: first 3 ingredients only
```

The browser runs in headed (visible) mode on purpose — see "How it works" below. Don't close
the window while it's running.

### Ingredient/recipe matching (optional, offline)

```bash
cd Kaggle_Matcher
pip install rapidfuzz pandas
python precompute_scraped_matches.py
```

Safe to re-run — it skips recipes that already have matches.

### iOS app

Open `ios/ShopwiseFrontEndUI.xcodeproj` in Xcode and run on a simulator or device. The app
reads from Supabase directly; no local backend is needed.

## How it works

**Headed-browser session persistence.** The scraper opens a single Playwright/Chromium session
and reuses it across every ingredient in the taxonomy, instead of opening a fresh page per
query. Instacart sets session and location cookies on first load; reusing one browser context
lets those persist so every subsequent search stays scoped to the same delivery location —
in this case, the Riverside/UCR area — without re-negotiating it each time.

**Upsert, not insert.** Each batch of scraped rows is upserted with `on_conflict="id"`, so
re-running the scraper (or resuming after a partial run) updates existing product rows in place
instead of creating duplicates.

**Bot-detection handling, not rate-limiting.** The scraper checks each page for common
blocking signals (CAPTCHA text, "unusual traffic," HTTP 4xx) and skips a query if it's blocked,
rather than retrying immediately. To be transparent: it does **not** currently throttle or
back off between ingredient searches — there's only a short pause between paginating a single
store's product carousel. If you build on this, consider adding delays between queries; this
project scrapes a modest, fixed taxonomy list for a small number of stores near one campus, not
high-frequency or bulk collection.

**Recipe matching.** `Kaggle_Matcher` fuzzy-matches free-text recipe ingredients (e.g. "2 cups
diced tomatoes, drained") against scraped product names using rapidfuzz, with unit/prep-word
stripping and synonym normalization (e.g. "scallions" → "green onions"). It optionally reranks
top candidates with a Claude API call to disambiguate near-matches (e.g. "peanut butter" vs.
"butter"). This runs offline, once per recipe, so the app never has to fuzzy-match on the
critical path of a request.

**Client-side store optimization.** Once a recipe's matched ingredients are fetched, the app
computes two shopping strategies locally: cheapest overall ("Value") and fewest stores to visit
("Time Save", a greedy set-cover over the fetched matches, tie-broken by price) — no extra
round-trip to Supabase for either.

## Known limitations

- The iOS app persists auth tokens in `UserDefaults`, not the Keychain — fine for a class/demo
  project, but not how you'd ship this to production.
- The scraper has no rate-limiting between queries (see above).
- Kroger-family store locations in the Map view are hardcoded pending the `kroger_locations`
  table being populated.

## Credits

Shopwise was built by a four-person team:

- **Jake Wang** — Team lead; Instacart scraping pipeline and Supabase data architecture
- **James Chang** — iOS frontend (search, cart, UI)
- **Nicholas Castellanos** — iOS frontend and backend integration (Supabase auth, recipe matching, maps)
- **Shengyang "Leo" Zhou** — Database and backend integration (Supabase ingredient classification)
