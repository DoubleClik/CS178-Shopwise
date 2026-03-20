import pandas as pd
from ingredient_matcher import IngredientMatcher, parse_ingredient_list_string

CATALOG      = "scraped_ingredients_rows.csv"
NUM_RECIPES  = 1000
START_RECIPE = 0        # start from recipe index 10
OUTPUT_FILE  = "results_scraped.txt"

print(f"Loading catalog: {CATALOG}")
matcher = IngredientMatcher(CATALOG)
print(f"Ready. Testing recipes {START_RECIPE}–{START_RECIPE + NUM_RECIPES - 1}\n")

recipes = pd.read_csv("RecipesDataset_with_urls.csv")


def format_price(match):
    p = match.get("min_price")
    return f"${p:.2f}" if p else "price N/A"


def print_result(r, file, indent=""):
    raw = r["raw_ingredient"]

    if r.get("alternatives"):
        sub_with_matches = [a for a in r["alternatives"] if a.get("matches")]
        if not sub_with_matches:
            file.write(f"{indent}Ingredient: {raw}\n")
            file.write(f"{indent}  No match found\n")
            return
        file.write(f"{indent}Ingredient: {raw}  [split]\n")
        for alt in r["alternatives"]:
            if not alt.get("raw_ingredient"): continue
            if alt.get("skipped"):            continue
            if not alt.get("matches"):        continue
            print_result(alt, file, indent + "  ")
        return

    if r.get("skipped"):
        return

    file.write(f"{indent}Ingredient: {raw}\n")
    if not r["matches"]:
        file.write(f"{indent}  No match found\n")
        return

    for m in r["matches"]:
        store = m.get("brand", "")          # brand = store name in scraped catalog
        price = format_price(m)
        file.write(f"{indent}  -> [{store}] {m['description']} | {price} | score: {m['score']}\n")


with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    for i in range(START_RECIPE, START_RECIPE + NUM_RECIPES):
        row = recipes.iloc[i]
        ingredients = parse_ingredient_list_string(row["Cleaned_Ingredients"])

        f.write("\n====================================================\n")
        f.write(f"Recipe: {row['Title']}\n")
        f.write("----------------------------------------------------\n")

        print(f"  [{i+1}/{START_RECIPE + NUM_RECIPES - 1}] {row['Title']}")

        results = matcher.match_ingredients(ingredients, top_k=3)
        for r in results:
            if r.get("skipped"):
                continue
            f.write("\n")
            print_result(r, f)

print(f"\nDone. Results written to {OUTPUT_FILE}")