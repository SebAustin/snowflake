from connection import get_session
from snowflake.snowpark import functions as F
from snowflake.snowpark.window import Window

session = get_session()

# ── Read tables as DataFrames (lazy — no data pulled yet) ──────────────
customers = session.table("snowflake_learning.raw.customers")
orders    = session.table("snowflake_learning.raw.orders_raw")

# Print schema without pulling data
customers.printSchema()

# ── Transformations (still lazy) ───────────────────────────────────────
enriched = (orders
    .filter(F.col("status").isin("PAID", "SHIPPED"))
    .with_column("line_total", F.col("quantity") * F.col("unit_price"))
    .with_column("order_month", F.date_trunc("month", F.col("order_date")))
)

# ── Window function: rank orders by value per month ────────────────────
window = (Window
    .partition_by(F.col("order_month"))
    .order_by(F.col("line_total").desc())
)
enriched = enriched.with_column("revenue_rank", F.rank().over(window))

# ── ACTION: this triggers actual execution ─────────────────────────────
print("\n── Enriched Orders ──")
enriched.show(5)

# ── Join customers (broadcast for small tables) ────────────────────────
result = orders.join(customers, on="customer_id", how="left")
print("\n── Orders with Customer Info ──")
result.select(
    "order_id", "order_date", "status",
    "name", "tier", "unit_price"
).show(5)

# ── Aggregation ────────────────────────────────────────────────────────
customer_metrics = (orders
    .group_by("customer_id")
    .agg(
        F.count("order_id").alias("total_orders"),
        F.sum("unit_price").alias("total_spent"),
        F.avg("unit_price").alias("avg_order_value"),
        F.max("order_date").alias("last_order_date")
    )
    .join(customers.select("customer_id", "name", "tier"), on="customer_id", how="left")
    .sort(F.col("total_spent").desc())
)

print("\n── Customer Metrics ──")
customer_metrics.show()

# ── Write result back to Snowflake ─────────────────────────────────────
customer_metrics.write.mode("overwrite").save_as_table(
    "snowflake_learning.analytics.customer_metrics"
)
print("\n✅ Saved customer_metrics table to Snowflake")