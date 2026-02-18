# Food Product Ingredient Classifier — Ollama Edition

Classifies food products as cooking ingredients using a **local LLM via Ollama**.
No API key, no subscription, no data leaves your machine.

---

## 1. Install Ollama

Download from **https://ollama.com/download** (macOS, Windows, Linux).

After installing, Ollama runs automatically in the background.
If it isn't running, start it with:
```bash
ollama serve
```

---

## 2. Pull a model

```bash
ollama pull llama3.2        # recommended — fast, accurate, ~2 GB
# alternatives:
ollama pull mistral
ollama pull gemma3
```

---

## 3. Run the classifier

```bash
python classify_ingredients.py /path/to/csv/folder
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `-o / --output` | `classified_ingredients.csv` | Output file path |
| `-m / --model`  | `llama3.2` | Any model you've pulled locally |

**Examples:**
```bash
# Use default model
python classify_ingredients.py ./data

# Use a different model, custom output file
python classify_ingredients.py ./data -m mistral -o results.csv
```

---

## Output columns

| Column | Description |
|--------|-------------|
| `name` | Product name (from source CSV) |
| `ingredient` | `True` / `False` |
| `classifiers` | Pipe-separated tags, e.g. `PROTEIN\|CANNED_GOOD` |
| `retail_price` | From source CSV |
| `thumbnailImage` | From source CSV |
| `mediumImage` | From source CSV |
| `largeImage` | From source CSV |
| `color` | From source CSV |

---

## Classifier tags

| Tag | What it covers |
|-----|---------------|
| `PROTEIN` | Meat, poultry, seafood, eggs, tofu, legumes |
| `DAIRY` | Milk, cheese, butter, cream, yogurt |
| `PRODUCE` | Fresh/frozen vegetables and fruits |
| `GRAIN` | Flour, rice, pasta, bread, oats |
| `BAKING` | Leavening, sugar, chocolate chips, extracts |
| `SPICE` | Dried spices, herbs, seasoning blends, salt |
| `OIL_FAT` | Oils, lard, shortening, ghee |
| `CONDIMENT` | Sauces, vinegars, mustard, ketchup, soy sauce |
| `CANNED_GOOD` | Canned/jarred veg, beans, broth, tomatoes |
| `SWEETENER` | Honey, maple syrup, agave, sugar (as sweetener) |
| `NUT_SEED` | Nuts, seeds, nut butters |
| `ALCOHOL` | Wine, beer, spirits used in cooking |
| `THICKENER` | Cornstarch, arrowroot, gelatin, agar |
| `FRESH_HERB` | Fresh basil, parsley, cilantro, etc. |
| `OTHER_INGR` | Genuine ingredient not fitting above |

**Not classified as ingredients:** prepared meals, beverages, supplements,
kitchen equipment, or standalone snack foods.

---

## Performance notes

- The script processes one row at a time for reliability with local models.
- Speed depends on your hardware. On a modern laptop with `llama3.2`:
  ~2–4 seconds per product on CPU, ~0.5–1s with a GPU.
- No internet connection required after the initial model pull.
