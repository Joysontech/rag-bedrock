"""Query handler: embed question, retrieve, generate, persist session."""
import json
import logging
import os
import time

import boto3

from shared.bedrock import generate_response, get_embedding
from shared.db import vector_search

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

dynamodb = boto3.resource("dynamodb")
sessions = dynamodb.Table(os.environ["SESSIONS_TABLE"])

SESSION_TTL_DAYS = 30
HISTORY_LIMIT    = 5
TOP_K            = 5


def handler(event, context):
    body = event.get("body")
    if isinstance(body, str):
        body = json.loads(body)
    elif body is None:
        body = event

    question   = (body.get("question") or "").strip()
    session_id = body.get("session_id", "anonymous")

    if not question:
        return _err(400, "missing question")

    log.info("Query: session=%s, q=%s", session_id, question[:120])

    try:
        q_embedding = get_embedding(question)
    except Exception as e:
        log.exception("Embedding failed")
        return _err(500, f"embedding failed: {e}")

    try:
        retrieved = vector_search(q_embedding, top_k=TOP_K)
    except Exception as e:
        log.exception("Vector search failed")
        return _err(500, f"vector search failed: {e}")

    log.info("Retrieved %d chunks", len(retrieved))

    history = _load_history(session_id, limit=HISTORY_LIMIT)
    prompt  = _build_prompt(question, retrieved, history)

    try:
        answer = generate_response(prompt)
    except ValueError as e:
        if str(e).startswith("guardrail_intervened"):
            log.warning("Guardrail blocked response for session %s", session_id)
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "answer": "I\'m not able to answer that question.",
                    "guardrail_action": "BLOCKED",
                    "session_id": session_id,
                }),
            }
        return _err(500, f"generation failed: {e}")
    except Exception as e:
        log.exception("Generation failed")
        return _err(500, f"generation failed: {e}")

    _save_message(session_id, question, answer)

    return {
        "statusCode": 200,
        "body": json.dumps({
            "answer": answer,
            "sources": [
                {
                    "key": r["source"],
                    "chunk": r["chunk_index"],
                    "score": float(r["score"]),
                }
                for r in retrieved
            ],
            "session_id": session_id,
        }),
    }


def _build_prompt(question, retrieved, history):
    context_text = "\n\n".join(
        f"[Source: {r['source']}, Chunk: {r['chunk_index']}]\n{r['content']}"
        for r in retrieved
    )

    history_text = ""
    if history:
        history_text = "\n\nPrevious conversation:\n" + "\n".join(
            f"User: {h['question']}\nAssistant: {h['answer']}" for h in history
        )

    return f"""You are a helpful assistant answering questions using only the provided context.

Context:
{context_text}{history_text}

User question: {question}

Answer using only the context above. If the answer is not in the context, say \"I don't have enough information to answer.\" Cite sources inline as [source-key]."""


def _load_history(session_id, limit=5):
    try:
        response = sessions.query(
            KeyConditionExpression="session_id = :sid",
            ExpressionAttributeValues={":sid": session_id},
            ScanIndexForward=False,
            Limit=limit,
        )
        return list(reversed(response.get("Items", [])))
    except Exception as e:
        log.warning("Failed to load history: %s", e)
        return []


def _save_message(session_id, question, answer):
    try:
        ts         = int(time.time() * 1000)
        expires_at = int(time.time()) + (SESSION_TTL_DAYS * 86400)
        sessions.put_item(
            Item={
                "session_id": session_id,
                "timestamp":  ts,
                "question":   question,
                "answer":     answer,
                "expires_at": expires_at,
            }
        )
    except Exception as e:
        log.warning("Failed to save session message: %s", e)


def _err(status, message):
    return {
        "statusCode": status,
        "body": json.dumps({"error": message}),
    }
