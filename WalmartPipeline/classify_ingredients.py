#!/usr/bin/env python3
"""
Food Product Ingredient Classifier — Hybrid Edition (M4 Optimised)

Three-pass strategy:
  Pass 1 — Explicit keyword rules     (~65% of products, instant)
  Pass 2 — Food-category default      (~25% more, instant, no LLM)
  Pass 3 — LLM for true unknowns      (~10% or less)

Recommended for Apple Silicon M4:
  ollama pull llama3.2:1b
  python classify_ingredients.py /path/to/folder -m llama3.2:1b -w 8 -b 25

Setup:
  1. Install Ollama:  https://ollama.com/download
  2. Pull model:      ollama pull llama3.2:1b
  3. Run:             python classify_ingredients.py /path/to/csv/folder -m llama3.2:1b -w 8
"""

import csv
import json
import time
import argparse
import urllib.request
import urllib.error
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

# ── Configuration ─────────────────────────────────────────────────────────────

DEFAULT_MODEL   = "llama3.2:1b"   # fastest model; still accurate for classification
DEFAULT_WORKERS = 8               # M4 unified memory handles this easily
DEFAULT_BATCH   = 25
OLLAMA_BASE_URL = "http://localhost:11434"

# ══════════════════════════════════════════════════════════════════════════════
#  PASS 1 — EXPLICIT KEYWORD RULES
# ══════════════════════════════════════════════════════════════════════════════

NON_INGREDIENT_KEYWORDS = {
    # Prepared / frozen meals
    "frozen meal", "frozen dinner", "frozen entree", "frozen pizza",
    "tv dinner", "microwave meal", "microwave popcorn", "heat and serve",
    "ready to eat", "ready-to-eat", "meal kit", "dinner kit", "lunch kit",
    "skillet meal", "hamburger helper", "tuna helper",
    "mac and cheese dinner", "boxed dinner",
    # Snack foods
    "potato chip", "tortilla chip", "corn chip", "pita chip",
    "cheese puff", "cheese curl", "veggie straw", "veggie chip",
    "rice cake", "popcorn", "pork rind", "pork skin",
    "pretzel bag", "snack pretzel", "snack mix",
    "snack bar", "granola bar", "cereal bar", "protein bar", "energy bar",
    "fruit snack", "fruit roll", "fruit leather", "fruit gummy",
    "gummy bear", "gummy worm", "gummy candy",
    "candy bar", "chocolate bar", "candy bag", "hard candy",
    "lollipop", "jawbreaker", "licorice", "taffy", "cotton candy",
    # Beverages
    "soda", " cola", "ginger ale", "root beer", "cream soda",
    "energy drink", "sports drink", "electrolyte drink",
    "fruit juice", "orange juice", "apple juice", "grape juice",
    "cranberry juice", "pineapple juice", "tomato juice",
    "lemonade", "limeade", "fruit punch",
    "iced tea", "sweet tea", "kombucha",
    "coffee drink", "bottled coffee", "cold brew bottle", "frappuccino",
    "smoothie bottle", "juice smoothie", "drinkable yogurt",
    "protein shake", "meal replacement shake",
    "sparkling water", "mineral water", "bottled water", "distilled water",
    "flavored water", "vitamin water", "coconut water bottle",
    "beer ", " beer", "wine bottle", "spirits bottle", "whiskey bottle",
    "vodka bottle", "rum bottle", "gin bottle", "tequila bottle",
    "hard seltzer", "hard cider",
    # Candy / confections
    "candy", "confection", "breath mint", "chewing gum", " gum ", "bubble gum",
    # Breakfast cereals
    "breakfast cereal", "corn flakes", "frosted flakes", "fruit loops",
    "froot loops", "lucky charms", "cocoa puffs", "cap'n crunch",
    "cheerios", "wheaties", "grape nuts", "honey smacks",
    "rice krispies", "special k cereal", "raisin bran",
    # Ice cream / frozen desserts
    "ice cream", "gelato", "sorbet", "sherbet", "frozen yogurt",
    "popsicle", "ice pop", "fudge bar", "ice cream bar", "ice cream sandwich",
    "drumstick cone", "klondike",
    # Pre-made bakery / desserts
    "birthday cake", "wedding cake", "sheet cake",
    "cupcake", "donut", "doughnut", "muffin pack", "danish pastry",
    "croissant pack", "cinnamon roll pack",
    "brownie pack", "cookie pack", "cookie assortment",
    "pudding cup", "jello cup", "gelatin cup", "snack pudding",
    # Supplements / vitamins
    "vitamin c", "vitamin d", "vitamin e", "vitamin a", "vitamin b",
    "multivitamin", "supplement", "probiotic", "prebiotic",
    "fish oil capsule", "omega-3 capsule",
    "protein powder", "whey protein", "casein protein",
    "plant protein powder", "creatine", "bcaa", "pre-workout",
    "melatonin", "sleep aid", "fiber supplement", "metamucil",
    "ensure bottle", "boost bottle", "pediasure",
    # Baby / infant
    "baby formula", "infant formula", "toddler formula",
    "baby food", "baby puree", "baby cereal", "gerber",
    # Pet food
    "dog food", "cat food", "puppy food", "kitten food",
    "dog treat", "cat treat", "bird seed", "fish food",
    "pet food", "pet treat",
    # Paper / cleaning / household
    "paper towel", "paper plate", "napkin pack",
    "plastic wrap", "aluminum foil",
    "zip bag", "storage bag", "freezer bag", "sandwich bag",
    "trash bag", "garbage bag",
    "dish soap", "laundry detergent", "cleaning spray", "bleach",
    # Kitchen equipment
    "cutting board", "mixing bowl", "baking sheet", "baking pan",
    "cast iron pan", "skillet pan", "saute pan", "sauce pan",
    "dutch oven", "roasting pan", "muffin tin", "loaf pan",
    "measuring cup", "measuring spoon", "spatula", "whisk",
    "can opener", "vegetable peeler",
}

NON_INGREDIENT_CATEGORIES = {
    "beverage", "drinks", "soda", "juice", "water",
    "snacks", "chips", "crackers", "popcorn",
    "candy", "confectionery", "gum",
    "ice cream", "frozen dessert", "frozen novelty",
    "frozen meals", "frozen entrees", "prepared meals",
    "breakfast cereal", "cereal",
    "supplement", "vitamins", "health supplement",
    "protein powder", "sports nutrition",
    "baby food", "baby formula", "infant",
    "pet food", "dog", "cat", "pet",
    "paper goods", "cleaning supplies", "household",
    "cookware", "bakeware", "kitchen tools",
    "personal care", "beauty", "cosmetic",
    "deli prepared", "deli meals",
}

INGREDIENT_RULES: list[tuple[set[str], list[str]]] = [
    # PRODUCE
    ({"fresh vegetable", "fresh fruit", "organic vegetable", "organic fruit",
      "frozen vegetable", "frozen fruit",
      "broccoli", "cauliflower", "spinach", "kale", "arugula", "romaine",
      "iceberg lettuce", "butter lettuce", "mixed greens", "collard greens",
      "brussels sprout", "cabbage", "bok choy", "napa cabbage",
      "carrot", "celery", "cucumber", "zucchini", "squash",
      "bell pepper", "jalapeño", "serrano pepper", "habanero",
      "poblano", "anaheim pepper", "banana pepper",
      "cherry tomato", "grape tomato", "roma tomato",
      "red onion", "yellow onion", "white onion", "shallot",
      "scallion", "green onion", "leek",
      "garlic bulb", "garlic clove", "garlic head",
      "portobello", "shiitake", "cremini", "button mushroom",
      "oyster mushroom", "enoki", "chanterelle",
      "asparagus", "artichoke", "beet", "turnip", "parsnip",
      "sweet potato", "yam", "russet potato", "red potato", "yukon gold",
      "fingerling potato", "corn on the cob", "fresh corn",
      "green bean", "snap pea", "sugar snap", "snow pea",
      "eggplant", "okra", "fennel bulb", "radish", "jicama",
      "apple", "pear", "orange", "lemon", "lime", "grapefruit",
      "banana", "mango", "pineapple", "papaya", "kiwi",
      "strawberry", "blueberry", "raspberry", "blackberry",
      "watermelon", "cantaloupe", "honeydew",
      "peach", "nectarine", "plum", "apricot", "cherry",
      "avocado", "fig", "pomegranate", "passion fruit",
      }, ["PRODUCE"]),
    # FRESH HERBS
    ({"fresh basil", "fresh parsley", "fresh cilantro", "fresh thyme",
      "fresh rosemary", "fresh mint", "fresh dill", "fresh chives",
      "fresh tarragon", "fresh oregano", "fresh sage",
      "fresh lemongrass", "fresh ginger root", "fresh turmeric root",
      "herb bunch", "herb packet",
      }, ["FRESH_HERB"]),
    # PROTEIN
    ({"chicken breast", "chicken thigh", "chicken wing", "chicken leg",
      "chicken tender", "whole chicken", "chicken drumstick",
      "ground chicken", "ground turkey", "turkey breast", "whole turkey",
      "ground beef", "beef chuck", "beef brisket", "beef rib",
      "flank steak", "skirt steak", "ribeye", "sirloin", "tenderloin",
      "beef roast", "beef stew meat", "beef short rib",
      "pork chop", "pork loin", "pork belly", "pork shoulder",
      "pork tenderloin", "baby back rib", "pork rib", "spare rib",
      "ham steak", "uncured ham", "spiral ham",
      "lamb chop", "lamb leg", "ground lamb", "rack of lamb",
      "salmon fillet", "salmon steak", "whole salmon",
      "tuna steak", "tuna fillet", "tilapia", "cod fillet", "halibut",
      "mahi mahi", "sea bass", "snapper", "trout", "catfish",
      "shrimp", "scallop", "lobster tail", "crab leg", "crab meat",
      "clam", "mussel", "oyster", "squid", "octopus",
      "bacon", "pancetta", "prosciutto", "salami", "pepperoni",
      "chorizo", "andouille", "bratwurst", "italian sausage",
      "breakfast sausage", "sausage link", "sausage patty",
      "deli turkey", "deli ham", "deli roast beef", "deli chicken",
      "lunch meat", "deli meat", "sliced meat",
      "tofu", "extra firm tofu", "silken tofu", "firm tofu",
      "tempeh", "seitan", "textured vegetable protein",
      "edamame", "black bean", "pinto bean", "kidney bean",
      "chickpea", "lentil", "split pea", "navy bean",
      "great northern bean", "cannellini bean", "fava bean",
      "dozen eggs", "large eggs", "medium eggs", "free range egg",
      "cage free egg", "organic egg", "egg whites", "liquid egg",
      }, ["PROTEIN"]),
    # DAIRY
    ({"whole milk", "skim milk", "2% milk", "1% milk", "nonfat milk",
      "reduced fat milk", "lactose free milk", "organic milk",
      "buttermilk", "evaporated milk", "condensed milk", "dry milk",
      "powdered milk",
      "heavy cream", "heavy whipping cream", "whipping cream",
      "half and half", "light cream",
      "sour cream", "creme fraiche",
      "cream cheese", "neufchatel", "mascarpone", "ricotta",
      "cottage cheese", "farmers cheese",
      "fresh mozzarella", "burrata",
      "cheddar cheese", "cheddar block", "shredded cheddar",
      "parmesan", "parmigiano", "romano cheese", "asiago",
      "gruyere", "emmental", "swiss cheese",
      "gouda", "edam", "havarti", "fontina", "provolone",
      "brie", "camembert", "gorgonzola", "roquefort", "stilton",
      "blue cheese", "feta cheese", "queso fresco", "queso blanco",
      "monterey jack", "colby", "pepper jack",
      "butter stick", "unsalted butter", "salted butter", "european butter",
      "ghee jar", "clarified butter",
      "greek yogurt", "plain yogurt", "whole milk yogurt", "nonfat yogurt",
      "skyr", "kefir", "whipped cream can",
      }, ["DAIRY"]),
    # GRAIN
    ({"all purpose flour", "bread flour", "whole wheat flour",
      "cake flour", "pastry flour", "self rising flour",
      "almond flour", "coconut flour", "oat flour", "rye flour",
      "spelt flour", "cassava flour", "chickpea flour", "rice flour",
      "white rice", "brown rice", "jasmine rice", "basmati rice",
      "arborio rice", "wild rice", "instant rice",
      "spaghetti", "penne", "rigatoni", "fusilli", "rotini",
      "farfalle", "linguine", "fettuccine", "tagliatelle",
      "angel hair", "orzo", "macaroni", "lasagna noodle",
      "egg noodle", "ramen noodle", "soba noodle", "udon noodle",
      "rice noodle", "vermicelli noodle", "glass noodle",
      "rolled oat", "quick oat", "steel cut oat", "instant oat",
      "cornmeal", "polenta", "grits", "semolina",
      "breadcrumb", "panko", "plain breadcrumb", "italian breadcrumb",
      "bread loaf", "sandwich bread", "whole wheat bread", "white bread",
      "sourdough bread", "french bread", "baguette", "ciabatta",
      "pita bread", "naan", "flatbread",
      "flour tortilla", "corn tortilla",
      "quinoa", "farro", "bulgur", "couscous", "barley", "millet",
      "amaranth", "teff", "freekeh", "crouton", "stuffing mix",
      }, ["GRAIN"]),
    # BAKING
    ({"baking soda", "baking powder", "cream of tartar",
      "active dry yeast", "instant yeast", "rapid rise yeast",
      "vanilla extract", "almond extract", "peppermint extract",
      "lemon extract", "orange extract",
      "food coloring", "gel food color",
      "cocoa powder", "dutch process cocoa", "unsweetened cocoa",
      "chocolate chip", "mini chocolate chip", "white chocolate chip",
      "dark chocolate chip", "baking chocolate", "unsweetened chocolate",
      "bittersweet chocolate", "semisweet chocolate",
      "sprinkle", "nonpareil", "decorating sugar", "sanding sugar",
      "cake mix", "brownie mix", "cookie mix", "muffin mix",
      "pancake mix", "waffle mix", "biscuit mix",
      "powdered sugar", "confectioners sugar", "icing sugar",
      "granulated sugar", "cane sugar",
      "brown sugar", "dark brown sugar", "light brown sugar",
      "turbinado sugar", "raw sugar", "demerara sugar",
      "corn syrup", "light corn syrup", "dark corn syrup", "molasses",
      }, ["BAKING"]),
    # SPICE
    ({"black pepper", "white pepper", "peppercorn",
      "sea salt", "kosher salt", "table salt", "himalayan salt",
      "fleur de sel", "smoked salt", "celery salt", "garlic salt",
      "garlic powder", "onion powder",
      "cumin", "ground cumin", "cumin seed",
      "paprika", "smoked paprika", "sweet paprika", "hot paprika",
      "chili powder", "ancho chili", "chipotle powder",
      "cayenne", "red pepper flake", "crushed red pepper",
      "cinnamon", "ground cinnamon", "cinnamon stick",
      "nutmeg", "ground nutmeg",
      "oregano", "dried oregano", "thyme", "dried thyme",
      "rosemary", "dried rosemary", "basil", "dried basil",
      "bay leaf", "turmeric", "ground turmeric",
      "coriander", "ground coriander", "fennel seed", "caraway seed",
      "cardamom", "clove", "allspice", "ginger", "ground ginger",
      "mustard seed", "ground mustard", "fenugreek", "nigella seed",
      "sumac", "za'atar", "herbs de provence", "italian seasoning",
      "old bay", "cajun seasoning", "creole seasoning",
      "taco seasoning", "fajita seasoning", "ranch seasoning",
      "curry powder", "garam masala", "ras el hanout",
      "five spice", "everything bagel seasoning",
      "lemon pepper", "steak seasoning", "bbq rub", "dry rub",
      "vanilla bean", "saffron", "annatto", "achiote",
      "dill weed", "dried dill", "marjoram", "dried sage",
      }, ["SPICE"]),
    # OIL_FAT
    ({"olive oil", "extra virgin olive oil",
      "vegetable oil", "canola oil", "sunflower oil", "safflower oil",
      "corn oil", "soybean oil", "peanut oil", "grapeseed oil",
      "avocado oil", "coconut oil", "palm oil",
      "sesame oil", "toasted sesame oil",
      "walnut oil", "flaxseed oil", "truffle oil",
      "cooking spray", "nonstick spray", "baking spray",
      "shortening", "vegetable shortening", "crisco",
      "lard", "rendered lard", "duck fat",
      "beef tallow", "margarine stick", "vegan butter",
      }, ["OIL_FAT"]),
    # CONDIMENT
    ({"soy sauce", "tamari", "liquid aminos", "coconut aminos",
      "fish sauce", "oyster sauce", "hoisin sauce",
      "worcestershire sauce",
      "hot sauce", "sriracha", "tabasco", "cholula",
      "chili garlic sauce", "sambal oelek", "gochujang",
      "apple cider vinegar", "white vinegar", "distilled vinegar",
      "red wine vinegar", "white wine vinegar", "balsamic vinegar",
      "sherry vinegar", "rice vinegar", "malt vinegar",
      "dijon mustard", "whole grain mustard", "yellow mustard",
      "ketchup", "mayonnaise", "light mayonnaise",
      "relish", "sweet relish", "dill relish",
      "bbq sauce", "barbecue sauce", "steak sauce",
      "buffalo sauce", "wing sauce",
      "teriyaki sauce", "ponzu sauce", "sweet chili sauce",
      "pad thai sauce", "stir fry sauce",
      "tahini", "miso paste", "red miso", "white miso",
      "tomato paste", "marinara sauce", "pasta sauce",
      "alfredo sauce", "pesto sauce",
      "enchilada sauce", "salsa verde", "mole sauce",
      "salsa jar", "chunky salsa",
      "pickle", "dill pickle", "bread and butter pickle",
      "pickled jalapeno", "giardiniera",
      "capers", "anchovy paste", "anchovy fillet",
      "sun dried tomato", "roasted red pepper",
      "horseradish prepared", "wasabi paste",
      }, ["CONDIMENT"]),
    # CANNED_GOOD
    ({"canned tomato", "diced tomato", "crushed tomato", "stewed tomato",
      "whole peeled tomato", "san marzano", "fire roasted tomato",
      "canned bean", "canned black bean", "canned chickpea",
      "canned kidney bean", "canned pinto bean", "canned navy bean",
      "canned lentil", "canned white bean", "canned cannellini",
      "canned corn", "canned pumpkin", "canned yam",
      "canned artichoke", "canned beet", "canned mushroom",
      "canned water chestnut", "canned bamboo",
      "canned green bean", "canned pea", "canned spinach",
      "coconut milk can", "coconut cream can", "lite coconut milk",
      "chicken broth", "beef broth", "vegetable broth",
      "chicken stock", "beef stock", "bone broth",
      "canned tuna", "canned salmon", "canned sardine",
      "canned anchovy", "canned crab", "canned clam",
      "rotel", "green chili can", "chipotle in adobo",
      }, ["CANNED_GOOD"]),
    # SWEETENER
    ({"honey", "raw honey", "manuka honey", "clover honey",
      "maple syrup", "pure maple syrup",
      "agave", "agave nectar", "date syrup", "date sugar",
      "stevia", "monk fruit sweetener", "erythritol",
      "brown rice syrup",
      }, ["SWEETENER"]),
    # NUT_SEED
    ({"almonds", "raw almonds", "roasted almonds", "sliced almonds",
      "slivered almonds", "almond meal",
      "walnuts", "walnut halves", "pecans", "cashews",
      "pistachios", "pine nuts", "hazelnuts", "macadamia nut",
      "brazil nut", "peanut", "raw peanut", "roasted peanut",
      "peanut butter", "almond butter", "cashew butter",
      "sunflower seed", "pumpkin seed", "pepita",
      "sesame seed", "chia seed", "flaxseed", "ground flax",
      "hemp seed", "poppy seed",
      }, ["NUT_SEED"]),
    # THICKENER
    ({"cornstarch", "corn starch", "arrowroot", "arrowroot powder",
      "tapioca starch", "tapioca pearl", "potato starch",
      "unflavored gelatin", "agar agar", "agar powder",
      "xanthan gum", "guar gum", "pectin",
      }, ["THICKENER"]),
    # ALCOHOL (cooking)
    ({"cooking wine", "dry sherry", "mirin", "sake cooking",
      "rice wine", "shaoxing wine",
      }, ["ALCOHOL"]),
    # OTHER_INGR (catch-all pantry)
    ({"nutritional yeast", "dried mushroom", "porcini dried",
      "seaweed", "nori sheet", "kombu", "wakame",
      "dashi", "bonito flake", "matcha powder",
      "rose water", "orange blossom water", "liquid smoke",
      "raisin", "currant", "sultana",
      "dried cranberry", "dried cherry", "dried apricot", "dried fig",
      "dried date", "dried mango", "dried blueberry", "dried tomato",
      "canned fruit", "canned peach", "canned pear", "canned pineapple",
      "maraschino cherry",
      "lemon juice bottle", "lime juice bottle",
      "jam", "jelly", "preserves", "fruit spread", "marmalade",
      "chutney",
      "caramel sauce", "caramel topping",
      "sweetened condensed milk",
      "cream of mushroom soup", "cream of chicken soup",
      "french onion soup can",
      "harissa", "curry paste", "red curry paste", "green curry paste",
      "yellow curry paste", "massaman paste",
      "coconut butter", "cacao nib", "carob powder",
      "vital wheat gluten", "citric acid",
      "meat tenderizer",
      "vinegar",
      }, ["OTHER_INGR"]),
]

# ══════════════════════════════════════════════════════════════════════════════
#  PASS 2 — FOOD-CATEGORY DEFAULT
#  If a product's category looks like a food/grocery category (and wasn't
#  caught by explicit non-ingredient rules), assume it IS an ingredient.
#  This eliminates most of the LLM queue.
# ══════════════════════════════════════════════════════════════════════════════

FOOD_CATEGORY_KEYWORDS = {
    "food", "grocery", "groceries", "pantry", "cooking", "baking",
    "ingredient", "produce", "meat", "seafood", "poultry", "dairy",
    "deli", "bakery", "spice", "herb", "condiment", "sauce", "oil",
    "flour", "grain", "pasta", "rice", "canned", "jarred", "dry good",
    "bulk", "organic", "natural food", "gourmet", "specialty food",
    "international food", "ethnic food", "asian food", "mexican food",
    "italian food", "middle eastern", "latin food",
    "frozen food", "refrigerated", "chilled",
    "nut", "seed", "nut butter", "sweetener", "sugar", "honey",
    "vinegar", "dressing", "marinade", "seasoning", "rub", "blend",
    "broth", "stock", "soup base",
    "cheese", "butter", "egg", "milk", "cream", "yogurt",
    "bread", "tortilla", "wrap",
    "breakfast", "cereal grain",   # NOTE: cereal grain ≠ "cereal" (covered by non-ingredient)
}


def normalise(text: str) -> str:
    return text.lower().strip()


def is_food_category(category: str) -> bool:
    """Return True if the category string looks like a food/grocery category."""
    cat = normalise(category)
    for kw in FOOD_CATEGORY_KEYWORDS:
        if kw in cat:
            return True
    return False


def rule_classify(row: dict) -> dict | None:
    name     = normalise(row.get("name", ""))
    category = normalise(row.get("category_name", ""))
    combined = name + " " + category

    # Pass 1a: explicit non-ingredient keywords
    for kw in NON_INGREDIENT_KEYWORDS:
        if kw in combined:
            return {"ingredient": False, "classifiers": []}
    for cat_kw in NON_INGREDIENT_CATEGORIES:
        if cat_kw in category:
            return {"ingredient": False, "classifiers": []}

    # Pass 1b: explicit ingredient keywords
    for keywords, tags in INGREDIENT_RULES:
        for kw in keywords:
            if kw in combined:
                return {"ingredient": True, "classifiers": tags}

    # Pass 2: food-category default
    if is_food_category(category):
        return {"ingredient": True, "classifiers": ["OTHER_INGR"]}

    return None  # truly ambiguous → LLM


# ── Ollama helpers ─────────────────────────────────────────────────────────────

def check_ollama_running():
    try:
        req = urllib.request.urlopen(f"{OLLAMA_BASE_URL}/api/tags", timeout=5)
        data = json.loads(req.read())
        return [m["name"].split(":")[0] for m in data.get("models", [])]
    except (urllib.error.URLError, OSError):
        return None


SYSTEM_PROMPT = """You are a food product classifier. For each product determine:
1. Is it an INGREDIENT a home cook would use in a recipe?
2. If yes, assign 1-3 tags: PROTEIN, DAIRY, PRODUCE, GRAIN, BAKING, SPICE, OIL_FAT,
   CONDIMENT, CANNED_GOOD, SWEETENER, NUT_SEED, ALCOHOL, THICKENER, FRESH_HERB, OTHER_INGR

Respond ONLY with a JSON array — one object per product in the same order.
Each: {"ingredient": true/false, "classifiers": ["TAG"]}
No explanation. No markdown. Only the JSON array."""


def ollama_chat(model: str, system: str, user: str) -> str:
    payload = json.dumps({
        "model": model, "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",   "content": user},
        ],
        "options": {"temperature": 0.0},
    }).encode()
    req = urllib.request.Request(
        f"{OLLAMA_BASE_URL}/api/chat", data=payload,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read())["message"]["content"].strip()


def parse_json_array(text: str, expected: int) -> list[dict]:
    text = text.strip()
    if "```" in text:
        for part in text.split("```")[1:]:
            part = part.lstrip("json").strip()
            if part:
                text = part
                break
    start, end = text.find("["), text.rfind("]") + 1
    if start != -1 and end > start:
        try:
            r = json.loads(text[start:end])
            if isinstance(r, list) and len(r) == expected:
                return r
        except json.JSONDecodeError:
            pass
    return [{"ingredient": False, "classifiers": []} for _ in range(expected)]


def build_prompt(row: dict) -> str:
    parts = [f"Name: {row.get('name','').strip()}"]
    if cat := row.get("category_name","").strip():
        parts.append(f"Category: {cat}")
    if sd := row.get("shortDescription","").strip()[:200]:
        parts.append(f"Desc: {sd}")
    return " | ".join(parts)


def classify_batch_llm(model: str, batch: list[dict], retries: int = 2) -> list[dict]:
    numbered = "\n".join(f"{i+1}. {build_prompt(r)}" for i, r in enumerate(batch))
    user_msg = (
        f"Classify these {len(batch)} food products. "
        f"Return a JSON array with exactly {len(batch)} objects.\n\n" + numbered
    )
    for attempt in range(retries + 1):
        try:
            raw = ollama_chat(model, SYSTEM_PROMPT, user_msg)
            return parse_json_array(raw, len(batch))
        except Exception:
            if attempt == retries:
                return [{"ingredient": False, "classifiers": []} for _ in batch]
            time.sleep(1)


# ── CSV I/O ───────────────────────────────────────────────────────────────────

def read_csvs(folder: str) -> list[dict]:
    csv.field_size_limit(10_000_000)
    rows = []
    for csv_file in Path(folder).glob("*.csv"):
        print(f"  Reading {csv_file.name} …")
        with open(csv_file, newline="", encoding="utf-8-sig") as f:
            for row in csv.DictReader(f):
                rows.append(row)
    print(f"  Total rows: {len(rows):,}")
    return rows


def write_output(classified: list[dict], output_path: str):
    fieldnames = ["name", "ingredient", "classifiers", "retail_price",
                  "thumbnailImage", "mediumImage", "largeImage", "color"]
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(classified)
    n_ingr = sum(1 for r in classified if r["ingredient"])
    print(f"\nSaved → {output_path}")
    print(f"   {n_ingr:,} ingredients / {len(classified):,} total products")


def to_output_row(row: dict, result: dict) -> dict:
    return {
        "name":           row.get("name", ""),
        "ingredient":     result.get("ingredient", False),
        "classifiers":    "|".join(result.get("classifiers", [])),
        "retail_price":   row.get("retail_price", ""),
        "thumbnailImage": row.get("thumbnailImage", ""),
        "mediumImage":    row.get("mediumImage", ""),
        "largeImage":     row.get("largeImage", ""),
        "color":          row.get("color", ""),
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Hybrid rule+LLM ingredient classifier — M4 optimised."
    )
    parser.add_argument("input_folder")
    parser.add_argument("-o", "--output",  default="classified_ingredients.csv")
    parser.add_argument("-m", "--model",   default=DEFAULT_MODEL,
                        help=f"Ollama model (default: {DEFAULT_MODEL})")
    parser.add_argument("-w", "--workers", type=int, default=DEFAULT_WORKERS,
                        help=f"Parallel workers (default: {DEFAULT_WORKERS})")
    parser.add_argument("-b", "--batch",   type=int, default=DEFAULT_BATCH,
                        help=f"Products per LLM call (default: {DEFAULT_BATCH})")
    parser.add_argument("--no-llm", action="store_true",
                        help="Skip LLM pass — output rules + category-default only (fast)")
    args = parser.parse_args()

    print(f"\n📂 Reading CSVs from: {args.input_folder}")
    rows = read_csvs(args.input_folder)
    if not rows:
        print("⚠  No rows found.")
        return

    # ── Pass 1 + 2: Rule-based + category default (instant) ──────────────────
    print("\nPass 1+2: Rule-based + food-category default ...")
    t0 = time.time()

    results   = [None] * len(rows)
    llm_queue = []

    for i, row in enumerate(rows):
        r = rule_classify(row)
        if r is not None:
            results[i] = r
        else:
            llm_queue.append((i, row))

    rule_count = len(rows) - len(llm_queue)
    rule_pct   = 100 * rule_count / len(rows)
    print(f"   Rule-classified: {rule_count:,}  ({rule_pct:.1f}%)")
    print(f"   Needs LLM:       {len(llm_queue):,}  ({100-rule_pct:.1f}%)")
    print(f"   Time: {time.time()-t0:.1f}s")

    if args.no_llm:
        print(f"\n--no-llm: outputting rule-classified rows only.")
        print(f"   Skipping {len(llm_queue):,} unclassified products entirely.")
        classified = [to_output_row(row, results[i]) for i, row in enumerate(rows) if results[i] is not None]
        write_output(classified, args.output)
        print(f"   Total wall time: {(time.time()-t0)/60:.1f} min")
        return

    # ── Pass 3: LLM for true unknowns ─────────────────────────────────────────
    if llm_queue:
        print(f"\nPass 3: LLM classification for {len(llm_queue):,} products …")
        print(f"   Model: {args.model}  |  Workers: {args.workers}  |  Batch: {args.batch}")
        print(f"   💡 Tip: make sure you ran  ollama pull {args.model}\n")

        available = check_ollama_running()
        if available is None:
            print("⚠  Ollama not reachable — marking unknowns as non-ingredient.")
            for orig_idx, _ in llm_queue:
                results[orig_idx] = {"ingredient": False, "classifiers": []}
        elif args.model.split(":")[0] not in available:
            print(f"WARN Model '{args.model}' not found. Run: ollama pull {args.model}")
            for orig_idx, _ in llm_queue:
                results[orig_idx] = {"ingredient": False, "classifiers": []}
        else:
            only_rows  = [r for _, r in llm_queue]
            batches    = [
                (llm_queue[i : i + args.batch], only_rows[i : i + args.batch])
                for i in range(0, len(llm_queue), args.batch)
            ]
            total_b   = len(batches)
            completed = 0
            lock      = Lock()
            t1        = time.time()

            def process(b_idx, idx_row_pairs, row_batch):
                return b_idx, idx_row_pairs, classify_batch_llm(args.model, row_batch)

            with ThreadPoolExecutor(max_workers=args.workers) as pool:
                futures = {
                    pool.submit(process, bi, idxs, rws): bi
                    for bi, (idxs, rws) in enumerate(batches)
                }
                for future in as_completed(futures):
                    b_idx, idx_row_pairs, llm_results = future.result()
                    for (orig_idx, _), res in zip(idx_row_pairs, llm_results):
                        results[orig_idx] = res
                    with lock:
                        completed += 1
                        elapsed    = time.time() - t1
                        rate       = completed / elapsed
                        eta        = (total_b - completed) / rate if rate > 0 else 0
                        print(
                            f"  LLM batch {completed:>5}/{total_b}  "
                            f"ETA: {eta/60:>5.1f} min",
                            end="\r",
                        )
            print()

    classified = [to_output_row(row, results[i]) for i, row in enumerate(rows)]
    write_output(classified, args.output)
    print(f"   Total wall time: {(time.time()-t0)/60:.1f} min")


if __name__ == "__main__":
    main()