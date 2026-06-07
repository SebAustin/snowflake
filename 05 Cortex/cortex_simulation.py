# Simulating Snowflake Cortex AI patterns using HuggingFace
# In production this runs inside Snowflake as SNOWFLAKE.CORTEX.SENTIMENT()

from connection import get_session
from snowflake.snowpark import functions as F
from snowflake.snowpark.types import StringType, FloatType

session = get_session()

# Load feedback data
feedback_df = session.table(
    "snowflake_learning.analytics.customer_feedback"
).to_pandas()

print("Customer feedback:")
print(feedback_df[["FEEDBACK_ID", "FEEDBACK_TEXT"]].to_string())

# Simulate SENTIMENT using TextBlob (lightweight, no GPU needed)
# In Snowflake: SNOWFLAKE.CORTEX.SENTIMENT(text)
from textblob import TextBlob

def analyze_sentiment(text):
    blob = TextBlob(text)
    score = blob.sentiment.polarity
    if score > 0.1:
        return "positive", score
    elif score < -0.1:
        return "negative", score
    else:
        return "neutral", score

print("\nSentiment Analysis (simulating Cortex SENTIMENT):")
for _, row in feedback_df.iterrows():
    label, score = analyze_sentiment(row["FEEDBACK_TEXT"])
    print(f"  [{row['FEEDBACK_ID']}] {label:8} ({score:+.2f}) | {row['FEEDBACK_TEXT'][:50]}...")

# Simulate AI_CLASSIFY
categories = ["shipping", "product_quality", "customer_service", "pricing"]

def classify_feedback(text):
    text_lower = text.lower()
    if any(w in text_lower for w in ["shipping", "delivery", "package", "arrived"]):
        return "shipping"
    elif any(w in text_lower for w in ["quality", "product", "purchase", "disappointed"]):
        return "product_quality"
    elif any(w in text_lower for w in ["support", "service", "staff", "team"]):
        return "customer_service"
    else:
        return "general"

print("\nClassification (simulating Cortex AI_CLASSIFY):")
for _, row in feedback_df.iterrows():
    category = classify_feedback(row["FEEDBACK_TEXT"])
    print(f"  [{row['FEEDBACK_ID']}] {category:20} | {row['FEEDBACK_TEXT'][:50]}...")

# Save results back to Snowflake
import pandas as pd
results = []
for _, row in feedback_df.iterrows():
    label, score = analyze_sentiment(row["FEEDBACK_TEXT"])
    category = classify_feedback(row["FEEDBACK_TEXT"])
    results.append({
        "FEEDBACK_ID":      int(row["FEEDBACK_ID"]),
        "SENTIMENT_LABEL":  label,
        "SENTIMENT_SCORE":  float(score),
        "CATEGORY":         category
    })

results_df = pd.DataFrame(results)
snow_df = session.create_dataframe(results_df)
snow_df.write.mode("overwrite").save_as_table(
    "snowflake_learning.analytics.feedback_analysis"
)
print("\nSaved feedback_analysis table to Snowflake")
