from typing import List, Tuple
import joblib

from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, confusion_matrix


def train_model(
    X: List[str],
    y: List[int],
    model_out_path: str = "ingredient_clf.joblib",
    test_size: float = 0.2,
    random_state: int = 42
) -> Pipeline:
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    model = Pipeline([
        ("tfidf", TfidfVectorizer(
            analyzer="char",
            ngram_range=(3, 5),
            min_df=2,
        )),
        ("clf", LogisticRegression(
            max_iter=2000,
            class_weight="balanced",
        ))
    ])

    model.fit(X_train, y_train)

    predictions = model.predict(X_test)

    print("Confusion matrix:")
    print(confusion_matrix(y_test, predictions))
    print("\nClassification report:")
    print(classification_report(y_test, predictions, digits=4))

    joblib.dump(model, model_out_path)
    print(f"\nSaved model to: {model_out_path}")

    return model


def load_model(model_path: str) -> Pipeline:
    return joblib.load(model_path)


def predict_probability(model: Pipeline, text: str) -> float:
    """
    Returns P(ingredient) in [0, 1].
    """
    return float(model.predict_proba([text])[0][1])


def predict_label(model: Pipeline, text: str, threshold: float = 0.5) -> int:
    """
    Returns 1 if P(ingredient) >= threshold else 0.
    """
    return 1 if predict_probability(model, text) >= threshold else 0
