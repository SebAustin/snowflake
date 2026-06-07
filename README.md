# Snowflake Learning Project

A hands-on curriculum for building on Snowflake — from warehouse setup and data loading through pipelines, dbt transformations, Snowpark Python, Cortex AI, and data governance.

Each module is self-contained SQL or Python you can run in a Snowflake trial or dev account.

## Project Structure

```
Snowflake/
├── 01-foundations/          # Warehouse setup, stages, COPY INTO, VARIANT
├── 02-pipelines/            # Streams & Tasks, Dynamic Tables
├── 03-dbt/                  # dbt project (staging + marts)
├── 04-snowpark-python/      # DataFrames, UDFs, ML pipeline
├── 05-Cortex/               # Cortex AI, RAG chatbot, Streamlit app
└── 06-Governance & RAG/     # RBAC, masking, row access, PII tagging
```

## Modules

### 01 — Foundations
- **Lab 1** — Create a `learning_wh` warehouse, resource monitor, database, and schemas
- **Lab 2** — Load data with stages, file formats, `COPY INTO`, and semi-structured `VARIANT` columns

### 02 — Pipelines
- **Lab 3** — Change Data Capture with Streams and scheduled Tasks
- **Lab 4** — Declarative pipelines with Dynamic Tables (deduplication, incremental refresh)

### 03 — dbt
A dbt project targeting Snowflake with the Jaffle Shop sample data:
- **Staging** — `stg_customers`, `stg_orders` (views)
- **Marts** — `dim_customers`, `fct_orders` (tables)
- **Seeds** — Raw CSV reference data

```bash
cd 03-dbt
dbt deps
dbt seed
dbt run
dbt test
```

Configure your connection in `~/.dbt/profiles.yml` (not committed to this repo).

### 04 — Snowpark Python
Python scripts using Snowpark DataFrames:
- `dataframes.py` — Lazy transforms and aggregations
- `udfs.py` — User-defined functions in Snowflake
- `ml_pipeline.py` — End-to-end ML workflow with churn scoring

### 05 — Cortex AI
Snowflake Cortex and generative AI examples:
- `cortex_simulation.py` — Cortex functions without a paid account
- `cortex_rag_chatbot.py` — RAG pipeline with Cortex Search + `AI_COMPLETE`
- `cortex_streamlit_app.py` — Streamlit in Snowflake (sentiment, knowledge base, reports)

> Cortex Search and some AI functions require a paid Snowflake account with Cortex enabled.

### 06 — Governance & RAG
- Role hierarchy (access roles → functional roles → users)
- Dynamic Data Masking policies on PII columns
- Row Access Policies for regional data isolation
- Tag-based governance and audit queries

## Prerequisites

| Tool | Version |
|------|---------|
| Snowflake account | Trial or dev |
| Python | 3.9+ |
| dbt-core + dbt-snowflake | 1.9.4 recommended |

```bash
pip install "dbt-snowflake==1.9.4" "dbt-core==1.9.4"
```

For Snowpark and Cortex scripts:

```bash
pip install snowflake-snowpark-python snowflake-ml-python streamlit
```

## Getting Started

1. Clone the repo and open the Snowflake UI or SnowSQL
2. Run **Lab 1** to create the `snowflake_learning` database and `learning_wh` warehouse
3. Work through modules in order — each lab builds on concepts from the previous ones
4. Set up `~/.dbt/profiles.yml` before running the dbt project (see [dbt profiles docs](https://docs.getdbt.com/docs/core/connect-data-platform/profiles.yml))

## Database Layout

All labs use a shared database:

| Schema | Purpose |
|--------|---------|
| `raw` | Landing zone — stages, raw tables, VARIANT data |
| `staging` | Cleaned, typed data (dbt staging layer) |
| `analytics` | Business-ready marts and Cortex services |
| `governance` | Tags, policies, audit metadata |

## What's Not in the Repo

The following are excluded via `.gitignore`:

- `dbt-env/` — Python virtual environment
- `logs/` — dbt run logs
- `03-dbt/target/` — Compiled dbt artifacts
- `03-dbt/dbt_packages/` — Installed dbt packages
- `.env` — Credentials and secrets

## Author

[SebAustin](https://github.com/SebAustin)
