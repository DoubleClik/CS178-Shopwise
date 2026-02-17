# Need to set OPENAI_API_KEY in shell before running (ask Jake for key, or make one)

from openai import OpenAI
import pandas as pd
import json
import os
from pathlib import Path

client = OpenAI()

# ----- TAGS -----
TAGS = [
    "produce",
    "meat_seafood",
    "dairy_eggs",
    "grains_pasta",
    "baking",
    "spices_extracts",
    "oils_vinegars",
    "condiments_sauces",
    "canned_jarred",
    "frozen",
    "snacks_sweets",
    "beverages",
    "prepared_meal",
    "non_food",
    "unknown",
]

# ----- OpenAI API Query Functions -----

# Output: Yes/Maybe/No
# Use this to skip certain categories to save tokens
def checkCategoryName(file_name):
    response = client.responses.create(
    model="gpt-4.1-mini",
    temperature=0,
    input=[
            {
                "role": "system",
                "content": (
                    "You classify filenames that contain supermarket products. "
                    "You must answer with exactly one word: Yes, No, or Maybe."
                )
            },
            {
                "role": "user",
                "content": (
                    "Decision rules:\n"
                    "- Answer Yes ONLY if the filename clearly and unambiguously implies recipe ingredients or recipe components.\n"
                    "- Answer No ONLY if the filename clearly implies non-ingredients.\n"
                    "- If there is any uncertainty, answer Maybe.\n"
                    "- Default to Maybe when unsure.\n\n"

                    f"{file_name} is a file containing supermarket products. "
                    "From its name alone, determine if it likely contains products "
                    "that can be ingredients in recipes.\n\n"
                    "Answer strictly with one word:\n"
                    "Yes\nNo\nMaybe"
                )
            }
        ]
    )

    return response.output_text


def checkItem(name, shortDescription, longDescription):
    TAGS = [
        "produce","meat_seafood","dairy_eggs","grains_pasta","baking","spices_extracts",
        "oils_vinegars","condiments_sauces","canned_jarred","frozen","snacks_sweets",
        "beverages","prepared_meal","non_food","unknown"
    ]

    # Normalize inputs safely
    name = "" if pd.isna(name) else str(name).strip()
    shortDescription = "" if pd.isna(shortDescription) else str(shortDescription).strip()
    longDescription = "" if pd.isna(longDescription) else str(longDescription).strip()

    response = client.responses.create(
    model="gpt-4.1-mini",
    temperature=0,
    input=[
            {
                "role": "system",
                "content": (
                    "You classify a single supermarket product.\n"
                    "Decide whether it is a recipe ingredient.\n\n"
                    "Your response MUST be valid JSON and NOTHING ELSE.\n\n"
                    "Output format:\n"
                    "- If the product is INGREDIENT:\n"
                    '  {"ingredient": true, "tag": "<one allowed tag>"}\n'
                    "- If the product is NOT_INGREDIENT:\n"
                    '  {"ingredient": false, "tag": null}\n\n'
                    "Definitions:\n"
                    "- INGREDIENT: a product that is clearly and unambiguously used in cooking, baking, or as a component of a dish a recipe.\n"
                    "- NOT_INGREDIENT: a product that is unclear and ambigous in its usage to be cooked, baked, or to be a component of a dish created from a recipe. A product that could be a pre-prepared meal or non-food or supplement product.\n\n"
                    "Rules:\n"
                    "- If classification is INGREDIENT, pick exactly ONE tag from the allowed list that best fits the product.\n"
                    "- If classification is NOT_INGREDIENT, omit the tag field entirely.\n"
                    "- Be conservative: if uncertain, choose NOT_INGREDIENT.\n"
                    "- Use only the provided product text."
                    "- Output JSON only"
                ),
            },
            {
                "role": "user",
                "content": (
                    f"Allowed tags: {TAGS}\n\n"
                    f"Product name: {name}\n"
                    f"Short description: {shortDescription}\n"
                    f"Long description: {longDescription}\n"
                ),
            },
        ]
    )

    # Parse JSON safely
    try:
        return json.loads(response.output_text)
    except json.JSONDecodeError:
        raise ValueError(f"Model returned invalid JSON:\n{response.output_text}")


# ----- CSV Helper Functions -----

#csvToTable converts a Walmart product CSV into a filtered product table.
def csvToTable(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)

    req_columns = [
        "name",
        "retail_price",
        "shortDescription",
        "longDescription",
        "brandName",
        "thumbnailImage",
        "mediumImage",
        "largeImage",
        "color",
    ]

    # Keep only columns that actually exist (defensive)
    existing_columns = [col for col in req_columns if col in df.columns]

    # Return filtered table
    return df[existing_columns]

#csvHasData returns True if the CSV contains at least one data row, False otherwise.
def csvHasData(csv_path: str) -> bool:
    try:
        df = pd.read_csv(csv_path)
    except Exception:
        # Can't find CSV
        return False

    # True if at least one row exists
    return not df.empty

#dfToCsv Saves a pandas DataFrame to a CSV file.
# df (pd.DataFrame): DataFrame to save
# output_path (str): Destination CSV path
# index (bool): Whether to include DataFrame index (default False)
def dfToCsv(df, output_path, index=False):
    # Ensure output directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    df.to_csv(output_path, index=index)



# ----- Main -----

if __name__ == '__main__':
    targetCSVFolder = Path("test2")

    prunedIngredientTable = pd.DataFrame(columns=[
        "name",
        "retail_price",
        "shortDescription",
        "longDescription",
        "brandName",
        "thumbnailImage",
        "mediumImage",
        "largeImage",
        "color",
        "tag",
    ])

    for targetCSVFile in targetCSVFolder.glob("*.csv"):
        print(f"Processing: {targetCSVFile.name}")

        if not csvHasData(targetCSVFile):
            print("  → Skipping empty CSV")
            continue

        df = pd.read_csv(targetCSVFile)

        categoryResponse = checkCategoryName(targetCSVFile)

        if categoryResponse == "Yes":
            numRows = len(df)
            for index, row in df.iterrows():
                print(f"Item {index} out of {numRows}")

                # jsonResult = {"ingredient": True, "tag": "produce"} OR {"ingredient": False, "tag": None}
                jsonResult = checkItem(row["name"], row["shortDescription"], row["longDescription"])
                if jsonResult["ingredient"]:
                    prunedIngredientTable.loc[len(prunedIngredientTable)] = {
                        "name": row["name"],
                        "retail_price": row["retail_price"],
                        "shortDescription": row["shortDescription"],
                        "longDescription": row["longDescription"],
                        "brandName": row["brandName"],
                        "thumbnailImage": row["thumbnailImage"],
                        "mediumImage": row["mediumImage"],
                        "largeImage": row["largeImage"],
                        "color": row["color"],
                        "tag": jsonResult["tag"],
                    }
        #Check random 5, if majority (4+/5) good -> loop through entire thing, if bad, chuck this one out.
        elif categoryResponse == "Maybe":
            print("Maybe good, checking")
            n = min(5, len(df))
            sampled_df = df.sample(n=n)
            yesCount = 0

            for _, row in sampled_df.iterrows():
                checkerResult = checkItem(row["name"], row["shortDescription"], row["longDescription"])
                if checkerResult["ingredient"]:
                    yesCount = yesCount + 1
            
            if yesCount < (n - 1):
                print("  → Not enough good items skipping CSV")
                continue
            
            jsonResult = checkItem(row["name"], row["shortDescription"], row["longDescription"])
            if jsonResult["ingredient"]:
                prunedIngredientTable.loc[len(prunedIngredientTable)] = {
                    "name": row["name"],
                    "retail_price": row["retail_price"],
                    "shortDescription": row["shortDescription"],
                    "longDescription": row["longDescription"],
                    "brandName": row["brandName"],
                    "thumbnailImage": row["thumbnailImage"],
                    "mediumImage": row["mediumImage"],
                    "largeImage": row["largeImage"],
                    "color": row["color"],
                    "tag": jsonResult["tag"],
                }

    dfToCsv(prunedIngredientTable, "result/pruned.csv", index=False)
