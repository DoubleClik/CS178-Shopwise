import re
import math
import json
import os
import urllib.request
import urllib.error
from collections import defaultdict
from typing import List, Dict, Any, Optional, Tuple, Set

import pandas as pd

try:
    from rapidfuzz import fuzz
except ImportError:
    raise ImportError(
        "rapidfuzz is required. Install it with:\n"
        "pip install rapidfuzz pandas"
    )


# ============================================================
# CONFIG
# ============================================================

VERSION = "5.0"

CATALOG_CSV_PATH = "food_catalogue.csv"

TOP_K = 5
MIN_CANDIDATE_SCORE = 35.0
MAX_PREFILTER_ROWS = 500          # raised from 300 — inverted index makes wider search cheap
MIN_CANDIDATES_AFTER_BAD_FILTER = 15
MIN_TOP_MATCH_SCORE = 60.0

# ── LLM Reranker ─────────────────────────────────────────────────────────────
RERANKER_MODEL = "claude-opus-4-6"
RERANKER_MAX_CANDIDATES = 10   # top-N fuzzy results sent to the LLM
RERANKER_MAX_TOKENS = 150      # JSON response is tiny; 150 is generous headroom

RERANKER_SYSTEM = (
    "You are a grocery product matching assistant. You receive a recipe ingredient "
    "and a list of candidate products found by fuzzy text search. Pick the single "
    "best matching product, or return null if no candidate is a reasonable match.\n\n"
    "Rules:\n"
    "- Match on what the ingredient IS, not just shared words. "
    "'peanut butter' is not plain 'butter'. 'granulated garlic' is not 'granulated sugar'.\n"
    "- A product may differ in brand, size, or preparation form and still be correct.\n"
    "- Prefer the simplest/most generic form unless the recipe specifies otherwise.\n"
    "- Return null only if every candidate is clearly the wrong food entirely.\n\n"
    "Respond with JSON only — no text outside the JSON object."
)

RERANKER_USER_TEMPLATE = (
    'Recipe ingredient: "{raw}"\n'
    'Normalized: "{normalized}"\n\n'
    "Candidates (ranked by fuzzy score):\n"
    "{candidates_json}\n\n"
    "Respond with exactly:\n"
    '{{"choice": <integer index of best candidate, or null>, "reason": "<one sentence>"}}'
)

UNITS = {
    "tsp", "teaspoon", "teaspoons",
    "tbsp", "tablespoon", "tablespoons",
    "cup", "cups",
    "oz", "ounce", "ounces",
    "lb", "lbs", "pound", "pounds",
    "g", "gram", "grams",
    "kg", "kilogram", "kilograms",
    "ml", "l", "liter", "liters",
    "pinch", "pinches",
    "dash", "dashes",
    "clove", "cloves",
    "can", "cans",
    "package", "packages",
    "pkg", "pkgs",
    "bunch", "bunches",
    "slice", "slices",
    "stick", "sticks",
    "piece", "pieces",
    "quart", "quarts",
    "pint", "pints",
    "sprig", "sprigs",
    "bag", "bags",
}

# keep "ground"
PREP_WORDS = {
    "chopped", "diced", "minced", "shredded", "grated", "sliced",
    "cubed", "peeled", "crushed", "freshly", "fresh",
    "softened", "melted", "room", "temperature", "large", "small",
    "medium", "extra", "virgin", "optional", "to", "taste",
    "thinly", "roughly", "finely", "halved", "divided",
    "boneless", "skinless", "trimmed", "cooked", "uncooked",
    "drained", "rinsed", "beaten", "packed", "frozen", "thawed",
    "lightly", "reduced", "sodium",
}

PREPARED_FOOD_TERMS = {
    "salad", "kit", "dip", "soup", "meal", "entree", "pizza",
    "sandwich", "wrap", "bowl", "plate", "platter", "snack",
    "chips", "crackers", "cookies", "bars", "dessert", "ice cream",
    "drink", "beverage", "soda", "juice cocktail", "smoothie",
    "seasoned", "marinated", "breaded", "casserole", "dinner"
}

SYNONYM_MAP = {
    "scallions": "green onions",
    "green onion": "green onions",
    "spring onions": "green onions",
    "confectioners sugar": "powdered sugar",
    "icing sugar": "powdered sugar",
    "caster sugar": "sugar",
    "bell peppers": "bell pepper",
    "tomatoes": "tomato",
    "potatoes": "potato",
    "new potatoes": "potato",
    "onions": "onion",
    "limes": "lime",
    "lemons": "lemon",
    "apples": "apple",
    "garlic cloves": "garlic",
    "chicken breasts": "chicken breast",
    "olive oil extra virgin": "olive oil",
    "evoo": "olive oil",
    "courgette": "zucchini",
    "aubergine": "eggplant",
    "coriander leaves": "cilantro",
    "italian loaf": "italian bread",
    "round italian loaf": "italian bread",
    "egg whites": "egg white",
    "hot apple cider": "apple cider",
    "chamomile tea bags": "chamomile tea",
    "aleppo pepper": "red pepper flakes",
    "moong dal": "lentils",
    "masoor dal": "red lentils",
    "urad dal": "lentils",
    "assorted dals": "lentils",
    "thai chiles": "green chiles",
    "thai chile": "green chiles",
}

GOOD_CLASSIFIERS = {
    "PRODUCE", "MEAT", "SEAFOOD", "DAIRY", "DELI", "PANTRY", "BAKERY"
}

BAD_CATEGORY_HINTS = {
    "personal care": 45.0,
    "beauty": 45.0,
    "household": 45.0,
    "cleaning": 45.0,
    "pet": 35.0,
    "pharmacy": 45.0,
    "baby care": 35.0,
}

BAD_PRODUCT_TERMS = {
    "cracker": 18.0,
    "crackers": 18.0,
    "chip": 18.0,
    "chips": 18.0,
    "stick": 12.0,
    "sticks": 12.0,
    "dip": 16.0,
    "dressing": 16.0,
    "kit": 14.0,
    "snack": 16.0,
    "cookie": 18.0,
    "cookies": 18.0,
    "candy": 18.0,
    "bar": 10.0,
    "bars": 10.0,
    "smoothie": 16.0,
    "beverage": 16.0,
    "drink": 16.0,
    "juice cocktail": 18.0,
    "meal": 18.0,
    "entree": 18.0,
    "pizza": 18.0,
    "sandwich": 18.0,
    "wrap": 18.0,
    "soap": 25.0,
    "lotion": 25.0,
    "shampoo": 25.0,
    "conditioner": 25.0,
    "gummies": 18.0,
    "crisps": 18.0,
    "peanuts": 18.0,
    "nuts": 14.0,
    "sauce": 12.0,
}

CATEGORY_BOOST_HINTS = {
    "produce": 8.0,
    "meat": 8.0,
    "seafood": 8.0,
    "dairy": 8.0,
    "pantry": 5.0,
    "spices": 5.0,
    "condiment": 2.0,
    "bakery": 7.0,
    "bread": 7.0,
    "herb": 5.0,
    "beverage": 6.0,
    "adult beverage": 20.0,
}

INGREDIENT_CATEGORY_HINTS = {
    "spinach": {"produce"},
    "kale": {"produce"},
    "lettuce": {"produce"},
    "onion": {"produce"},
    "garlic": {"produce"},
    "tomato": {"produce"},
    "potato": {"produce"},
    "apple": {"produce"},
    "banana": {"produce"},
    "lime": {"produce"},
    "lemon": {"produce"},
    "cilantro": {"produce"},
    "parsley": {"produce"},
    "zucchini": {"produce"},
    "eggplant": {"produce"},
    "squash": {"produce"},
    "acorn": {"produce"},
    "rosemary": {"produce", "spices", "herb"},
    "thyme": {"produce", "spices", "herb"},
    "sage": {"produce", "spices", "herb"},
    "chamomile": {"beverage", "pantry"},
    "tea": {"beverage", "pantry"},
    "chicken": {"meat"},
    "beef": {"meat"},
    "pork": {"meat"},
    "salmon": {"seafood"},
    "shrimp": {"seafood"},
    "milk": {"dairy"},
    "butter": {"dairy"},
    "yogurt": {"dairy"},
    "cheese": {"dairy"},
    "cream": {"dairy"},
    "cumin": {"spices", "pantry"},
    "paprika": {"spices", "pantry"},
    "salt": {"spices", "pantry"},
    "pepper": {"spices", "pantry"},
    "oil": {"pantry"},
    "flour": {"pantry"},
    "rice": {"pantry"},
    "pasta": {"pantry"},
    "bread": {"bakery", "bread"},
    "loaf": {"bakery", "bread"},
    "roll": {"bakery", "bread"},
    "bun": {"bakery", "bread"},
    "egg": {"dairy"},
    "cider": {"beverage"},
    "wine": {"beverage", "pantry"},
    "bourbon": {"adult beverage"},
    "rum": {"adult beverage"},
    "tequila": {"adult beverage"},
    "whiskey": {"adult beverage"},
    "whisky": {"adult beverage"},
    "vodka": {"adult beverage"},
    "gin": {"adult beverage"},
    "brandy": {"adult beverage"},
    "sherry": {"adult beverage", "pantry"},
    "champagne": {"adult beverage"},
    "prosecco": {"adult beverage"},
    "vermouth": {"adult beverage", "pantry"},
    "broth": {"pantry"},
    "stock": {"pantry"},
    "lentils": {"pantry"},
}

# Spirit/liqueur tokens — used to boost "Adult Beverage" category and penalise
# flavoured food products (BBQ sauces, salami, etc.) that contain spirit words.
SPIRIT_TOKENS: Set[str] = {
    "bourbon", "rum", "tequila", "whiskey", "whisky", "vodka", "gin",
    "brandy", "sherry", "mezcal", "scotch", "cognac", "champagne",
    "prosecco", "vermouth", "mescal",
}

# Compound-butter terms: when ingredient is plain dairy butter, these product types
# are false matches — the word "butter" appears as a modifier, not the main ingredient.
# Guard: "apple butter" and "nut butter" as recipe ingredients are excluded at call site.
BUTTER_COMPOUND_TERMS: List[str] = [
    "peanut butter", "almond butter", "cashew butter", "sunflower butter",
    "nut butter", "cookie butter", "butter cup", "butter cups",
    "butter pecan", "butter bean", "butter beans",
    "butter flavor", "butter flavored",
    "shea butter", "cocoa butter", "body butter",
]

# Candy/confection signals that identify an "egg" product as NOT a raw cooking egg.
CANDY_EGG_TERMS: List[str] = [
    "chocolate", "candy", "marshmallow", "creme egg", "cream egg",
    "easter", "jelly bean", "fondant",
]

# Spirit synonym map: normalize obscure/regional terms → generic catalog-searchable term.
# Applied inside normalize_ingredient so prefilter and scorer both benefit.
SPIRIT_SYNONYMS: Dict[str, str] = {
    "scotch":      "whiskey",   # no scotch in catalog; whiskey products exist
    "mezcal":      "tequila",   # only tequila spirits in catalog
    "mescal":      "tequila",
    "amontillado": "sherry",    # style → spirit type
    "oloroso":     "sherry",
    "reposado":    "tequila",   # age designation → spirit type (tequila already present but helps overlap)
    "blanco":      "tequila",
    "anejo":       "tequila",
}

FORM_PREFERENCE_HINTS = {
    "ground cumin": {"ground"},
    "ground paprika": {"ground"},
    "ground beef": {"ground"},
    "black pepper": {"ground"},
    "olive oil": {"oil"},
    "cheddar cheese": {"cheese"},
    "chicken breast": {"breast"},
    "baby spinach": {"baby"},
    "italian bread": {"bread"},
    "acorn squash": {"acorn", "squash"},
    "apple cider": {"cider"},
    "lime": {"lime"},
    "lemon": {"lemon"},
    "rosemary": {"rosemary"},
    "potato": {"potato"},
    "apple": {"apple"},
    "chamomile tea": {"tea", "chamomile"},
}

# ---------------------------------------------------------------------------
# V5: opposite modifier penalties
# Keys are modifier tokens that survive normalize_ingredient().
# Opposites list: if ANY of these appear (as whole words) in the product
# description, it means the product directly contradicts the ingredient
# modifier — hard penalise.
# The guard (modifier already present in desc) prevents false positives
# where both ingredient and product share the same modifier.
# ---------------------------------------------------------------------------
OPPOSITE_MODIFIER_PENALTIES: Dict[str, Tuple[List[str], float]] = {
    # fat level in dairy
    "full fat":     (["reduced fat", "low fat", "fat free", "nonfat", "non fat",
                       "light", "lite", "neufchatel"], 40.0),
    "fat free":     (["whole", "full fat", "regular"], 35.0),
    "nonfat":       (["whole", "full fat", "regular"], 35.0),
    # salt level (butter, broth, nuts)
    "unsalted":     (["salted", "sea salt", "with salt"], 45.0),
    "salted":       (["unsalted"], 40.0),
    # cheese sharpness
    "sharp":        (["mild", "medium"], 20.0),
    # milk fat
    "whole":        (["skim", "nonfat", "low fat", "reduced fat", "1%", "2%"], 35.0),
    "skim":         (["whole", "full fat"], 35.0),
    # egg/egg-white handled via special case in _score_candidate
}

def _word_in(phrase: str, text: str) -> bool:
    """True if `phrase` appears as whole words in `text`.
    Falls back to plain substring for patterns with non-word characters (e.g. '2%')."""
    if re.search(r"[^a-zA-Z\s]", phrase):
        return phrase in text
    return bool(re.search(r"\b" + re.escape(phrase) + r"\b", text))

STOP_TOKENS = {"and", "or", "with", "of"}

SKIP_EXACT = {
    "divided",
    "melted",
    "plus more",
    "room temperature",
    "for finishing",
    "for serving",
    "to taste",
    "optional",
    "hot water",
    "warm water",
    "cold water",
    "water",
}

SKIP_PHRASES = {
    "plus more",
    "for finishing",
    "for serving",
    "to taste",
    "room temperature",
    "stems removed",
    "cut into",
    "torn into",
    "thinly sliced",
    "roughly chopped",
    "finely chopped",
    "lightly beaten",
    "beaten",
    "cored",
    "peeled",
    "melted",
    "divided",
    "optional",
}

SKIP_PHRASE_CONTAINS = [
    "prepared according to",
    "according to package",
    "according to directions",
    "package instructions",
    "prepare according",
]

COOKWARE_HINTS = {
    "baking dish",
    "sheet pan",
    "skillet",
    "saucepan",
    "stockpot",
    "pot",
    "pan",
    "bowl",
    "dish",
    "glass dish",
    "ceramic dish",
}

ALT_SPLIT_PATTERN = re.compile(r"\s+(?:and/or|or)\s+", re.IGNORECASE)


# ============================================================
# TEXT CLEANING
# ============================================================

def safe_str(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and math.isnan(value):
        return ""
    return str(value).strip()


def parse_min_price(price_str: Any) -> Optional[float]:
    """Extract the minimum price from a semicolon-separated price string.
    Returns None if no valid price found.
    e.g. '1.49;1.49;2.49' -> 1.49
    """
    if not price_str or str(price_str).strip() in ("", "nan", "None"):
        return None
    prices = []
    for p in str(price_str).split(";"):
        p = p.strip()
        try:
            val = float(p)
            if val > 0:
                prices.append(val)
        except ValueError:
            pass
    return min(prices) if prices else None


def normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def strip_brackets_and_parens(text: str) -> str:
    text = re.sub(r"\([^)]*\)", " ", text)
    text = re.sub(r"\[[^\]]*\]", " ", text)
    return text


def remove_fractions_numbers(text: str) -> str:
    text = re.sub(r"\b\d+\s*-\s*\d+/\d+\b", " ", text)
    text = re.sub(r"\b\d+/\d+\b", " ", text)
    text = re.sub(r"\b\d+(?:\.\d+)?\b", " ", text)
    return text


def basic_clean(text: str) -> str:
    text = safe_str(text).lower()
    text = strip_brackets_and_parens(text)
    text = text.replace("&", " and ")
    text = text.replace("®", " ")
    text = re.sub(r"[^a-zA-Z\s]", " ", text)
    return normalize_spaces(text)


def singularize_token(token: str) -> str:
    if len(token) <= 3:
        return token
    if token.endswith("ies") and len(token) > 4:
        return token[:-3] + "y"
    if token.endswith("oes") and len(token) > 4:
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def dedupe_adjacent_tokens(tokens: List[str]) -> List[str]:
    deduped = []
    for token in tokens:
        if not deduped or deduped[-1] != token:
            deduped.append(token)
    return deduped


def preprocess_ingredient(raw_ingredient: str) -> str:
    """Clean modifier/garnish tails before skip logic and matching."""
    text = safe_str(raw_ingredient).strip()

    if not text:
        return ""

    text = re.sub(r"^\s*garnish\s*:\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r",\s*plus more.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r",\s*optional.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r",\s*for finishing.*$", "", text, flags=re.IGNORECASE)
    text = re.sub(r",\s*for serving.*$", "", text, flags=re.IGNORECASE)

    # Strip comma-separated list: keep only the FIRST item.
    # Guard: if everything after the first comma is prep/modifier words only
    # (e.g. "divided", "lightly beaten"), leave it alone — those get stripped
    # later by normalize_ingredient's PREP_WORDS filter.
    m = re.match(r"^([^,]+),\s*(.+)$", text)
    if m:
        rest_words = m.group(2).strip().lower().split()
        rest_is_prep_only = all(w in PREP_WORDS for w in rest_words)
        if not rest_is_prep_only:
            text = m.group(1).strip()

    # Strip bare "or" alternatives: "X or Y" → "X".
    # Guard 1: remove parenthetical "(or ...)" first — qualifiers, not alternatives.
    # Guard 2: don't strip when the word before "or" is a prep/modifier.
    text = re.sub(r"\(\s*or\s+[^)]+\)", "", text)
    m2 = re.search(r"\s+or\s+", text, flags=re.IGNORECASE)
    if m2:
        before = text[:m2.start()].strip()
        before_last = before.split()[-1].lower() if before.split() else ""
        if before_last not in PREP_WORDS:
            text = before

    if re.match(r"^\s*plus\s+\d+.*$", text, flags=re.IGNORECASE):
        return ""

    return text.strip()


def looks_like_cookware(text: str) -> bool:
    t = basic_clean(text)
    return any(hint in t for hint in COOKWARE_HINTS)


def strip_quantity_like_prefix(text: str) -> str:
    text = basic_clean(text)
    text = remove_fractions_numbers(text)
    return normalize_spaces(text)


def should_skip_ingredient(raw_ingredient: str) -> Tuple[bool, str]:
    raw_ingredient = preprocess_ingredient(raw_ingredient)
    t = basic_clean(raw_ingredient)
    t_no_qty = strip_quantity_like_prefix(raw_ingredient)

    if not t:
        return True, "empty"

    if t in SKIP_EXACT:
        return True, "non-ingredient fragment"

    if looks_like_cookware(t):
        return True, "cookware/container phrase"

    for phrase in SKIP_PHRASES:
        if t == phrase:
            return True, "non-ingredient fragment"

    prep_only_tokens = {
        "divided", "melted", "optional", "room", "temperature", "plus", "more",
        "thinly", "sliced", "roughly", "finely", "chopped", "cored", "peeled",
        "cut", "into", "for", "serving", "finishing", "beaten", "lightly",
        "stems", "removed"
    }

    tokens = set(t.split())
    if tokens and tokens.issubset(prep_only_tokens):
        return True, "prep-only fragment"

    t_no_qty_clean = basic_clean(t_no_qty).strip()
    if t_no_qty_clean in {"dry", "wet", "hot", "cold", "warm", "large", "small",
                          "medium", "fresh", "frozen", "whole", "ground", "raw",
                          "cooked", "drained", "rinsed", "packed", "heaping"}:
        return True, "bare adjective fragment"

    if "plus more" in t or "for serving" in t or "for finishing" in t:
        return True, "serving note"

    for phrase in SKIP_PHRASE_CONTAINS:
        if phrase in t:
            return True, "prep instruction fragment"

    if t.startswith("plus ") and ("room temperature" in t or "optional" in t):
        return True, "leftover modifier fragment"

    if t_no_qty in {"hot water", "warm water", "cold water", "water"}:
        return True, "skip water"

    if "lemon wheel" in t_no_qty or "lemon wheels" in t_no_qty:
        return True, "garnish fragment"

    return False, ""


def extract_garnish_core(raw_ingredient: str) -> str:
    text = safe_str(raw_ingredient)
    lower = basic_clean(text)

    if not lower.startswith("garnish"):
        return text

    lower = re.sub(r"^garnish\s*", "", lower).strip()
    lower = re.sub(r"^:\s*", "", lower).strip()

    if "cinnamon" in lower:
        return "cinnamon"
    if "peppercorn" in lower:
        return "peppercorns"
    if "lemon" in lower:
        return "lemon"
    if "orange" in lower:
        return "orange"

    return lower


def split_alternative_ingredients(raw_ingredient: str) -> List[str]:
    """
    Improved splitting:
    - ghee or vegetable oil
    - Aleppo pepper or crushed red pepper flakes
    - ghee, unsalted butter, or olive oil
    - bourbon, aged rum, Scotch, mezcal, or gin
    """
    text = preprocess_ingredient(raw_ingredient)
    if not text:
        return []

    text = extract_garnish_core(text)
    simplified = strip_quantity_like_prefix(text)

    if " or " not in simplified and " and/or " not in simplified:
        return [text]

    first_pass = [p.strip(" ,") for p in ALT_SPLIT_PATTERN.split(simplified) if p.strip(" ,")]

    expanded = []
    for part in first_pass:
        comma_parts = [x.strip(" ,") for x in part.split(",") if x.strip(" ,")]
        if len(comma_parts) > 1:
            expanded.extend(comma_parts)
        else:
            expanded.append(part)

    cleaned_parts = []
    for p in expanded:
        if len(p) <= 1:
            continue

        lower = basic_clean(p)
        if "jasmine rice" in lower or "long grain rice" in lower:
            cleaned_parts.append("rice")
            continue
        if "giblet stock" in lower:
            cleaned_parts.append("chicken broth")
            continue
        if "dal" in lower or "dals" in lower:
            cleaned_parts.append("lentils")
            continue

        cleaned_parts.append(p)

    seen = set()
    result = []
    for p in cleaned_parts:
        key = basic_clean(p)
        if key in seen:
            continue
        seen.add(key)
        result.append(p)

    return result or [text]


def split_compound_ingredient(raw_ingredient: str) -> List[str]:
    text = preprocess_ingredient(raw_ingredient)
    if not text:
        return []

    lower = basic_clean(text)

    if "salt" in lower and "pepper" in lower and " and " in lower:
        parts = re.split(r"\s+and\s+", text, flags=re.IGNORECASE)
        return [p.strip(" ,") for p in parts if p.strip(" ,")]

    return [text]


def normalize_ingredient(raw_ingredient: str) -> str:
    raw_ingredient = preprocess_ingredient(raw_ingredient)
    raw_ingredient = extract_garnish_core(raw_ingredient)

    text = basic_clean(raw_ingredient)
    text = remove_fractions_numbers(text)

    text = re.sub(r"\bplus more\b.*$", " ", text)
    text = re.sub(r"\bfor serving\b.*$", " ", text)
    text = re.sub(r"\bfor finishing\b.*$", " ", text)
    text = re.sub(r"\bcut into\b.*$", " ", text)
    text = re.sub(r"\btorn into\b.*$", " ", text)
    text = re.sub(r"\bsuch as\b.*$", " ", text)
    text = re.sub(r"\babout\b.*$", " ", text)
    text = re.sub(r"\bstorebought or homemade\b.*$", " ", text)
    text = re.sub(r"\bdepending on\b.*$", " ", text)
    text = re.sub(r"^garnish\s*", " ", text)

    text = text.replace("extra virgin", "extra-virgin")
    text = text.replace("apple cider vinegar", "apple-cider-vinegar")
    # Chile flake synonyms → crushed red pepper
    text = re.sub(r"\bchile flakes\b", "crushed red pepper", text)
    text = re.sub(r"\bchili flakes\b", "crushed red pepper", text)
    text = re.sub(r"\bred pepper flakes\b", "crushed red pepper", text)
    text = re.sub(r"\bpepper flakes\b", "crushed red pepper", text)
    text = re.sub(r"\bwhite sugar\b", "granulated sugar", text)
    text = re.sub(r"\bsugar\s*\(?\s*white\b", "granulated sugar", text)
    text = re.sub(r"\bcane sugar\b", "granulated sugar", text)
    text = text.replace("chicken broth", "chicken-broth")
    text = text.replace("chicken stock", "chicken-stock")

    tokens = []
    for token in text.split():
        token = token.replace("-", " ")
        for subtoken in token.split():
            if subtoken in UNITS:
                continue
            if subtoken in PREP_WORDS:
                continue
            subtoken = singularize_token(subtoken)
            # Apply spirit synonyms: map regional/style terms → catalog-searchable spirit name
            if subtoken in SPIRIT_SYNONYMS:
                raw_lower_check = basic_clean(raw_ingredient)
                if subtoken == "scotch" and any(x in raw_lower_check for x in ["bonnet", "pepper", "chile", "chili"]):
                    pass
                else:
                    subtoken = SPIRIT_SYNONYMS.get(subtoken, subtoken)
            tokens.append(subtoken)

    cleaned = " ".join(tokens)
    cleaned = cleaned.replace("apple cider vinegar", "apple-cider-vinegar")
    cleaned = cleaned.replace("chicken broth", "chicken-broth")
    cleaned = cleaned.replace("chicken stock", "chicken-stock")
    cleaned = re.sub(r"\bof\b", " ", cleaned)
    cleaned = normalize_spaces(cleaned)

    cleaned = cleaned.replace("apple-cider-vinegar", "apple cider vinegar")
    cleaned = cleaned.replace("chicken-broth", "chicken broth")
    cleaned = cleaned.replace("chicken-stock", "chicken stock")

    cleaned = SYNONYM_MAP.get(cleaned, cleaned)

    deduped = dedupe_adjacent_tokens(cleaned.split())
    cleaned = " ".join(deduped)

    if "round italian loaf" in cleaned:
        cleaned = "italian bread"
    elif cleaned.endswith(" loaf"):
        cleaned = cleaned.replace(" loaf", " bread")

    raw_lower = basic_clean(raw_ingredient)

    if cleaned.endswith(" wheel") or cleaned.endswith(" wedge") or cleaned.endswith(" twist"):
        parts = cleaned.split()
        if parts:
            cleaned = parts[0]

    if "pink lady" in raw_lower or "gala" in raw_lower:
        if "apple" in cleaned or "apple" in raw_lower:
            cleaned = "apple"

    if "acorn" in raw_lower and "squash" in raw_lower:
        cleaned = "acorn squash"

    if "new potato" in raw_lower or "new potatoes" in raw_lower:
        cleaned = "potato"

    if "jasmine rice" in raw_lower or "long grain rice" in raw_lower:
        cleaned = "rice"

    if "giblet stock" in raw_lower:
        cleaned = "chicken broth"

    if "dal" in raw_lower or "dals" in raw_lower:
        if "masoor" in raw_lower:
            cleaned = "red lentils"
        else:
            cleaned = "lentils"

    if cleaned == "egg":
        cleaned = "egg"
    if cleaned == "egg white":
        cleaned = "egg white"

    return normalize_spaces(cleaned)


def normalize_catalog_text(text: str) -> str:
    text = basic_clean(text)
    tokens = [singularize_token(tok) for tok in text.split()]
    return normalize_spaces(" ".join(tokens))


def important_tokens(text: str) -> List[str]:
    tokens = []
    for tok in normalize_ingredient(text).split():
        if tok in STOP_TOKENS:
            continue
        if len(tok) <= 1:
            continue
        tokens.append(tok)
    return tokens


# ============================================================
# MATCHER
# ============================================================

class IngredientMatcher:
    def __init__(self, catalog_csv_path: str, use_reranker: bool = False, anthropic_api_key: Optional[str] = None):
        self.catalog_csv_path = catalog_csv_path
        self.df = self._load_catalog(catalog_csv_path)
        self._index, self._prefix_index = self._build_index()
        self.use_reranker = use_reranker
        # API key: explicit arg → ANTHROPIC_API_KEY env var → None (reranker disabled)
        self._api_key = anthropic_api_key or os.environ.get("ANTHROPIC_API_KEY")
        if use_reranker and not self._api_key:
            raise ValueError(
                "use_reranker=True requires an Anthropic API key. "
                "Pass anthropic_api_key= or set the ANTHROPIC_API_KEY environment variable."
            )

    # Mapping from new-format classifier labels → category strings the scorer understands.
    # NOTE: the new-format classifiers are ML-generated for recipe context and are noisy
    # (e.g. ALCOHOL is assigned to candy, soda, cooking sauces). We map the reliable
    # ones and leave unreliable ones as empty so they don't pollute category boosts.
    _NEW_FORMAT_CLASSIFIER_TO_CATEGORY: Dict[str, str] = {
        "PRODUCE":    "Produce",
        "PROTEIN":    "Meat & Seafood",
        "GRAIN":      "Pantry",
        "SPICE":      "Spices & Seasonings",
        "CONDIMENT":  "Condiment & Sauces",
        "OIL_FAT":    "Pantry",
        "BAKING":     "Baking Goods",
        "CANNED_GOOD": "Canned & Packaged",
        "NUT_SEED":   "Pantry",
        "FRESH_HERB": "Produce",
        "SWEETENER":  "Baking Goods",
        "THICKENER":  "Pantry",
        # DAIRY and ALCOHOL are intentionally omitted — too noisy in practice.
        # DAIRY fires on chips/crackers; ALCOHOL fires on candy/soda/sauces.
        # OTHER_INGR is a catch-all with no useful signal.
    }

    def _load_catalog(self, path: str) -> pd.DataFrame:
        df = pd.read_csv(path)

        # ── Auto-detect catalog format ───────────────────────────────────────
        # Format A (food_catalogue.csv): 'description', 'categories', 'classifier', 'search_keyword'
        # Format B (kroger_ingredients_rows.csv): 'name', 'classifiers' (JSON array), 'id', 'price'
        # Format C (kroger_ingredients2_rows.csv): 'name', 'classifier' (string), 'search_keyword', 'price'
        if "name" in df.columns and "classifiers" in df.columns and "description" not in df.columns:
            # Format B — old small catalog with JSON classifiers array
            df = self._adapt_new_catalog_format(df)
        elif "name" in df.columns and "classifier" in df.columns and "description" not in df.columns:
            # Format C — new priced catalog with plain string classifier + search_keyword
            df = self._adapt_priced_catalog_format(df)
        elif "name" in df.columns and "taxonomy" in df.columns and "store" in df.columns:
            # Format D — scraped_ingredients (multi-store, taxonomy-based)
            df = self._adapt_scraped_catalog_format(df)

        required_cols = [
            "productId", "brand", "description",
            "categories", "classifier", "search_keyword"
        ]
        for col in required_cols:
            if col not in df.columns:
                df[col] = ""

        for col in required_cols:
            df[col] = df[col].fillna("")

        for col in ["description", "brand", "categories", "search_keyword"]:
            if col in df.columns:
                df[col] = (df[col].astype(str)
                    .str.replace("Â®", "®", regex=False)
                    .str.replace("â„¢", "™", regex=False)
                    .str.replace("Ã©", "é", regex=False)
                    .str.replace("â€™", "'", regex=False))
        df["description_norm"] = df["description"].map(normalize_catalog_text)
        df["brand_norm"] = df["brand"].map(normalize_catalog_text)
        df["categories_norm"] = df["categories"].map(normalize_catalog_text)
        df["classifier_norm"] = df["classifier"].map(normalize_catalog_text)
        df["search_keyword_norm"] = df["search_keyword"].map(normalize_catalog_text)

        df["combined_text"] = (
            df["description_norm"] + " " +
            df["brand_norm"] + " " +
            df["categories_norm"] + " " +
            df["classifier_norm"] + " " +
            df["search_keyword_norm"]
        ).map(normalize_spaces)

        return df

    # Trailing noise words stripped when synthesizing search_keyword from product name.
    _KW_TRAILING_STOPWORDS: Set[str] = {
        "each", "bag", "pack", "packs", "can", "cans", "jar", "jars", "box", "boxes",
        "bottle", "bottles", "ct", "count", "deal", "value", "multipack", "variety",
        "bulk", "tray", "shaker", "grinder", "set", "assorted", "longneck",
    }

    def _synthesize_search_keyword(self, name: str) -> str:
        """Derive a search keyword from the trailing content words of a product name.

        Product names follow the pattern [Brand] [Adjectives] [Core Product].
        The last 1-3 meaningful words are the best proxy for what the product IS.
        This restores the 0.15 * score_keyword contribution lost when the new
        catalog format has no explicit search_keyword column.
        """
        text = re.sub(r"[®™°–]", " ", name.lower())
        text = re.sub(r"\([^)]*\)", " ", text)
        text = re.sub(r"\d+[\d./]*\s*(?:oz|lb|lbs|g|kg|ml|fl|ct|pk|ea)", " ", text)
        text = re.sub(r"[^a-z\s]", " ", text)
        text = normalize_spaces(text)
        tokens = text.split()
        # Strip trailing noise/size words
        while tokens and tokens[-1] in self._KW_TRAILING_STOPWORDS:
            tokens = tokens[:-1]
        # Return last 3 tokens — these are the core product type
        return " ".join(tokens[-3:]) if tokens else ""

    def _adapt_new_catalog_format(self, df: pd.DataFrame) -> pd.DataFrame:
        """Convert new-format catalog (name/classifiers/price) to old-format column layout."""
        import json as _json

        def parse_cls(v: str) -> List[str]:
            try:
                return _json.loads(v)
            except Exception:
                return []

        classifiers_list = df["classifiers"].map(parse_cls)

        out = pd.DataFrame()
        out["productId"]   = df.get("id", pd.Series(range(len(df))))
        out["brand"]       = df.get("brand", pd.Series([""] * len(df))).fillna("")
        out["description"] = df["name"]
        out["price"]       = df.get("price", pd.Series([None] * len(df)))

        out["categories"] = classifiers_list.map(
            lambda cls: "; ".join(
                self._NEW_FORMAT_CLASSIFIER_TO_CATEGORY[c]
                for c in cls
                if c in self._NEW_FORMAT_CLASSIFIER_TO_CATEGORY
            )
        )
        out["classifier"] = classifiers_list.map(
            lambda cls: cls[0] if cls else ""
        )
        # Synthesize search_keyword from trailing content words of the product name.
        # This restores the 0.15 * score_keyword fuzzy score contribution that the
        # old catalog provided via its explicit search_keyword column.
        out["search_keyword"] = df["name"].map(self._synthesize_search_keyword)
        out["size"]       = df.get("size", pd.Series([""] * len(df))).fillna("")
        out["image_url"]  = df.get("image", pd.Series([""] * len(df))).fillna("")
        out["store_ids"]  = df.get("store_id", pd.Series([""] * len(df))).fillna("")

        return out

    def _adapt_priced_catalog_format(self, df: pd.DataFrame) -> pd.DataFrame:
        """Convert Format C catalog (name/classifier string/search_keyword/price/store_ids)
        to the internal column layout expected by the scorer.

        This format already has:
          - 'name'           → becomes 'description'
          - 'classifier'     → single uppercase string e.g. 'PRODUCE'
          - 'categories'     → human-readable e.g. 'Produce; Produce'
          - 'search_keyword' → explicit, already synthesized
          - 'price'          → semicolon-separated per store
          - 'store_ids'      → semicolon-separated store IDs
          - 'image_url'      → product image URL
          - 'brand'          → brand name
        """
        out = pd.DataFrame()
        out["productId"]      = df.get("productId", pd.Series(range(len(df))))
        out["brand"]          = df.get("brand", pd.Series([""] * len(df))).fillna("")
        out["description"]    = df["name"]
        out["categories"]     = df.get("categories", pd.Series([""] * len(df))).fillna("")
        out["classifier"]     = df.get("classifier", pd.Series([""] * len(df))).fillna("")
        out["search_keyword"] = df.get("search_keyword", pd.Series([""] * len(df))).fillna("")
        out["price"]          = df.get("price", pd.Series([None] * len(df)))
        out["size"]           = df.get("size", pd.Series([""] * len(df))).fillna("")
        out["image_url"]      = df.get("image_url", pd.Series([""] * len(df))).fillna("")
        out["store_ids"]      = df.get("store_ids", pd.Series([""] * len(df))).fillna("")
        out["upc"]            = df.get("upc", pd.Series([""] * len(df))).fillna("")
        return out

    def _adapt_scraped_catalog_format(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Convert scraped_ingredients format to internal column layout.
        Schema: id, taxonomy, store, name, price (numeric), price_raw,
                price_unit, quantity, image_url, description, out_of_stock
        """
        out = pd.DataFrame()
        out["productId"]      = df["id"]
        out["description"]    = df["name"]
        out["brand"]          = df.get("store", pd.Series([""] * len(df))).fillna("")
        out["categories"]     = df.get("taxonomy", pd.Series([""] * len(df))).fillna("")
        out["classifier"]     = df.get("taxonomy", pd.Series([""] * len(df))).fillna("")
        out["search_keyword"] = df.get("taxonomy", pd.Series([""] * len(df))).fillna("")
        out["size"]           = df.get("quantity", pd.Series([""] * len(df))).fillna("")
        out["image_url"]      = df.get("image_url", pd.Series([""] * len(df))).fillna("")
        out["store_ids"]      = df.get("store", pd.Series([""] * len(df))).fillna("")
        out["price_raw"]      = df.get("price_raw", pd.Series([""] * len(df))).fillna("")
        # price is already a single numeric — store as both price (for parse_min_price)
        # and min_price (direct use). parse_min_price handles plain "1.79" correctly.
        _price = df.get("price", pd.Series([""] * len(df))).fillna("").astype(str)
        out["price"]          = _price
        out["min_price"]      = pd.to_numeric(_price, errors="coerce")
        return out

    # ------------------------------------------------------------------
    # V5: inverted index — built once at load time, O(1) per token lookup
    # ------------------------------------------------------------------

    def _build_index(self) -> Tuple[Dict[str, Set[int]], Dict[str, Set[int]]]:
        """
        Build two lookup structures at load time so _prefilter_candidates
        never scans the full dataframe with per-row regex.

        _index        : exact token  -> set of positional row indices (int)
        _prefix_index : 4-char prefix -> set of positional row indices (int)
                        (fallback for rare / morphologically-varied tokens)

        Both store *positional* indices (0..len(df)-1) so iloc retrieval
        is fast and label-agnostic.
        """
        index: Dict[str, Set[int]] = defaultdict(set)
        prefix_index: Dict[str, Set[int]] = defaultdict(set)

        for pos, combined in enumerate(self.df["combined_text"]):
            for tok in combined.split():
                if len(tok) < 2:
                    continue
                index[tok].add(pos)
                if len(tok) >= 4:
                    prefix_index[tok[:4]].add(pos)

        return index, prefix_index

    def _prefilter_candidates(self, normalized_ingredient: str) -> pd.DataFrame:
        tokens = important_tokens(normalized_ingredient)

        if not tokens:
            return self.df.head(MAX_PREFILTER_ROWS).copy()

        # -- 1. Exact-token lookup (O(tokens) dict hits) ----------------------
        candidate_positions: Set[int] = set()
        for tok in tokens:
            candidate_positions |= self._index.get(tok, set())

        # -- 2. Prefix fallback for tokens that had zero exact hits -----------
        # Catches plural/stem mismatches and lightly misspelled ingredients.
        for tok in tokens:
            if not self._index.get(tok) and len(tok) >= 4:
                candidate_positions |= self._prefix_index.get(tok[:4], set())

        # -- 3. Full-catalog safety net ---------------------------------------
        if not candidate_positions:
            candidates = self.df.copy()
        else:
            candidates = self.df.iloc[sorted(candidate_positions)].copy()

        # -- 4. Drop obvious non-food categories ------------------------------
        bad_mask = candidates["categories_norm"].str.contains(
            "personal care|beauty|household|cleaning|pet|pharmacy",
            regex=True,
            na=False,
        )
        if (~bad_mask).sum() >= MIN_CANDIDATES_AFTER_BAD_FILTER:
            candidates = candidates[~bad_mask].copy()

        # -- 5. Rank by token overlap, then alpha — pure set math, no regex --
        token_set = set(tokens)
        candidates["token_overlap_count"] = candidates["combined_text"].map(
            lambda text: len(token_set & set(text.split()))
        )

        candidates = candidates.sort_values(
            by=["token_overlap_count", "description_norm"],
            ascending=[False, True],
        ).head(MAX_PREFILTER_ROWS)

        return candidates

    def _score_candidate(self, normalized_ingredient: str, row: pd.Series) -> Tuple[float, Dict[str, float]]:
        desc = safe_str(row["description_norm"])
        cats = safe_str(row["categories_norm"])
        classifier = safe_str(row["classifier_norm"])
        keyword = safe_str(row["search_keyword_norm"])
        combined = safe_str(row["combined_text"])

        ingredient_tokens = important_tokens(normalized_ingredient)
        ingredient_token_set: Set[str] = set(ingredient_tokens)
        combined_tokens = set(combined.split())

        score_desc_ratio = float(fuzz.ratio(normalized_ingredient, desc))
        score_desc_partial = float(fuzz.partial_ratio(normalized_ingredient, desc))
        score_desc_token = float(fuzz.token_sort_ratio(normalized_ingredient, desc))
        score_combined = float(fuzz.token_sort_ratio(normalized_ingredient, combined))
        score_keyword = float(fuzz.token_sort_ratio(normalized_ingredient, keyword)) if keyword else 0.0

        overlap = len(ingredient_token_set & combined_tokens)
        n_tokens = max(len(ingredient_tokens), 1)
        if n_tokens == 1:
            # Single-token ingredients: log scaling only — coverage ratio is trivially 1.0
            # and would inflate noise matches on common words (salt, pepper, butter, etc.)
            overlap_score = math.log1p(overlap) * 12.0
        else:
            # Multi-token: coverage fraction penalises partial matches, log bonus
            # rewards absolute overlap count with diminishing returns.
            # Max ≈ 26 pts (vs old linear max of 36 for 3 tokens) — reduces inflation
            # from long catalog descriptions that happen to contain all tokens.
            overlap_score = (overlap / n_tokens) * 18.0 + math.log1p(overlap) * 6.0

        exact_phrase_boost = 0.0
        if normalized_ingredient == desc:
            exact_phrase_boost += 25.0
        elif normalized_ingredient in desc:
            exact_phrase_boost += 18.0
        elif normalized_ingredient in combined:
            exact_phrase_boost += 10.0

        category_boost = 0.0
        cats_lower = cats.lower()
        classifier_lower = classifier.lower()
        classifier_upper = safe_str(row.get("classifier", "")).upper()
        desc_lower = desc.lower()

        if classifier_upper in GOOD_CLASSIFIERS:
            category_boost += 4.0

        hints = set()
        for token in ingredient_token_set:
            hints |= INGREDIENT_CATEGORY_HINTS.get(token, set())

        for hint in hints:
            if hint in cats_lower:
                category_boost += CATEGORY_BOOST_HINTS.get(hint, 0.0)
            if hint in classifier_lower:
                category_boost += CATEGORY_BOOST_HINTS.get(hint, 0.0)

        # Spirit ingredients: penalise flavoured foods that use spirit words as flavouring
        if ingredient_token_set & SPIRIT_TOKENS:
            if any(x in desc_lower for x in [
                "bbq", "barbecue", "baked beans", "marinade", "seasoning",
                "salami", "cashews", "pulled pork", "raisin", "ice cream",
                "pudding", "morsels", "chips", "gummy", "gummies", "vinegar",
                "shampoo", "lipstick",
            ]):
                category_boost -= 30.0

        form_boost = 0.0
        preferred_terms = FORM_PREFERENCE_HINTS.get(normalized_ingredient, set())
        for term in preferred_terms:
            if term in desc_lower:
                form_boost += 8.0

        penalty = 0.0

        # -- V5: opposite modifier penalty ------------------------------------
        modifier_penalty = 0.0
        for modifier, (opposites, pen_value) in OPPOSITE_MODIFIER_PENALTIES.items():
            if not _word_in(modifier, normalized_ingredient):
                continue
            # Skip if the product description already confirms the same modifier
            if _word_in(modifier, desc_lower):
                continue
            for opp in opposites:
                if _word_in(opp, desc_lower):
                    modifier_penalty += pen_value
                    break
        penalty += modifier_penalty

        for bad_cat, penalty_value in BAD_CATEGORY_HINTS.items():
            if bad_cat in cats_lower or bad_cat in classifier_lower:
                penalty += penalty_value

        for bad_term, penalty_value in BAD_PRODUCT_TERMS.items():
            if bad_term in desc_lower and bad_term not in normalized_ingredient:
                penalty += penalty_value

        for bad_term in PREPARED_FOOD_TERMS:
            if bad_term in desc_lower and bad_term not in normalized_ingredient:
                penalty += 8.0

        if "dip" in desc_lower and "dip" not in normalized_ingredient:
            penalty += 10.0
        if "salad" in desc_lower and "salad" not in normalized_ingredient:
            penalty += 8.0
        if "dressing" in desc_lower and "dressing" not in normalized_ingredient:
            penalty += 10.0
        if "kit" in desc_lower and "kit" not in normalized_ingredient:
            penalty += 8.0

        if "olive oil" in normalized_ingredient:
            if "personal care" in cats_lower or "beauty" in cats_lower:
                penalty += 50.0
            if any(x in desc_lower for x in ["soap", "hair", "skin", "body"]):
                penalty += 50.0
            if "oil" in desc_lower:
                form_boost += 8.0
            if "pantry" in cats_lower or "baking" in cats_lower:
                category_boost += 6.0

        if "cheese" in normalized_ingredient:
            if any(x in desc_lower for x in ["cracker", "crackers", "dip", "snack", "stick", "sticks"]):
                penalty += 24.0
            if "dairy" in cats_lower:
                category_boost += 10.0

        if "butter" in normalized_ingredient:
            # Guard: recipe ingredients that are themselves nut/seed butters are fine.
            _ing_is_nut_butter = any(
                x in normalized_ingredient
                for x in ["peanut", "almond", "cashew", "sunflower", "apple", "nut butter"]
            )
            if not _ing_is_nut_butter:
                # Penalise compound-butter products (nut butters, flavored, cosmetic)
                for _bt in BUTTER_COMPOUND_TERMS:
                    if _bt in desc_lower:
                        penalty += 40.0
                        break
                # Penalise personal-care products containing "butter" as an ingredient
                if any(x in desc_lower for x in ["shampoo", "moisturizing", "healing balm", "skin protectant"]):
                    penalty += 50.0
                # Boost when product is actual dairy butter (classifier or category)
                if "dairy" in cats_lower or "dairy" in classifier_lower:
                    category_boost += 10.0

        if normalized_ingredient == "garlic":
            if "produce" in cats_lower:
                category_boost += 10.0
            if "paste" in desc_lower or "stir in" in desc_lower:
                penalty += 8.0

        # onion, red onion, white onion — all variants share the same rules
        if "onion" in normalized_ingredient and "pearl" not in normalized_ingredient:
            if "green onion" in desc_lower or "scallion" in desc_lower:
                penalty += 20.0
            if "pearl" in desc_lower:
                # pearl onions are a completely different product (tiny, pickled/braised)
                penalty += 35.0
            if _word_in("leek", desc_lower) or _word_in("leeks", desc_lower):
                penalty += 30.0
            if "produce" in cats_lower:
                category_boost += 12.0

        if normalized_ingredient in {"lime", "lemon"}:
            if "juice" in desc_lower and "juice" not in normalized_ingredient:
                penalty += 18.0
            if "sauce" in desc_lower:
                penalty += 20.0
            if "produce" in cats_lower:
                category_boost += 14.0

        if "rosemary" in normalized_ingredient:
            if any(x in desc_lower for x in ["crisps", "cracker", "crackers", "snack"]):
                penalty += 25.0
            if "produce" in cats_lower or "spices" in cats_lower:
                category_boost += 10.0

        if "sage" in normalized_ingredient:
            if any(x in desc_lower for x in ["sausage", "carrot", "glazed", "snack"]):
                penalty += 14.0
            if "produce" in cats_lower or "spices" in cats_lower:
                category_boost += 8.0

        if "thyme" in normalized_ingredient:
            if "produce" in cats_lower or "spices" in cats_lower:
                category_boost += 8.0

        if "celery" in normalized_ingredient:
            # celery root (celeriac) is a completely different vegetable
            if "root" in desc_lower or "celeriac" in desc_lower:
                penalty += 40.0
            # celery seed is a spice, not the vegetable
            if "seed" in desc_lower and "stalk" not in desc_lower:
                penalty += 30.0
            if "produce" in cats_lower:
                category_boost += 8.0

        if "chicken breast" in normalized_ingredient:
            if any(x in desc_lower for x in ["nugget", "nuggets", "tender", "tenders", "patty", "patties", "breaded"]):
                penalty += 30.0
            if "meat" in cats_lower or "seafood" in cats_lower:
                category_boost += 8.0

        if "spinach" in normalized_ingredient:
            if any(x in desc_lower for x in ["dip", "salad kit", "kit"]):
                penalty += 20.0
            if "produce" in cats_lower:
                category_boost += 8.0

        if normalized_ingredient == "ground cumin":
            if "seed" in desc_lower:
                penalty += 12.0
            if "ground" in desc_lower:
                form_boost += 10.0

        if normalized_ingredient == "salt":
            if any(x in desc_lower for x in ["peanut", "peanuts", "nut", "nuts", "snack"]):
                penalty += 30.0
            if "spices" in cats_lower or "pantry" in cats_lower:
                category_boost += 8.0

        if "sugar" in normalized_ingredient:
            # "Zero sugar" / "sugar free" / "no sugar added" products are about removing
            # sugar, not providing it — wrong match for a baking sugar ingredient.
            if any(x in desc_lower for x in [
                "zero sugar", "sugar free", "sugar-free",
                "no sugar added", "no added sugar", "reduced sugar",
            ]):
                penalty += 35.0
            # "Granulated garlic" shares the word "granulated" with "granulated sugar"
            # and fuzzy scoring can rank it above actual sugar products.
            elif "garlic" in desc_lower and "sugar" not in desc_lower:
                penalty += 45.0
            # General: savory seasoning/sauce products without "sugar" in name
            # should not match a plain sugar ingredient.
            elif normalized_ingredient in {
                "granulated sugar", "sugar", "brown sugar",
                "dark brown sugar", "powdered sugar", "cane sugar",
            }:
                if any(x in desc_lower for x in [
                    "garlic", "onion", "chili", "pepper", "seasoning",
                    "bbq", "rub", "sauce", "marinade",
                ]) and "sugar" not in desc_lower:
                    penalty += 40.0

        if normalized_ingredient in {"egg", "egg white", "egg yolk"}:
            if any(x in desc_lower for x in ["peanut", "peanuts", "noodle", "noodles", "snack"]):
                penalty += 35.0
            # Candy/confection products that happen to be egg-shaped or named "egg"
            for _ct in CANDY_EGG_TERMS:
                if _ct in desc_lower:
                    penalty += 45.0
                    break
            # egg ≠ egg white product (and vice versa)
            if normalized_ingredient == "egg":
                if _word_in("whites", desc_lower) or "liquid egg white" in desc_lower:
                    penalty += 30.0
                # plant-based egg substitutes are not real eggs
                if "plant based" in desc_lower or "plant-based" in desc_lower:
                    penalty += 35.0
                # egg-white bites / sandwiches are prepared foods, not raw eggs
                if _word_in("bites", desc_lower) or _word_in("sandwich", desc_lower):
                    penalty += 20.0
            if normalized_ingredient == "egg white":
                if "whole egg" in desc_lower:
                    penalty += 25.0

        if normalized_ingredient == "acorn squash":
            if "acorn" in desc_lower and "squash" in desc_lower:
                form_boost += 20.0
            elif "squash" in desc_lower:
                category_boost += 4.0
            else:
                penalty += 10.0

        if "bread" in normalized_ingredient or "loaf" in normalized_ingredient:
            if "bakery" in cats_lower or "bread" in cats_lower:
                category_boost += 14.0
            if any(x in desc_lower for x in ["bean", "beans", "mango"]) and "bread" not in desc_lower:
                penalty += 18.0

        if "squash" in normalized_ingredient:
            if "produce" in cats_lower:
                category_boost += 14.0
            if "banana" in desc_lower and "banana squash" not in normalized_ingredient:
                penalty += 16.0
            if "acorn" in normalized_ingredient and "acorn" in desc_lower:
                form_boost += 14.0
            # Baby food pouches / purees are not whole squash
            if any(x in desc_lower for x in ["baby food", "baby pouch", "kids pouch",
                                              "serenity kids", "puree pouch", "squeeze pouch",
                                              "toddler", "stage 2", "stage 3"]):
                penalty += 60.0

        if normalized_ingredient == "apple cider":
            if "vinegar" in desc_lower:
                penalty += 35.0
            if "gummies" in desc_lower:
                penalty += 30.0
            if "cider" in desc_lower or "beverage" in cats_lower or "drink" in desc_lower:
                form_boost += 10.0

        if normalized_ingredient == "potato":
            if "produce" in cats_lower:
                category_boost += 14.0
            if "potato" in desc_lower:
                form_boost += 10.0
            if "chip" in desc_lower or "chips" in desc_lower:
                penalty += 25.0

        if normalized_ingredient == "apple":
            if "produce" in cats_lower:
                category_boost += 14.0
            if "apple" in desc_lower:
                form_boost += 10.0
            if "juice" in desc_lower or "cider" in desc_lower or "butter" in desc_lower:
                penalty += 14.0

        if normalized_ingredient == "chamomile tea":
            if "tea" in desc_lower:
                form_boost += 14.0
            if "beverage" in cats_lower or "pantry" in cats_lower:
                category_boost += 8.0

        if normalized_ingredient in {"bourbon", "scotch", "mezcal", "gin", "tequila", "grand marnier", "amaro averna"}:
            if any(x in desc_lower for x in ["biscuit", "sauce", "cookie", "dough"]):
                penalty += 40.0

        # ── allspice/spice: products with "chicken" in name are not a spice ──────
        PURE_SPICE_INGREDIENTS = {
            "allspice", "ground allspice", "cinnamon", "ground cinnamon",
            "nutmeg", "ground nutmeg", "cloves", "ground cloves",
            "cardamom", "ground cardamom", "turmeric", "ground turmeric",
            "paprika", "smoked paprika", "cumin", "ground cumin",
            "coriander", "ground coriander", "oregano", "thyme", "rosemary",
            "sage", "bay leaf", "bay leaves", "ginger", "ground ginger",
            "cayenne", "cayenne pepper", "chili powder",
        }
        if normalized_ingredient in PURE_SPICE_INGREDIENTS:
            # Ground meat products are not spices — penalize all meat types
            _MEAT_WORDS = ["chicken", "beef", "bison", "pork", "turkey",
                           "lamb", "veal", "venison", "hamburger"]
            if any(m in desc_lower for m in _MEAT_WORDS) and "flavor" not in desc_lower:
                penalty += 50.0
            # Different spices should not substitute for each other unless very similar
            # e.g. black pepper is not allspice, paprika is not allspice
            _SPICE_MISMATCH = {
                "allspice":  ["black pepper", "white pepper", "paprika", "cayenne",
                               "chili powder", "cumin", "coriander"],
                "nutmeg":    ["black pepper", "white pepper", "paprika", "cayenne"],
                "cardamom":  ["black pepper", "white pepper", "paprika", "cayenne",
                               "coriander", "cumin"],
                "cloves":    ["black pepper", "white pepper", "paprika", "cayenne"],
            }
            if normalized_ingredient in _SPICE_MISMATCH:
                for mismatch_spice in _SPICE_MISMATCH[normalized_ingredient]:
                    if mismatch_spice in desc_lower and normalized_ingredient not in desc_lower:
                        penalty += 45.0
                        break

        # ── salt: peanuts / snacks with "salted" in name are not plain salt ─────
        _is_salt_ingredient = (
            normalized_ingredient in {"salt", "kosher salt", "sea salt", "table salt"}
            or normalized_ingredient.endswith(" salt")
            or normalized_ingredient.endswith(" kosher salt")
        )
        if _is_salt_ingredient:
            if any(x in desc_lower for x in ["peanut", "peanuts", "cashew", "almond",
                                              "pretzel", "popcorn", "chip", "cracker",
                                              "salted caramel", "salted snack"]):
                penalty += 45.0
            # "No salt added" products and canned vegetables are not plain salt
            if any(x in desc_lower for x in ["no salt added", "no-salt", "low sodium",
                                              "mixed vegetable", "canned", "vegetable blend"]):
                penalty += 60.0

        # ── fresh vegetables: cake / dessert versions are not fresh produce ──────
        FRESH_PRODUCE = {
            "carrot", "carrots", "celery", "zucchini", "squash", "beet", "beets",
            "parsnip", "turnip", "sweet potato", "yam",
        }
        if normalized_ingredient in FRESH_PRODUCE or any(
            v in normalized_ingredient for v in FRESH_PRODUCE
        ):
            if any(x in desc_lower for x in ["cake", "muffin", "cookie", "loaf",
                                              "bread", "bar", "brownie", "dessert",
                                              "smoothie", "juice blend"]):
                penalty += 40.0

        # ── egg whites: ham bites / prepared meals are not liquid egg whites ─────
        if normalized_ingredient in {"egg white", "egg whites"}:
            if any(x in desc_lower for x in ["ham", "sausage", "bacon", "gruyere",
                                              "bite", "bites", "sandwich", "wrap",
                                              "burrito", "meal", "entree"]):
                penalty += 50.0

        # ── global: clothing / apparel / personal care are never food ─────────────
        NON_FOOD_TERMS = [
            "underwear", "shirt", "pants", "jacket", "socks", "shoes",
            "deodorant", "shampoo", "conditioner", "lotion", "sunscreen",
            "cologne", "razor", "toothbrush", "toothpaste", "detergent",
            "quick-dry", "athletic wear", "sportswear", "laundry",
        ]
        if any(x in desc_lower for x in NON_FOOD_TERMS):
            penalty += 200.0

        # ── scotch bonnet pepper: spirits should not match ────────────────────────
        if "scotch bonnet" in normalized_ingredient or (
            "scotch" in normalized_ingredient and "pepper" in normalized_ingredient
        ):
            if any(x in desc_lower for x in ["whiskey", "whisky", "bourbon", "spirit", "liquor"]):
                penalty += 100.0

        # ── bourbon: wine barrel-aged products are not bourbon spirit ─────────────
        if normalized_ingredient in {"bourbon", "scotch", "mezcal", "gin", "tequila",
                                     "grand marnier", "amaro averna"}:
            if any(x in desc_lower for x in ["biscuit", "sauce", "cookie", "dough"]):
                penalty += 40.0
            if normalized_ingredient == "bourbon":
                if any(x in desc_lower for x in ["barrel aged", "barrel-aged", "wine",
                                                  "cabernet", "sauvignon", "pinot", "chardonnay"]):
                    penalty += 50.0

        # ── rosemary herb: goat cheese / deli meats are not the herb ─────────────
        if "rosemary" in normalized_ingredient:
            if any(x in desc_lower for x in ["goat cheese", "cheese", "ham", "turkey",
                                              "massage oil", "cracker", "crisps"]):
                penalty += 45.0
            if "produce" in cats_lower or "spices" in cats_lower:
                category_boost += 10.0

        # ── olive oil: mayonnaise / vinegar / dressing ≠ plain olive oil ────────
        if "olive oil" in normalized_ingredient:
            if any(x in desc_lower for x in ["mayo", "mayonnaise", "vinegar",
                                              "dressing", "marinade", "spray"]):
                penalty += 50.0

        # ── chamomile: iced/RTD tea is not chamomile tea bags ────────────────────
        if "chamomile" in normalized_ingredient:
            if any(x in desc_lower for x in ["iced tea", "half and half", "half & half",
                                              "lemon tea", "peach tea", "green tea"]):
                penalty += 40.0

        # ── miso: white vegetables / mushrooms ≠ miso paste ─────────────────────
        if "miso" in normalized_ingredient:
            if any(x in desc_lower for x in ["onion", "mushroom", "potato",
                                              "turnip", "radish", "parsnip"]):
                penalty += 55.0
            # Boost actual miso products
            if "miso" in desc_lower:
                form_boost += 20.0

        # ── flour: tortillas / chips are not plain flour ─────────────────────────
        if "flour" in normalized_ingredient and "tortilla" not in normalized_ingredient:
            if any(x in desc_lower for x in ["tortilla", "tortillas", "chip", "chips",
                                              "bread crumb", "breadcrumb", "breading"]):
                penalty += 40.0

        # ── rice: rice flour / cakes are not whole grain rice ────────────────────
        if "rice" in normalized_ingredient and "flour" not in normalized_ingredient:
            if any(x in desc_lower for x in ["rice flour", "rice cake", "rice cracker",
                                              "rice crisp", "rice puff", "rice syrup"]):
                penalty += 45.0

        # ── evaporated/condensed milk → plant-based milk penalty ──────────────────
        if any(x in normalized_ingredient for x in ["evaporated milk", "condensed milk"]):
            if any(x in desc_lower for x in ["oat milk", "oatmilk", "almond milk",
                                              "soy milk", "plant milk", "rice milk",
                                              "cashew milk", "hemp milk", "oat beverage"]):
                penalty += 70.0

        # ── vanilla extract → oat/nut milk penalty ───────────────────────────────
        if "vanilla" in normalized_ingredient and "extract" in normalized_ingredient:
            if any(x in desc_lower for x in ["oatmilk", "oat milk", "almond milk",
                                              "soy milk", "coconut milk", "plant milk"]):
                penalty += 65.0

        # ── yogurt → liquid milk penalty ─────────────────────────────────────────
        if "yogurt" in normalized_ingredient:
            if any(x in desc_lower for x in ["almond milk", "oat milk", "oatmilk",
                                              "soy milk", "rice milk", "coconut milk beverage"]):
                if "yogurt" not in desc_lower:
                    penalty += 60.0

        # ── milk: cheese / ice cream / personal care ≠ plain milk ────────────────
        if normalized_ingredient in {"whole milk", "milk", "skim milk", "lowfat milk"}:
            if any(x in desc_lower for x in ["cheese", "mozzarella", "shredded",
                                              "chocolate egg", "candy", "ice cream",
                                              "peanut butter", "frozen dessert"]):
                penalty += 50.0
            if any(x in desc_lower for x in ["deodorant", "shampoo", "lotion",
                                              "sunscreen", "body spray", "conditioner"]):
                penalty += 80.0

        # ── onion powder: fresh/diced onions ≠ onion powder ─────────────────────
        if "onion powder" in normalized_ingredient:
            if any(x in desc_lower for x in ["diced", "fresh", "whole onion",
                                              "onion bag", "fajita", "bell pepper"]):
                penalty += 40.0

        # ── brown sugar: pearl sugar / coffee pods ≠ brown sugar ─────────────────
        if "brown sugar" in normalized_ingredient:
            if "pearl" in desc_lower:
                penalty += 45.0
            if any(x in desc_lower for x in ["k-cup", "coffee pod", "bbq", "marinade"]):
                penalty += 30.0

        # ── cumin seeds: non-cumin seeds ≠ cumin ─────────────────────────────────
        if "cumin" in normalized_ingredient and "seed" in normalized_ingredient:
            if any(x in desc_lower for x in ["pumpkin", "sesame", "chia",
                                              "sunflower", "poppy", "hemp", "flax"]):
                penalty += 45.0
            if "cumin" not in desc_lower:
                penalty += 45.0

        # ── cream cheese: dairy-free / baked goods ≠ plain cream cheese ──────────
        if "cream cheese" in normalized_ingredient:
            if any(x in desc_lower for x in ["dairy free", "dairy-free", "vegan",
                                              "non dairy", "nondairy"]):
                penalty += 40.0
            if any(x in desc_lower for x in ["cinnamon roll", "carrot cake", "icing",
                                              "frosting", "imitation crab", "toaster strudel",
                                              "pastry", "cake", "sushi", "strudel"]):
                penalty += 40.0
            if "feta" in desc_lower:
                penalty += 50.0

        # ── scallion / green onion: prepared noodle dishes ≠ fresh ──────────────
        if any(x in normalized_ingredient for x in ["scallion", "green onion"]):
            if any(x in desc_lower for x in ["noodle", "pasta", "ramen", "stir fry",
                                              "sauce", "seasoning", "dip", "cream cheese"]):
                penalty += 40.0

        # ── chicken (whole): lunch meat / deli / ground / wings ≠ whole fresh chicken
        if "chicken" in normalized_ingredient:
            if any(x in desc_lower for x in ["lunch meat", "deli", "buddig",
                                              "chicken salad kit", "chicken snack"]):
                penalty += 50.0
            if "vienna sausage" in desc_lower:
                penalty += 40.0
            if "ground chicken" in desc_lower:
                penalty += 50.0
            # Wings, tenders, nuggets, strips are not a whole chicken
            if any(x in desc_lower for x in ["wing", "wings", "tender", "tenders",
                                              "nugget", "nuggets", "strip", "strips",
                                              "patty", "patties", "cutlet", "baked",
                                              "breaded", "popcorn chicken"]):
                penalty += 55.0

        # ── Italian bread loaf: bread crumbs ≠ a loaf ────────────────────────────
        if "italian" in normalized_ingredient and any(
            x in normalized_ingredient for x in ["loaf", "bread"]
        ):
            if "crumb" in desc_lower or "breadcrumb" in desc_lower:
                penalty += 50.0

        # ── sugar: egg whites / cornmeal ≠ baking sugar ──────────────────────────
        if normalized_ingredient in {"sugar", "granulated sugar", "white sugar",
                                     "cane sugar", "pure cane sugar"}:
            if any(x in desc_lower for x in ["egg white", "liquid egg", "arepa",
                                              "corn meal", "cornmeal"]):
                penalty += 60.0

        # ── lentil soup: raw dried lentils ≠ canned lentil soup ──────────────────
        if "lentil soup" in normalized_ingredient or (
            "lentil" in normalized_ingredient and "soup" in normalized_ingredient
        ):
            if "soup" in desc_lower:
                form_boost += 20.0
            if "lentil" in desc_lower and "soup" not in desc_lower:
                penalty += 35.0

        total = (
            0.20 * score_desc_ratio +
            0.25 * score_desc_partial +
            0.25 * score_desc_token +
            0.15 * score_combined +
            0.15 * score_keyword +
            overlap_score +
            exact_phrase_boost +
            category_boost +
            form_boost -
            penalty
        )

        breakdown = {
            "score_desc_ratio": round(score_desc_ratio, 2),
            "modifier_penalty": round(modifier_penalty, 2),
            "score_desc_partial": round(score_desc_partial, 2),
            "score_desc_token": round(score_desc_token, 2),
            "score_combined": round(score_combined, 2),
            "score_keyword": round(score_keyword, 2),
            "overlap_score": round(overlap_score, 2),
            "exact_phrase_boost": round(exact_phrase_boost, 2),
            "category_boost": round(category_boost, 2),
            "form_boost": round(form_boost, 2),
            "penalty": round(penalty, 2),
            "final_score": round(total, 2),
        }

        return total, breakdown

    def _confidence_label(self, score: float) -> str:
        if score >= 130:
            return "high"
        if score >= 100:
            return "medium"
        return "low"

    def _dedupe_matches(self, matches: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        seen = set()
        deduped = []
        for match in matches:
            key = (
                safe_str(match.get("description", "")).lower(),
                safe_str(match.get("brand", "")).lower()
            )
            if key in seen:
                continue
            seen.add(key)
            deduped.append(match)
        return deduped

    def _rerank(
        self,
        raw_ingredient: str,
        normalized: str,
        candidates: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """Call the Claude API to rerank fuzzy candidates.

        Returns the reranked list.  On any failure (network, parse error,
        invalid index) the original fuzzy-ranked list is returned unchanged.
        """
        if not candidates:
            return candidates

        # Build a lean candidate list for the prompt — only what the LLM needs.
        prompt_candidates = [
            {
                "index": i,
                "description": c["description"],
                "brand": c.get("brand", ""),
                "category": c.get("categories", c.get("classifier", "")),
                "fuzzy_score": c["score"],
            }
            for i, c in enumerate(candidates[:RERANKER_MAX_CANDIDATES])
        ]

        user_content = RERANKER_USER_TEMPLATE.format(
            raw=raw_ingredient,
            normalized=normalized,
            candidates_json=json.dumps(prompt_candidates, indent=2),
        )

        payload = json.dumps({
            "model": RERANKER_MODEL,
            "max_tokens": RERANKER_MAX_TOKENS,
            "system": RERANKER_SYSTEM,
            "messages": [{"role": "user", "content": user_content}],
        }).encode("utf-8")

        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "x-api-key": self._api_key,
                "anthropic-version": "2023-06-01",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, json.JSONDecodeError) as exc:
            # Network or parse failure — fall back silently
            print(f"[reranker] API call failed: {exc}; using fuzzy ranking")
            return candidates

        # Extract text content from the response
        try:
            text = next(
                block["text"]
                for block in body.get("content", [])
                if block.get("type") == "text"
            )
        except (StopIteration, KeyError):
            print("[reranker] Unexpected response structure; using fuzzy ranking")
            return candidates

        # Strip accidental markdown fences
        text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            print(f"[reranker] Could not parse JSON: {text!r}; using fuzzy ranking")
            return candidates

        choice = parsed.get("choice")
        reason = parsed.get("reason", "")

        # LLM says no candidate fits — return empty so caller shows "no match"
        if choice is None:
            return []

        # Validate the choice index
        if not isinstance(choice, int) or not (0 <= choice < len(prompt_candidates)):
            print(f"[reranker] Invalid choice index {choice!r}; using fuzzy ranking")
            return candidates

        # Promote the chosen candidate to position 0; keep the rest after
        chosen = {**candidates[choice], "reranker_reason": reason, "reranker_choice": True}
        rest = [
            {**c, "reranker_choice": False}
            for i, c in enumerate(candidates)
            if i != choice
        ]
        return [chosen] + rest

    def match_ingredient(self, raw_ingredient: str, top_k: int = TOP_K) -> Dict[str, Any]:
        raw_ingredient = preprocess_ingredient(raw_ingredient)

        skip, reason = should_skip_ingredient(raw_ingredient)
        if skip:
            return {
                "raw_ingredient": raw_ingredient,
                "normalized_ingredient": "",
                "skipped": True,
                "skip_reason": reason,
                "matches": [],
            }

        normalized = normalize_ingredient(raw_ingredient)

        if not normalized:
            return {
                "raw_ingredient": raw_ingredient,
                "normalized_ingredient": "",
                "skipped": True,
                "skip_reason": "empty after normalization",
                "matches": [],
            }

        candidates = self._prefilter_candidates(normalized)

        scored_results = []
        for _, row in candidates.iterrows():
            score, breakdown = self._score_candidate(normalized, row)
            if score < MIN_CANDIDATE_SCORE:
                continue

            _price_raw = safe_str(row.get("price", ""))
            _min_price = parse_min_price(_price_raw)
            scored_results.append({
                "productId": safe_str(row.get("productId", "")),
                "brand": safe_str(row.get("brand", "")),
                "description": safe_str(row.get("description", "")),
                "categories": safe_str(row.get("categories", "")),
                "classifier": safe_str(row.get("classifier", "")),
                "search_keyword": safe_str(row.get("search_keyword", "")),
                "image_url": safe_str(row.get("image_url", "")),
                "size": safe_str(row.get("size", "")),
                "store_ids": safe_str(row.get("store_ids", "")),
                "price_raw": _price_raw,
                "min_price": _min_price,
                "score": round(score, 2),
                "confidence": self._confidence_label(score),
                "debug": breakdown,
            })

        scored_results.sort(key=lambda x: x["score"], reverse=True)
        scored_results = self._dedupe_matches(scored_results)

        # ── LLM reranker ─────────────────────────────────────────────────────
        # Pass the top candidates to Claude, which can override the fuzzy ranking.
        # Runs even when fuzzy would have returned "no match" — the LLM may
        # confirm that nothing fits (empty return) or pick a candidate the fuzzy
        # scorer underranked.
        if self.use_reranker and scored_results:
            scored_results = self._rerank(raw_ingredient, normalized, scored_results)

        if not scored_results:
            return {
                "raw_ingredient": raw_ingredient,
                "normalized_ingredient": normalized,
                "skipped": False,
                "skip_reason": "",
                "matches": [],
            }

        if not self.use_reranker and scored_results[0]["score"] < MIN_TOP_MATCH_SCORE:
            return {
                "raw_ingredient": raw_ingredient,
                "normalized_ingredient": normalized,
                "skipped": False,
                "skip_reason": "",
                "matches": [],
            }

        # ── Price sort: among top candidates, sort cheapest first ──────────────
        # Strategy:
        #   1. The top match must score >= MIN_TOP_MATCH_SCORE (already filtered above)
        #   2. Build a candidate pool: top min(top_k*3, 15) results BUT only those
        #      that score within 40 pts of the top match — avoids cheap irrelevant
        #      products (e.g. olive oil mayo at 129 shouldn't beat olive oil at 135
        #      just because it's cheaper; but a 20pt gap is acceptable).
        #   3. Also enforce a hard floor of score >= 65 to exclude low-confidence matches.
        #   4. Re-sort pool by min_price ascending; unpriced fall to end.
        top_score = scored_results[0]["score"]
        price_floor_score = max(top_score - 40.0, 65.0)
        candidate_pool = [
            m for m in scored_results[:max(top_k * 3, 15)]
            if m["score"] >= price_floor_score
        ]
        # Fallback: if floor filtered everything, use top result only
        if not candidate_pool:
            candidate_pool = scored_results[:1]
        priced   = [m for m in candidate_pool if m["min_price"] is not None]
        unpriced = [m for m in candidate_pool if m["min_price"] is None]
        priced.sort(key=lambda x: x["min_price"])
        price_sorted = (priced + unpriced)[:top_k]

        return {
            "raw_ingredient": raw_ingredient,
            "normalized_ingredient": normalized,
            "skipped": False,
            "skip_reason": "",
            "matches": price_sorted,
        }

    def match_ingredients(self, ingredients: List[str], top_k: int = TOP_K) -> List[Dict[str, Any]]:
        results = []

        for ingredient in ingredients:
            ingredient = preprocess_ingredient(ingredient)
            if not ingredient:
                results.append({
                    "raw_ingredient": "",
                    "normalized_ingredient": "",
                    "skipped": True,
                    "skip_reason": "empty after preprocessing",
                    "matches": [],
                })
                continue

            alternatives = split_alternative_ingredients(ingredient)

            expanded_parts = []
            for alt in alternatives:
                compound_parts = split_compound_ingredient(alt)
                expanded_parts.extend(compound_parts)

            deduped_parts = []
            seen = set()
            for part in expanded_parts:
                key = basic_clean(part)
                if not key or key in seen:
                    continue
                seen.add(key)
                deduped_parts.append(part)

            if len(deduped_parts) == 1:
                results.append(self.match_ingredient(deduped_parts[0], top_k=top_k))
            else:
                option_results = []
                for part in deduped_parts:
                    option_results.append(self.match_ingredient(part, top_k=top_k))

                results.append({
                    "raw_ingredient": ingredient,
                    "normalized_ingredient": "",
                    "skipped": False,
                    "skip_reason": "",
                    "alternatives": option_results,
                    "matches": [],
                })

        return results


# ============================================================
# OPTIONAL HELPERS FOR KAGGLE-LIKE INGREDIENT LIST STRINGS
# ============================================================

# Continuation words that signal a fragment belongs to the previous item
_CONTINUATION_WORDS_RE = re.compile(
    r'^(or|and|such as|like|about|approximately|roughly|'
    # apple/pear/potato varieties
    r'honeycrisp|fuji|gala|granny|pink lady|bosc|bartlett|'
    r'russet|yukon|fingerling|red bliss|'
    # food type qualifiers that got split from their ingredient
    r'cheddar|cheese|ham|spiral|spiral ham|shank|shoulder|'
    r'breast|thigh|tenderloin|sirloin|chuck|brisket|'
    r'extract|paste|powder|flakes|leaves|seeds|beans|'
    r'roma|cherry|heirloom|beefsteak)',
    re.IGNORECASE
)
# Short prep-word fragments e.g. ['sharp cheddar', 'shredded'] → 'sharp cheddar, shredded'
_PREP_FRAGMENT_RE = re.compile(
    r'^(shredded|drained|rinsed|minced|chopped|sliced|diced|grated|melted|softened|'
    r'divided|crumbled|toasted|roasted|peeled|seeded|trimmed|halved|quartered|'
    r'packed|heaping|lightly beaten|room temperature|at room temp)',
    re.IGNORECASE
)

def _rejoin_ingredient_fragments(items: List[str]) -> List[str]:
    """Merge orphaned fragments back into the ingredient they belong to."""
    merged = []
    i = 0
    while i < len(items):
        current = items[i]
        while i + 1 < len(items):
            nxt = items[i + 1]
            open_parens = current.count('(') - current.count(')')
            if (open_parens > 0
                    or bool(_CONTINUATION_WORDS_RE.match(nxt))
                    or (bool(_PREP_FRAGMENT_RE.match(nxt)) and len(nxt.split()) <= 4)):
                current = current + ', ' + nxt
                i += 1
            else:
                break
        merged.append(current)
        i += 1
    return merged


def parse_ingredient_list_string(value: str) -> List[str]:
    """
    Split a Cleaned_Ingredients string into individual ingredient strings.

    The format is: ['item one', 'item two, with comma', 'item three']
    Delimiter between items is always the quote-comma-quote boundary: ', '
    This means commas INSIDE an ingredient (like "salt, divided") are
    preserved correctly — we never split on every comma.
    """
    text = safe_str(value).strip()
    if not text:
        return []

    text = text.strip("[]").strip()

    # Split on the exact boundary between quoted items: ',' or ","
    parts = re.split(r"""['"]\s*,\s*['"]""", text)

    cleaned = []
    for p in parts:
        p = p.strip("'\" \t\n")
        if p:
            cleaned.append(p)

    return _rejoin_ingredient_fragments(cleaned)




# ============================================================
# CLI / QUICK TEST
# ============================================================

if __name__ == "__main__":
    matcher = IngredientMatcher(CATALOG_CSV_PATH)

    test_ingredients = [
        "2 cups shredded cheddar cheese",
        "1 tbsp olive oil",
        "2 cloves garlic, minced",
        "1 large onion, thinly sliced",
        "1 lb chicken breast",
        "3 cups baby spinach",
        "1 tsp ground cumin",
        "2 russet potatoes",
        "2 limes",
        "1 sprig rosemary",
        "1 round Italian loaf, cut into 1-inch cubes",
        "ghee or vegetable oil",
        "divided",
        "1 cup hot apple cider",
        "2 medium apples (such as Gala or Pink Lady; about 14 oz. total)",
        "1 pound new potatoes (about 1 inch in diameter)",
        "¼ tsp. Aleppo pepper or ⅛ tsp. crushed red pepper flakes",
        "2 Tbsp. ghee, unsalted butter, or olive oil",
        "½ cup turkey giblet stock or reduced-sodium chicken broth",
        "Garnish: orange twist and freshly grated or ground cinnamon",
        "Kosher salt and freshly ground black pepper",
    ]

    results = matcher.match_ingredients(test_ingredients, top_k=3)

    for result in results:
        print("\n" + "=" * 90)
        print(f"RAW: {result['raw_ingredient']}")

        if "alternatives" in result:
            print("ALTERNATIVES:")
            for alt in result["alternatives"]:
                print(f"  - RAW: {alt['raw_ingredient']}")
                print(f"    NORMALIZED: {alt['normalized_ingredient']}")
                if alt.get("skipped"):
                    print(f"    SKIPPED: {alt['skip_reason']}")
                    continue
                if not alt["matches"]:
                    print("    No strong matches found.")
                    continue
                for i, match in enumerate(alt["matches"], start=1):
                    print(
                        f"    {i}. {match['description']} | "
                        f"brand={match['brand']} | "
                        f"categories={match['categories']} | "
                        f"score={match['score']} | "
                        f"confidence={match['confidence']}"
                    )
            continue

        print(f"NORMALIZED: {result['normalized_ingredient']}")

        if result.get("skipped"):
            print(f"SKIPPED: {result['skip_reason']}")
            continue

        if not result["matches"]:
            print("No strong matches found.")
            continue

        for i, match in enumerate(result["matches"], start=1):
            print(
                f"{i}. {match['description']} | "
                f"brand={match['brand']} | "
                f"categories={match['categories']} | "
                f"score={match['score']} | "
                f"confidence={match['confidence']}"
            )