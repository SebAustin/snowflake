from connection import get_session
from snowflake.snowpark import functions as F
from snowflake.snowpark.types import StringType, FloatType, IntegerType

session = get_session()

# SCALAR UDF: runs inside Snowflake, one row at a time
@F.udf(name="classify_order_value",
       is_permanent=True,
       stage_location="@snowflake_learning.raw.raw_data_stage",
       replace=True,
       return_type=StringType(),
       input_types=[FloatType()],
       session=session)
def classify_order_value(order_value: float) -> str:
    if order_value is None:
        return "UNKNOWN"
    if order_value >= 200:
        return "WHALE"
    elif order_value >= 100:
        return "HIGH"
    elif order_value >= 25:
        return "MEDIUM"
    else:
        return "LOW"

# Use the UDF on the orders table
orders = session.table("snowflake_learning.raw.orders_raw")

orders_segmented = orders.with_column(
    "order_segment",
    F.call_udf("classify_order_value", F.col("unit_price"))
)

print("Orders with segment:")
orders_segmented.select(
    "order_id", "customer_id", "unit_price", "order_segment"
).show()

# Count orders per segment
print("Segment breakdown:")
orders_segmented.group_by("order_segment").agg(
    F.count("order_id").alias("order_count"),
    F.avg("unit_price").alias("avg_price")
).sort("avg_price", ascending=False).show()

print("UDF registered and executed successfully")
