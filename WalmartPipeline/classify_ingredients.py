#!/usr/bin/env python3
"""
classify_ingredients.py

Reads all the CSVs from walmart_CSVs/ and figures out which products are
cooking ingredients. Uses three passes:
  1. Keyword rules  - catches ~65% of products instantly
  2. Category check - another ~25%, no LLM needed
  3. Ollama LLM     - handles the remaining ~10% that are genuinely ambiguous

Run with --no-llm to skip the LLM entirely (that's the default from runner.js).
If you do want LLM mode, make sure ollama is running first:
  ollama pull llama3.2:1b
  python classify_ingredients.py /path/to/csvs -m llama3.2:1b -w 8

The 15 category tags (PRODUCE, PROTEIN, DAIRY, etc.) are shared with
kroger_catalogue.js - any changes here should be reflected there too.
"""

import csv
import json
import re
import time
import argparse
import urllib.request
import urllib.error
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

# --- Configuration ---
DEFAULT_MODEL   = "llama3.2:1b"
DEFAULT_WORKERS = 8
DEFAULT_BATCH   = 25
OLLAMA_BASE_URL = "http://localhost:11434"

# --- keyword rules ---
# These two sets handle most of the work without touching the LLM.
# Non-ingredient check runs first so things like "frozen dinner" don't
# accidentally match "frozen vegetable" in the ingredient rules below.

NON_INGREDIENT_KEYWORDS = {
    # Prepared / frozen meals
    "frozen meal", "frozen dinner", "frozen entree", "frozen pizza",
    "tv dinner", "microwave meal", "microwave popcorn", "heat and serve",
    "ready to eat", "ready-to-eat", "meal kit", "dinner kit", "lunch kit",
    "skillet meal", "hamburger helper", "tuna helper",
    "mac and cheese dinner", "boxed dinner", "gumbo mix", "protein bowl",
    # Cocktail / bar mixers
    "cocktail syrup", "margarita mix", "craft mixer", "cocktail mixer",
    # Gift sets / care packages (multi-product bundles, not ingredients)
    "gift set", "gift basket", "gift box", "gift tower", "care package", "snack care package",
    # Drink mixes / powdered beverages
    "drink mix", "powdered drink", "kool-aid", "crystal light",
    # Pancake / table syrup (condiment, not a cooking ingredient)
    "pancake syrup", "table syrup", "maple flavored syrup",
    # Instant noodles / ramen cups (complete meals)
    "instant noodle", "ramen noodle soup", "cup noodle", "cup of noodle",
    # Cake / cupcake toppers (decorative plastic/acrylic, not food)
    "cake topper", "cake toppers", "cupcake topper", "cupcake toppers",
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
    "soda", "cola", "ginger ale", "root beer", "cream soda",
    "energy drink", "sports drink", "electrolyte drink",
    "fruit juice", "orange juice", "apple juice", "grape juice",
    "cranberry juice", "pineapple juice", "tomato juice",
    "lemonade", "limeade", "fruit punch",
    "iced tea", "sweet tea", "diet tea", "bottled tea", "lemon tea", "leaf tea", "tea bag",
    "yerba mate", "kombucha",
    "coffee drink", "bottled coffee", "cold brew bottle", "frappuccino",
    "smoothie bottle", "juice smoothie", "drinkable yogurt", "dairy drink", "yogurt drink",
    "protein shake", "meal replacement shake",
    "sparkling water", "mineral water", "bottled water", "distilled water",
    "flavored water", "vitamin water", "coconut water bottle",
    "beer", "wine bottle", "spirits bottle", "whiskey bottle",
    "vodka bottle", "rum bottle", "gin bottle", "tequila bottle",
    "hard seltzer", "hard cider",
    "cold brew concentrate",
    # Coffee pods / capsules / flavored coffees (not cooking ingredients)
    "k-cup", "k cup", "coffee pod", "coffee capsule", "coffee single serve", "flavored coffee",
    # General capsules (supplement capsules, espresso machine capsules, etc.)
    "capsule", "softgel", "caplet",
    # Candles (birthday candles, numeral candles, decorative - not food)
    "candle",
    # Clothing / merchandise
    "hoodie", "sweatshirt", "t-shirt", "tote bag", "pullover shirt",
    # Prepared soups (ready-to-eat, not cooking-ingredient condensed soups)
    "chunky soup", "slow simmered soup", "chef boyardee", "chunky chili",
    # Breakfast sandwiches and similar prepared foods (both forms since plural is irregular)
    "breakfast sandwich", "breakfast sandwiches", "breakfast burrito", "biscuit sandwich",
    # Snack jerky (not a cooking ingredient)
    "jerky",
    # Trail mix (snack, not an ingredient)
    "trail mix",
    # Pretzel snacks (pieces, bites, etc. — not a raw ingredient)
    "pretzel",
    # Flavored drink syrups (Torani, Monin etc. — for coffee drinks, not cooking)
    "drink syrup", "coffee syrup", "flavored syrup",
    # Snack packs / mini cookie packs
    "snack pack",
    # Pop-tarts and similar pastry snacks
    "pop tarts", "pop-tart",
    # Tea formats that slip past "tea bag" (pyramid sachets, loose leaf tins)
    "pyramid sachet", "loose tea", "pyramid tea",
    # Cake decoration companies / party supply decorations
    "decopac", "wedding topper", "party topper",
    # Non-food merchandise / signs
    "banner", "yard sign", "signage",
    # Candy / confections
    "candy", "confection", "marshmallow", "breath mint", "chewing gum", "gum", "bubble gum",
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
    # Supplements / vitamins (single-letter vitamin keywords removed - too broad, catch fortified foods)
    "multivitamin", "supplement", "probiotic", "prebiotic",
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

# Checked BEFORE INGREDIENT_RULES to fix tag conflicts caused by rule ordering.
# E.g. "blueberry yogurt" hits PRODUCE before DAIRY without this, "coffee with cardamom"
# hits SPICE, packaged "pie filling" hits PRODUCE.
PRIORITY_INGREDIENT_CHECKS: list[tuple[set[str], list[str]]] = [
    ({"yogurt", "kefir"}, ["DAIRY"]),
    ({"pie filling"}, ["OTHER_INGR"]),
    ({
        "ground coffee", "coffee bean", "coffee grounds", "roasted coffee",
        "instant coffee", "espresso powder", "espresso bean", "coffee powder",
    }, ["OTHER_INGR"]),
    # Nuts/seeds with flavor modifiers (e.g. "sea salt") hit SPICE before NUT_SEED
    ({
        "cashews", "almonds", "peanuts", "walnuts", "pecans", "pistachios",
        "hazelnuts", "macadamia", "sunflower seeds", "pumpkin seeds", "pepitas",
    }, ["NUT_SEED"]),
    # Ham products hit PRODUCE when "apple" appears in "applewood smoked ham"
    ({"smoked ham", "spiral ham", "whole ham", "applewood smoked"}, ["PROTEIN"]),
]

# Ingredient rules - format is (keyword set, [tags to assign]).
# Synced with the search terms in kroger_catalogue.js FOOD_CATEGORIES.
# Kroger terms come first (marked "canonical"), then Walmart-specific variants.
# Keywords are matched against lowercased product name + category_name.

INGREDIENT_RULES: list[tuple[set[str], list[str]]] = [

    # --- PRODUCE ---
    ({
        # Kroger search terms (canonical)
        "fresh vegetable", "fresh fruit", "organic vegetable", "organic fruit",
        "broccoli", "cauliflower", "spinach", "kale", "romaine", "mixed greens",
        "brussels sprout", "cabbage", "carrot", "celery", "cucumber", "zucchini",
        "bell pepper", "jalapeño", "cherry tomato", "roma tomato",
        "red onion", "yellow onion", "shallot", "scallion", "leek",
        "garlic bulb", "portobello", "shiitake", "cremini mushroom",
        "asparagus", "artichoke", "beet", "turnip", "parsnip",
        "sweet potato", "russet potato", "red potato", "yukon gold",
        "corn on cob", "green bean", "snap pea", "snow pea", "eggplant",
        "fennel", "radish", "apple", "pear", "orange", "lemon", "lime",
        "banana", "mango", "pineapple", "papaya", "kiwi",
        "strawberry", "blueberry", "raspberry", "blackberry",
        "watermelon", "cantaloupe", "peach", "nectarine", "plum", "cherry",
        "avocado", "pomegranate",
        # Walmart-specific variants
        "frozen vegetable", "frozen fruit",
        "arugula", "iceberg lettuce", "butter lettuce", "collard greens",
        "bok choy", "napa cabbage",
        "serrano pepper", "habanero", "poblano", "anaheim pepper", "banana pepper",
        "grape tomato",
        "white onion", "green onion",
        "garlic clove", "garlic head",
        "cremini", "button mushroom", "oyster mushroom", "enoki", "chanterelle",
        "fennel bulb", "jicama", "okra",
        "yam", "fingerling potato", "fresh corn", "corn on the cob",
        "sugar snap", "eggplant",
        "grapefruit", "honeydew", "apricot", "fresh fig", "passion fruit",
    }, ["PRODUCE"]),

    # --- FRESH_HERB ---
    ({
        # Kroger search terms (canonical)
        "fresh basil", "fresh parsley", "fresh cilantro", "fresh thyme",
        "fresh rosemary", "fresh mint", "fresh dill", "fresh chives",
        "fresh tarragon", "fresh oregano", "fresh sage",
        "fresh lemongrass", "fresh ginger root",
        # Walmart-specific variants
        "fresh turmeric root", "herb bunch", "herb packet",
    }, ["FRESH_HERB"]),

    # --- PROTEIN ---
    ({
        # Kroger search terms (canonical)
        "chicken breast", "chicken thigh", "chicken wing", "chicken drumstick",
        "ground chicken", "whole chicken", "ground turkey", "turkey breast",
        "ground beef", "beef chuck", "beef brisket", "ribeye", "sirloin",
        "flank steak", "skirt steak", "beef roast", "beef short rib",
        "pork chop", "pork loin", "pork belly", "pork shoulder",
        "pork tenderloin", "baby back rib", "spiral ham", "ham steak",
        "lamb chop", "lamb leg", "ground lamb",
        "salmon fillet", "tuna fillet", "tilapia", "cod fillet", "halibut",
        "mahi mahi", "sea bass", "trout", "catfish",
        "shrimp", "scallop", "lobster tail", "crab leg", "crab meat",
        "clam", "mussel", "oyster",
        "bacon", "pancetta", "prosciutto", "salami", "pepperoni",
        "chorizo", "andouille", "bratwurst", "italian sausage",
        "breakfast sausage",
        "deli turkey", "deli ham", "deli roast beef", "deli chicken",
        "lunch meat",
        "extra firm tofu", "silken tofu", "tempeh", "seitan", "edamame",
        "black bean", "pinto bean", "kidney bean", "chickpea", "lentil",
        "split pea", "navy bean", "cannellini bean",
        "large eggs", "cage free egg", "organic egg", "egg whites",
        # Walmart-specific variants
        "chicken tender", "chicken leg", "whole turkey",
        "beef rib", "tenderloin", "beef stew meat",
        "pork rib", "spare rib", "uncured ham",
        "rack of lamb",
        "salmon steak", "whole salmon", "tuna steak",
        "snapper", "squid", "octopus",
        "sausage link", "sausage patty", "deli meat", "sliced meat",
        "tofu", "firm tofu", "textured vegetable protein",
        "great northern bean", "fava bean",
        "dozen eggs", "medium eggs", "free range egg", "liquid egg",
    }, ["PROTEIN"]),

    # --- DAIRY ---
    ({
        # Kroger search terms (canonical)
        "whole milk", "skim milk", "2% milk", "lactose free milk", "organic milk",
        "buttermilk", "evaporated milk", "condensed milk", "powdered milk",
        "heavy cream", "heavy whipping cream", "half and half", "light cream",
        "sour cream", "creme fraiche",
        "cream cheese", "mascarpone", "ricotta", "cottage cheese",
        "fresh mozzarella", "burrata",
        "cheddar cheese", "parmesan", "romano cheese", "asiago",
        "gruyere", "swiss cheese", "gouda", "havarti", "fontina", "provolone",
        "brie", "camembert", "gorgonzola", "blue cheese",
        "feta cheese", "queso fresco", "monterey jack", "pepper jack",
        "unsalted butter", "salted butter", "european butter", "ghee",
        "greek yogurt", "plain yogurt", "whole milk yogurt", "skyr", "kefir",
        # Walmart-specific variants
        "1% milk", "nonfat milk", "reduced fat milk",
        "whipping cream", "dry milk",
        "neufchatel", "farmers cheese",
        "cheddar block", "shredded cheddar",
        "parmigiano", "emmental", "edam",
        "roquefort", "stilton", "queso blanco", "colby",
        "butter stick", "ghee jar", "clarified butter",
        "nonfat yogurt", "whipped cream can",
    }, ["DAIRY"]),

    # --- GRAIN ---
    ({
        # Kroger search terms (canonical)
        "all purpose flour", "bread flour", "whole wheat flour",
        "cake flour", "almond flour", "coconut flour", "oat flour", "rye flour",
        "chickpea flour", "rice flour", "cassava flour",
        "white rice", "brown rice", "jasmine rice", "basmati rice",
        "arborio rice", "wild rice",
        "spaghetti", "penne", "rigatoni", "fusilli", "farfalle",
        "linguine", "fettuccine", "angel hair", "orzo", "macaroni",
        "lasagna noodle", "egg noodle", "ramen noodle", "soba noodle",
        "udon noodle", "rice noodle",
        "rolled oats", "quick oats", "steel cut oats",
        "cornmeal", "polenta", "grits", "semolina",
        "panko", "plain breadcrumb",
        "sandwich bread", "whole wheat bread", "sourdough bread",
        "french bread", "pita bread", "naan", "flatbread",
        "flour tortilla", "corn tortilla",
        "quinoa", "farro", "bulgur", "couscous", "barley", "millet",
        # Walmart-specific variants
        "pastry flour", "self rising flour", "spelt flour", "oat flour",
        "instant rice",
        "rotini", "tagliatelle", "vermicelli noodle", "glass noodle",
        "rolled oat", "quick oat", "steel cut oat", "instant oat",
        "breadcrumb", "italian breadcrumb",
        "bread loaf", "white bread", "baguette", "ciabatta",
        "amaranth", "teff", "freekeh", "crouton", "stuffing mix",
    }, ["GRAIN"]),

    # --- BAKING ---
    ({
        # Kroger search terms (canonical)
        "baking soda", "baking powder", "cream of tartar",
        "active dry yeast", "instant yeast",
        "vanilla extract", "almond extract", "peppermint extract",
        "cocoa powder", "dutch process cocoa",
        "chocolate chips", "white chocolate chips", "baking chocolate",
        "powdered sugar", "granulated sugar", "cane sugar",
        "brown sugar", "turbinado sugar", "demerara sugar",
        "corn syrup", "molasses",
        "cake mix", "brownie mix", "pancake mix", "waffle mix", "muffin mix",
        # Walmart-specific variants
        "rapid rise yeast",
        "lemon extract", "orange extract",
        "food coloring", "gel food color",
        "unsweetened cocoa",
        "chocolate chip", "mini chocolate chip", "dark chocolate chip",
        "white chocolate chip", "unsweetened chocolate",
        "bittersweet chocolate", "semisweet chocolate",
        "sprinkle", "nonpareil", "decorating sugar", "sanding sugar",
        "cookie mix", "biscuit mix",
        "confectioners sugar", "icing sugar",
        "dark brown sugar", "light brown sugar",
        "raw sugar", "light corn syrup", "dark corn syrup",
    }, ["BAKING"]),

    # --- SPICE ---
    ({
        # Kroger search terms (canonical)
        "black pepper", "white pepper", "peppercorn",
        "sea salt", "kosher salt", "himalayan salt", "garlic salt",
        "garlic powder", "onion powder",
        "cumin", "paprika", "smoked paprika", "chili powder",
        "cayenne", "red pepper flake",
        "cinnamon", "nutmeg", "oregano", "thyme", "rosemary",
        "basil dried", "bay leaf", "turmeric", "coriander",
        "fennel seed", "cardamom", "clove", "allspice",
        "ground ginger", "mustard seed", "ground mustard", "fenugreek",
        "sumac", "za'atar", "herbs de provence", "italian seasoning",
        "cajun seasoning", "taco seasoning",
        "curry powder", "garam masala", "ras el hanout", "five spice",
        "lemon pepper", "steak seasoning", "bbq rub",
        "vanilla bean", "saffron", "dill weed", "marjoram",
        # Walmart-specific variants
        "table salt", "fleur de sel", "smoked salt", "celery salt",
        "ground cumin", "cumin seed",
        "sweet paprika", "hot paprika", "ancho chili", "chipotle powder",
        "crushed red pepper",
        "ground cinnamon", "cinnamon stick", "ground nutmeg",
        "dried oregano", "dried thyme", "dried rosemary", "dried basil",
        "ground turmeric", "ground coriander", "caraway seed",
        "nigella seed",
        "old bay", "creole seasoning", "fajita seasoning", "ranch seasoning",
        "everything bagel seasoning",
        "dry rub", "annatto", "achiote",
        "dried dill", "dried sage",
    }, ["SPICE"]),

    # --- OIL_FAT ---
    ({
        # Kroger search terms (canonical)
        "olive oil", "extra virgin olive oil",
        "vegetable oil", "canola oil", "sunflower oil", "safflower oil",
        "corn oil", "soybean oil", "peanut oil", "grapeseed oil",
        "avocado oil", "coconut oil", "sesame oil", "toasted sesame oil",
        "walnut oil", "flaxseed oil", "truffle oil",
        "cooking spray", "nonstick spray",
        "shortening", "lard", "duck fat", "beef tallow",
        "vegan butter",
        # Walmart-specific variants
        "palm oil",
        "baking spray",
        "vegetable shortening", "crisco",
        "rendered lard",
        "margarine stick",
    }, ["OIL_FAT"]),

    # --- CONDIMENT ---
    ({
        # Kroger search terms (canonical)
        "soy sauce", "tamari", "liquid aminos", "coconut aminos",
        "fish sauce", "oyster sauce", "hoisin sauce", "worcestershire sauce",
        "hot sauce", "sriracha", "tabasco", "cholula", "sambal oelek", "gochujang",
        "apple cider vinegar", "white vinegar", "red wine vinegar",
        "white wine vinegar", "balsamic vinegar", "rice vinegar", "malt vinegar",
        "dijon mustard", "whole grain mustard", "yellow mustard",
        "ketchup", "mayonnaise", "relish",
        "bbq sauce", "barbecue sauce", "steak sauce", "buffalo sauce",
        "teriyaki sauce", "ponzu sauce", "sweet chili sauce", "stir fry sauce",
        "tahini", "miso paste",
        "tomato paste", "marinara sauce", "pasta sauce", "alfredo sauce", "pesto",
        "enchilada sauce", "salsa verde", "salsa jar",
        "pickle", "dill pickle", "pickled jalapeno", "giardiniera",
        "capers", "sun dried tomato", "roasted red pepper",
        "horseradish", "wasabi paste",
        # Walmart-specific variants
        "chili garlic sauce",
        "distilled vinegar", "sherry vinegar",
        "light mayonnaise", "sweet relish", "dill relish",
        "wing sauce", "pad thai sauce",
        "red miso", "white miso",
        "pesto sauce", "mole sauce", "chunky salsa",
        "bread and butter pickle",
        "anchovy paste", "anchovy fillet",
        "horseradish prepared",
    }, ["CONDIMENT"]),

    # --- CANNED_GOOD ---
    ({
        # Kroger search terms (canonical)
        "canned tomato", "diced tomato", "crushed tomato", "whole peeled tomato",
        "san marzano", "fire roasted tomato",
        "canned black bean", "canned chickpea", "canned kidney bean",
        "canned pinto bean", "canned navy bean", "canned cannellini",
        "canned corn", "canned pumpkin", "canned artichoke", "canned mushroom",
        "canned water chestnut", "canned green bean",
        "coconut milk can", "coconut cream",
        "chicken broth", "beef broth", "vegetable broth",
        "chicken stock", "beef stock", "bone broth",
        "canned tuna", "canned salmon", "canned sardine", "canned anchovy",
        "canned crab", "canned clam",
        "chipotle in adobo", "green chili can",
        # Walmart-specific variants
        "stewed tomato",
        "canned bean", "canned lentil", "canned white bean",
        "canned yam", "canned beet", "canned bamboo",
        "canned pea", "canned spinach",
        "coconut cream can", "lite coconut milk",
        "rotel",
    }, ["CANNED_GOOD"]),

    # --- NUT_SEED --- (before SWEETENER so "honey roasted cashews" tags as NUT_SEED not SWEETENER)
    ({
        # Kroger search terms (canonical)
        "raw almonds", "sliced almonds", "slivered almonds",
        "walnut halves", "pecans", "cashews", "pistachios",
        "pine nuts", "hazelnuts", "macadamia nut", "brazil nut",
        "peanut butter", "almond butter", "cashew butter",
        "sunflower seed", "pumpkin seed", "pepita",
        "sesame seed", "chia seed", "flaxseed", "hemp seed", "poppy seed",
        # Walmart-specific variants
        "almonds", "roasted almonds", "almond meal",
        "walnuts", "peanut", "raw peanut", "roasted peanut",
        "ground flax",
    }, ["NUT_SEED"]),

    # --- SWEETENER ---
    ({
        # Kroger search terms (canonical)
        "honey", "raw honey", "manuka honey",
        "maple syrup", "pure maple syrup",
        "agave nectar", "date syrup",
        "stevia", "monk fruit sweetener", "erythritol",
        # Walmart-specific variants
        "clover honey",
        "agave",
        "date sugar", "brown rice syrup",
    }, ["SWEETENER"]),

    # --- THICKENER ---
    ({
        # Kroger search terms (canonical)
        "cornstarch", "arrowroot powder", "tapioca starch",
        "unflavored gelatin", "agar agar", "xanthan gum", "guar gum", "pectin",
        # Walmart-specific variants
        "corn starch", "arrowroot",
        "tapioca pearl", "potato starch",
        "agar powder",
    }, ["THICKENER"]),

    # --- ALCOHOL (cooking only) ---
    ({
        # Kroger search terms (canonical)
        "cooking wine", "dry sherry", "mirin", "sake", "rice wine", "shaoxing wine",
        # Walmart-specific variants
        "sake cooking",
    }, ["ALCOHOL"]),

    # --- OTHER_INGR (catch-all pantry) ---
    ({
        # Kroger search terms (canonical)
        "nutritional yeast", "dried mushroom", "nori sheet", "kombu", "wakame",
        "dashi", "bonito flake", "matcha powder",
        "rose water", "liquid smoke",
        "raisins", "dried cranberry", "dried apricot", "dried fig",
        "dried mango", "dried date",
        "canned peach", "canned pear", "canned pineapple",
        "lemon juice", "lime juice",
        "jam", "jelly", "fruit preserves", "marmalade", "chutney",
        "caramel sauce", "sweetened condensed milk",
        "cream of mushroom soup", "cream of chicken soup",
        "harissa", "red curry paste", "green curry paste", "yellow curry paste",
        "coconut butter", "cacao nibs", "vital wheat gluten", "citric acid",
        # Walmart-specific variants
        "porcini dried", "seaweed",
        "orange blossom water",
        "raisin", "currant", "sultana", "dried cherry", "dried blueberry",
        "dried tomato", "canned fruit", "maraschino cherry",
        "lemon juice bottle", "lime juice bottle",
        "fruit spread",
        "caramel topping", "french onion soup can",
        "curry paste", "massaman paste",
        "cacao nib", "carob powder", "meat tenderizer", "vinegar",
    }, ["OTHER_INGR"]),
]

# Pass 2 - if the category name looks like a food/grocery category and the
# product didn't get flagged as a non-ingredient, assume it's an ingredient.
# This knocks out most of what's left without needing the LLM.
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
    "breakfast", "cereal grain",  # NOTE: "cereal grain" ≠ "cereal" (covered by non-ingredient)
}


def normalise(text: str) -> str:
    return text.lower().strip()


def is_food_category(category: str) -> bool:
    """Return True if the category string looks like a food/grocery category."""
    cat = normalise(category)
    return any(kw in cat for kw in FOOD_CATEGORY_KEYWORDS)


def rule_classify(row: dict) -> dict | None:
    name     = normalise(row.get("name", ""))
    category = normalise(row.get("category_name", ""))
    combined = name + " " + category
    # Strip punctuation so "cake topper," or "Coffee-" still match keyword boundaries
    clean  = re.sub(r'[^\w\s]', ' ', combined)
    padded = f" {clean} "

    # Pass 1a: non-ingredient keywords - padded so brand names like "FirstChoiceCandy"
    # don't trigger on the substring "candy". Also check plural form ({kw}s) so
    # "tea bags", "energy bars", "cake toppers" etc. match alongside the singular.
    for kw in NON_INGREDIENT_KEYWORDS:
        if f" {kw} " in padded or f" {kw}s " in padded:
            return {"ingredient": False, "classifiers": []}
    for cat_kw in NON_INGREDIENT_CATEGORIES:
        if cat_kw in category:
            return {"ingredient": False, "classifiers": []}

    # Catch mint/breath-freshener candy products that slip through because a spice or
    # produce keyword (e.g. "cinnamon", "strawberry") fires before the non-ingredient
    # check can see that the product is a candy mint.
    if any(k in name for k in ("breath mint", "sugar free mint", "sugar-free mint",
                                "mint tin", "mints bulk", "mint candy")):
        return {"ingredient": False, "classifiers": []}

    # Priority ingredient checks - run before INGREDIENT_RULES to fix ordering conflicts
    # (e.g. "blueberry yogurt" would match PRODUCE before DAIRY without this)
    for keywords, tags in PRIORITY_INGREDIENT_CHECKS:
        for kw in keywords:
            if kw in combined:
                return {"ingredient": True, "classifiers": tags}

    # Pass 1b: explicit ingredient keywords
    for keywords, tags in INGREDIENT_RULES:
        for kw in keywords:
            if kw in combined:
                return {"ingredient": True, "classifiers": tags}

    # Pass 2: food-category default
    if is_food_category(category):
        return {"ingredient": True, "classifiers": ["OTHER_INGR"]}

    return None  # truly ambiguous -> LLM


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

Respond ONLY with a JSON array - one object per product in the same order.
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
    """Build an LLM prompt line for a single product row."""
    parts = [f"Name: {row.get('name', '').strip()}"]
    if brand := row.get("brandName", "").strip():
        parts.append(f"Brand: {brand}")
    if size := row.get("size", "").strip():
        parts.append(f"Size: {size}")
    if cat := row.get("category_name", "").strip():
        parts.append(f"Category: {cat}")
    if sd := row.get("shortDescription", "").strip()[:200]:
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


# Output columns - matches what fetchProducts.js produces (we added size, brandName, upc
# and dropped the image/color fields we don't need).
OUTPUT_FIELDS = [
    "name", "brandName", "size", "upc",
    "ingredient", "classifiers",
    "retail_price", "thumbnailImage",
]


def read_csvs(folder: str) -> list[dict]:
    csv.field_size_limit(10_000_000)
    rows = []
    for csv_file in Path(folder).glob("*.csv"):
        print(f"  Reading {csv_file.name} ...")
        with open(csv_file, newline="", encoding="utf-8-sig") as f:
            for row in csv.DictReader(f):
                rows.append(row)
    print(f"  Total rows: {len(rows):,}")
    return rows


def write_output(classified: list[dict], output_path: str):
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=OUTPUT_FIELDS)
        writer.writeheader()
        writer.writerows(classified)
    n_ingr = sum(1 for r in classified if r["ingredient"])
    print(f"\nSaved -> {output_path}")
    print(f"   {n_ingr:,} ingredients / {len(classified):,} total products")


def to_output_row(row: dict, result: dict) -> dict:
    return {
        "name":          row.get("name", ""),
        "brandName":     row.get("brandName", ""),
        "size":          row.get("size", ""),
        "upc":           row.get("upc", ""),
        "ingredient":    result.get("ingredient", False),
        "classifiers":   "|".join(result.get("classifiers", [])),
        "retail_price":  row.get("retail_price", ""),
        "thumbnailImage": row.get("thumbnailImage", ""),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Classify Walmart products as cooking ingredients using keyword rules + optional LLM."
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
                        help="Skip LLM pass - output rules + category-default only (fast)")
    args = parser.parse_args()

    print(f"\nReading CSVs from: {args.input_folder}")
    rows = read_csvs(args.input_folder)
    if not rows:
        print("No rows found.")
        return

    # Pass 1 + 2: keyword rules + category fallback (no LLM needed)
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
        classified = [
            to_output_row(row, results[i])
            for i, row in enumerate(rows)
            if results[i] is not None
        ]
        write_output(classified, args.output)
        print(f"   Total wall time: {(time.time()-t0)/60:.1f} min")
        return

    # Pass 3: ask the LLM about anything the rules couldn't figure out
    if llm_queue:
        print(f"\nPass 3: LLM classification for {len(llm_queue):,} products ...")
        print(f"   Model: {args.model}  |  Workers: {args.workers}  |  Batch: {args.batch}")
        print(f"   Tip: make sure you ran  ollama pull {args.model}\n")

        available = check_ollama_running()
        if available is None:
            print("Ollama not reachable - marking unknowns as non-ingredient.")
            for orig_idx, _ in llm_queue:
                results[orig_idx] = {"ingredient": False, "classifiers": []}
        elif args.model.split(":")[0] not in available:
            print(f"WARN Model '{args.model}' not found. Run: ollama pull {args.model}")
            for orig_idx, _ in llm_queue:
                results[orig_idx] = {"ingredient": False, "classifiers": []}
        else:
            only_rows = [r for _, r in llm_queue]
            batches   = [
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
