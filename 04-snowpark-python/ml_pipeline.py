from connection import get_session
from snowflake.snowpark import functions as F
from snowflake.snowpark.types import FloatType, IntegerType
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report
import datetime

session = get_session()

# Load customer metrics
df = session.table("snowflake_learning.analytics.customer_metrics").to_pandas()
print("Data shape:", df.shape)
print(df.head())

# Fix: compare date to date (not Timestamp)
df["churned"] = (df["LAST_ORDER_DATE"] < datetime.date(2026, 1, 18)).astype(int)

# Features
feature_cols = ["TOTAL_ORDERS", "TOTAL_SPENT", "AVG_ORDER_VALUE"]
X = df[feature_cols].fillna(0)
y = df["churned"]

print("Churn distribution:")
print(y.value_counts())

# Need at least 2 classes to train — add synthetic rows if needed
if y.nunique() < 2:
    print("Only one class found — adding synthetic rows for demo purposes")
    import numpy as np
    synthetic = pd.DataFrame({
        "TOTAL_ORDERS":    [10, 1,  8, 2],
        "TOTAL_SPENT":     [500, 15, 400, 20],
        "AVG_ORDER_VALUE": [50, 15, 50, 20],
        "churned":         [0,  1,  0,  1]
    })
    X = pd.concat([X, synthetic[feature_cols]], ignore_index=True)
    y = pd.concat([y, synthetic["churned"]], ignore_index=True)

# Train model
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

model = GradientBoostingClassifier(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

preds = model.predict(X_test)
print("Model performance:")
print(classification_report(y_test, preds, zero_division=0))

# Deploy as permanent UDF inside Snowflake
def predict_churn(total_orders: float, total_spent: float, avg_order_value: float) -> int:
    features = [[total_orders, total_spent, avg_order_value]]
    return int(model.predict(features)[0])

churn_udf = session.udf.register(
    predict_churn,
    name="predict_churn",
    is_permanent=True,
    stage_location="@snowflake_learning.raw.raw_data_stage",
    replace=True,
    return_type=IntegerType(),
    input_types=[FloatType(), FloatType(), FloatType()],
    packages=["scikit-learn", "cloudpickle"]
)

# Score all customers inside Snowflake
metrics = session.table("snowflake_learning.analytics.customer_metrics")
scored = metrics.with_column(
    "churn_prediction",
    F.call_udf("predict_churn",
               F.col("TOTAL_ORDERS").cast(FloatType()),
               F.col("TOTAL_SPENT").cast(FloatType()),
               F.col("AVG_ORDER_VALUE").cast(FloatType()))
)

print("Churn predictions:")
scored.select("NAME", "TIER", "TOTAL_SPENT", "churn_prediction").show()

scored.write.mode("overwrite").save_as_table(
    "snowflake_learning.analytics.customer_churn_scores"
)
print("Saved churn scores to Snowflake")
