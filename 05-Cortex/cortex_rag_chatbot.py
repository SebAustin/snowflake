# cortex_rag_chatbot.py
# Requires paid Snowflake account with Cortex enabled
# Run: python3 cortex_rag_chatbot.py

from connection import get_session
from snowflake.core import Root
import json

session = get_session()

def rag_answer(user_question: str, doc_type_filter: str = None) -> dict:
    """
    RAG pipeline:
    1. Retrieve relevant docs with Cortex Search (hybrid retrieval)
    2. Build context prompt
    3. Generate grounded answer with AI_COMPLETE
    """
    root = Root(session)
    svc = (root.databases["snowflake_learning"]
               .schemas["analytics"]
               .cortex_search_services["company_knowledge_base"])

    # Step 1: Hybrid search
    search_params = {
        "query":   user_question,
        "columns": ["policy_name", "content"],
        "limit":   3
    }
    if doc_type_filter:
        search_params["filter"] = {"@eq": {"policy_name": doc_type_filter}}

    results = svc.search(**search_params)
    docs = results.results

    # Step 2: Build context from retrieved docs
    context = "\n\n".join([
        f"[{d['policy_name']}]:\n{d['content']}"
        for d in docs
    ])

    # Step 3: Generate grounded answer
    prompt = f"""You are a helpful customer support assistant.
Answer the question using ONLY the provided context.
If the answer is not in the context, say "I don't have that information."

Context:
{context}

Question: {user_question}

Answer:"""

    answer_df = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
            'mistral-large2',
            '{prompt.replace("'", "''")}'
        ) AS answer
    """)

    answer = answer_df.collect()[0]["ANSWER"]

    return {
        "question":          user_question,
        "answer":            answer,
        "sources":           [d["policy_name"] for d in docs],
        "docs_retrieved":    len(docs)
    }

# Test the RAG pipeline
questions = [
    "What is your return policy?",
    "How much does shipping cost?",
    "Can I pay with Apple Pay?"
]

print("=" * 60)
print("CORTEX RAG CHATBOT — Company Knowledge Base")
print("=" * 60)

for q in questions:
    result = rag_answer(q)
    print(f"\nQ: {result['question']}")
    print(f"A: {result['answer']}")
    print(f"Sources: {result['sources']}")
    print("-" * 40)
