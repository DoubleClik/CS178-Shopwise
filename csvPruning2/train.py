from data_collection import make_dataset
from model import train_model, load_model, predict_probability


def main() -> None:
    csv_path = "RecipesDataset.csv"

    X, y = make_dataset(csv_path, max_per_class=50_000, seed=42, balance_classes=True)
    train_model(X, y, model_out_path="ingredient_clf.joblib")

    model = load_model("ingredient_clf.joblib")
    demo_items = ["Yellow Onions 3 Lb Bag", "OLIPOP Prebiotic Soda, Tropical Punch, 12 fl oz, 12 Pack, Refrigerated", "spatula", "kosher salt"]
    for item in demo_items:
        p = predict_probability(model, item)
        print(f"{item!r} -> P(ingredient)={p:.3f}")


if __name__ == "__main__":
    main()
