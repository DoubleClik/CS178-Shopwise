import ast
import csv
import random
import re
from typing import List, Tuple


# -----------------------------
# Helper: Replace unicode fractions
# -----------------------------
def replace_unicode_fractions(text: str) -> str:
    unicode_fraction_map = {
        "¼": " 1/4 ", "½": " 1/2 ", "¾": " 3/4 ",
        "⅐": " 1/7 ", "⅑": " 1/9 ", "⅒": " 1/10 ",
        "⅓": " 1/3 ", "⅔": " 2/3 ",
        "⅕": " 1/5 ", "⅖": " 2/5 ", "⅗": " 3/5 ", "⅘": " 4/5 ",
        "⅙": " 1/6 ", "⅚": " 5/6 ",
        "⅛": " 1/8 ", "⅜": " 3/8 ", "⅝": " 5/8 ", "⅞": " 7/8 ",
    }
    for unicode_char, ascii_fraction in unicode_fraction_map.items():
        text = text.replace(unicode_char, ascii_fraction)
    return text


# -----------------------------
# Ingredient cleaner
# -----------------------------
def extract_ingredient_name(raw_ingredient: str) -> str:
    if not raw_ingredient:
        return ""

    normalized_text = replace_unicode_fractions(str(raw_ingredient).lower().strip())

    # Remove parenthetical info like "(about 3 lb. total)"
    normalized_text = re.sub(r"\([^)]*\)", " ", normalized_text)

    # Remove leading numeric quantities/ranges/mixed fractions
    normalized_text = re.sub(
        r"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d+[-–]\d+|\d+)\s*",
        " ",
        normalized_text
    )

    measurement_units = {
        "tsp", "tbsp", "cup", "cups", "lb", "lbs", "oz", "g", "kg",
        "teaspoon", "tablespoon", "pound", "ounces",
    }

    tokens = re.split(r"\s+", normalized_text)
    filtered_tokens: List[str] = []

    for token in tokens:
        cleaned_token = re.sub(r"[^\w]", "", token)
        if not cleaned_token:
            continue
        if cleaned_token.isdigit():
            continue
        if cleaned_token in measurement_units:
            continue
        filtered_tokens.append(cleaned_token)

    cleaned_text = " ".join(filtered_tokens)

    descriptor_words = {
        "small", "large", "fresh", "chopped", "minced", "diced", "ground",
        "divided", "plus", "more", "optional", "taste", "needed",
    }

    cleaned_text = " ".join(
        token for token in cleaned_text.split()
        if token not in descriptor_words
    )

    return cleaned_text.strip()


# -----------------------------
# Positives: from Ingredients column
# -----------------------------
def extract_ingredients_from_csv(csv_path: str) -> List[str]:
    cleaned_ingredient_list: List[str] = []

    with open(csv_path, newline="", encoding="utf-8") as csv_file:
        csv_reader = csv.DictReader(csv_file)

        for row in csv_reader:
            ingredient_column_value = row.get("Ingredients", "")
            try:
                parsed_ingredient_list = ast.literal_eval(ingredient_column_value)
            except Exception:
                continue

            if not isinstance(parsed_ingredient_list, list):
                continue

            for raw_ingredient in parsed_ingredient_list:
                ingredient_name = extract_ingredient_name(raw_ingredient)
                if ingredient_name:
                    cleaned_ingredient_list.append(ingredient_name)

    return cleaned_ingredient_list


# -----------------------------
# Negatives: curated + instruction snippets
# -----------------------------
def build_negative_samples(csv_path: str, target_count: int, seed: int = 42) -> List[str]:
    random.seed(seed)

    curated_negatives = [
        # tools / cookware
        "skillet", "saucepan", "baking sheet", "spatula", "whisk", "oven", "microwave",
        "knife", "cutting board", "blender", "food processor",
        # actions / instruction-like
        "preheat", "stir", "mix", "bake", "simmer", "serve", "let cool", "bring to a boil",
        "reduce heat", "remove from heat", "set aside",
        # metadata-ish
        "minutes", "hours", "temperature", "degrees", "servings",
        # non-ingredient-ish recipe phrases
        "optional", "to taste", "as needed", "for garnish",
    ]

    instruction_snippets: List[str] = []
    with open(csv_path, newline="", encoding="utf-8") as csv_file:
        csv_reader = csv.DictReader(csv_file)
        for row in csv_reader:
            instructions_text = (row.get("Instructions") or "").strip().lower()
            if not instructions_text:
                continue

            parts = re.split(r"[.\n;•]+", instructions_text)
            for part in parts:
                snippet = part.strip()
                if 3 <= len(snippet) <= 60:
                    instruction_snippets.append(snippet)

    all_candidates = curated_negatives + instruction_snippets
    all_candidates = list({c.strip() for c in all_candidates if c and c.strip()})

    if len(all_candidates) <= target_count:
        return all_candidates

    return random.sample(all_candidates, target_count)


# -----------------------------
# Dataset builder
# -----------------------------
def make_dataset(
    csv_path: str,
    max_per_class: int = 50_000,
    seed: int = 42,
    balance_classes: bool = True
) -> Tuple[List[str], List[int]]:
    random.seed(seed)

    positives = extract_ingredients_from_csv(csv_path)
    positives = [p.strip() for p in positives if p and p.strip()]
    positives = list(set(positives))  # unique helps reduce leakage
    random.shuffle(positives)
    positives = positives[:max_per_class]

    negatives_target = min(max_per_class, len(positives)) if balance_classes else max_per_class
    negatives = build_negative_samples(csv_path, target_count=negatives_target, seed=seed)
    negatives = [n.strip() for n in negatives if n and n.strip()]
    negatives = list(set(negatives))
    random.shuffle(negatives)

    if balance_classes:
        negatives = negatives[:len(positives)]
    else:
        negatives = negatives[:max_per_class]

    X = positives + negatives
    y = [1] * len(positives) + [0] * len(negatives)

    combined = list(zip(X, y))
    random.shuffle(combined)
    X, y = zip(*combined)

    return list(X), list(y)
