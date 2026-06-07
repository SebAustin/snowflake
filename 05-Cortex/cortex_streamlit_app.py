# cortex_streamlit_app.py
# Deploy as Streamlit in Snowflake (SiS)
# In Snowflake UI: Projects > Streamlit > + Streamlit App
# Or via CLI: snow streamlit deploy

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

st.set_page_config(page_title="Customer Feedback AI", page_icon="❄️")
st.title("❄️ Customer Feedback Analyzer")
st.caption("Powered by Snowflake Cortex AI")

tab1, tab2, tab3 = st.tabs(["Sentiment Analysis", "Knowledge Base", "Generate Report"])

# ── TAB 1: Sentiment Analysis ─────────────────────────────────
with tab1:
    st.subheader("Analyze Customer Feedback")

    feedback_input = st.text_area(
        "Enter feedback text:",
        placeholder="Type customer feedback here...",
        height=100
    )

    if st.button("Analyze", type="primary"):
        if feedback_input:
            result = session.sql(f"""
                SELECT
                    SNOWFLAKE.CORTEX.SENTIMENT('{feedback_input.replace("'", "''")}')  AS sentiment,
                    SNOWFLAKE.CORTEX.SUMMARIZE('{feedback_input.replace("'", "''")}')  AS summary,
                    SNOWFLAKE.CORTEX.AI_CLASSIFY(
                        '{feedback_input.replace("'", "''")}',
                        ['shipping','product_quality','pricing','customer_service']
                    ):label::STRING AS category
            """).collect()[0]

            col1, col2, col3 = st.columns(3)
            score = result["SENTIMENT"]
            label = "POSITIVE" if score > 0.3 else "NEGATIVE" if score < -0.3 else "NEUTRAL"
            color = "green" if label == "POSITIVE" else "red" if label == "NEGATIVE" else "orange"

            col1.metric("Sentiment", label, f"{score:+.2f}")
            col2.metric("Category", result["CATEGORY"])
            col3.metric("Score", f"{score:.3f}")

            st.info(f"**Summary:** {result['SUMMARY']}")

    # Show all feedback with AI analysis
    st.subheader("All Customer Feedback")
    df = session.sql("""
        SELECT
            feedback_id,
            feedback_text,
            ROUND(SNOWFLAKE.CORTEX.SENTIMENT(feedback_text), 2) AS sentiment,
            SNOWFLAKE.CORTEX.AI_CLASSIFY(
                feedback_text,
                ['shipping','product_quality','pricing','customer_service']
            ):label::STRING AS category
        FROM customer_feedback
        ORDER BY sentiment
    """).to_pandas()
    st.dataframe(df, use_container_width=True)

# ── TAB 2: Knowledge Base Chat ────────────────────────────────
with tab2:
    st.subheader("Ask about Company Policies")

    if "messages" not in st.session_state:
        st.session_state.messages = []

    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.write(msg["content"])

    if prompt := st.chat_input("Ask about returns, shipping, payments..."):
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Searching knowledge base..."):
                context_df = session.sql("""
                    SELECT content FROM company_policies
                """).to_pandas()
                context = " ".join(context_df["CONTENT"].tolist())

                response = session.sql(f"""
                    SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
                        'snowflake-arctic-instruct',
                        'Answer based on this context only: {context[:500]}. Question: {prompt.replace("'", "''")}'
                    ) AS response
                """).collect()[0]["RESPONSE"]

            st.write(response)
            st.session_state.messages.append({
                "role": "assistant",
                "content": response
            })

# ── TAB 3: Report Generation ──────────────────────────────────
with tab3:
    st.subheader("AI-Generated Executive Report")

    if st.button("Generate Report", type="primary"):
        with st.spinner("Analyzing all feedback with Cortex AI..."):
            metrics = session.sql("""
                SELECT
                    COUNT(*)                                                          AS total,
                    SUM(CASE WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) > 0.3
                             THEN 1 ELSE 0 END)                                      AS positive,
                    SUM(CASE WHEN SNOWFLAKE.CORTEX.SENTIMENT(feedback_text) < -0.3
                             THEN 1 ELSE 0 END)                                      AS negative,
                    ROUND(AVG(SNOWFLAKE.CORTEX.SENTIMENT(feedback_text)), 2)         AS avg_score
                FROM customer_feedback
            """).collect()[0]

            summary = session.sql(f"""
                SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
                    'snowflake-arctic-instruct',
                    'Write a 3-sentence executive summary. Total: {metrics["TOTAL"]}, Positive: {metrics["POSITIVE"]}, Negative: {metrics["NEGATIVE"]}, Avg sentiment: {metrics["AVG_SCORE"]}. Be specific and actionable.'
                ) AS summary
            """).collect()[0]["SUMMARY"]

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Total Feedback", metrics["TOTAL"])
        col2.metric("Positive", metrics["POSITIVE"])
        col3.metric("Negative", metrics["NEGATIVE"])
        col4.metric("Avg Sentiment", metrics["AVG_SCORE"])

        st.subheader("Executive Summary")
        st.success(summary)
