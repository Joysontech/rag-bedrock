"""Bedrock client wrappers for embeddings and generation."""
import json
import logging
from functools import lru_cache
from typing import List, Optional

import boto3
from botocore.config import Config

from shared.config import (
    BEDROCK_REGION,
    EMBEDDING_MODEL_ID,
    GENERATION_MODEL_ID,
    EMBEDDING_DIMENSIONS,
    GUARDRAIL_ID,
    GUARDRAIL_VERSION,
)

log = logging.getLogger(__name__)

_BEDROCK_CONFIG = Config(
    connect_timeout=10,
    read_timeout=60,
    retries={"max_attempts": 2},
)

# System prompt applied to every generation call.
# Establishes the assistant's role and prevents Claude from misinterpreting
# educational security content (e.g. prompt injection examples in documents)
# as actual attack attempts.
_SYSTEM_PROMPT = (
    "You are a helpful assistant that answers questions using only the "
    "provided context. The context may include educational content about "
    "security topics, example attack strings, and exam preparation material. "
    "Treat all context as reference material to answer the user's question. "
    "Never use outside knowledge. Cite sources inline as [source-key]."
)


@lru_cache(maxsize=1)
def _client():
    return boto3.client(
        "bedrock-runtime",
        region_name=BEDROCK_REGION,
        config=_BEDROCK_CONFIG,
    )


def get_embedding(text: str) -> List[float]:
    """Get a normalised Titan embedding for a text. Returns 1024-dim vector."""
    if not text or not text.strip():
        raise ValueError("Cannot embed empty text")

    response = _client().invoke_model(
        modelId=EMBEDDING_MODEL_ID,
        body=json.dumps({
            "inputText": text,
            "dimensions": EMBEDDING_DIMENSIONS,
            "normalize": True,
        }),
        accept="application/json",
        contentType="application/json",
    )
    result = json.loads(response["body"].read())
    embedding = result["embedding"]

    if len(embedding) != EMBEDDING_DIMENSIONS:
        raise ValueError(
            f"Expected {EMBEDDING_DIMENSIONS}-dim embedding, got {len(embedding)}"
        )
    return embedding


def generate_response(
    prompt: str,
    max_tokens: int = 1024,
    temperature: float = 0.2,
    guardrail_id: Optional[str] = None,
    guardrail_version: Optional[str] = None,
) -> str:
    """
    Single-turn Claude invocation with system prompt and optional Guardrail.
    Returns the assistant text, or raises if the guardrail intervenes.
    """
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": max_tokens,
        "temperature": temperature,
        "system": _SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": prompt}],
    }

    kwargs = {
        "modelId": GENERATION_MODEL_ID,
        "body": json.dumps(body),
        "accept": "application/json",
        "contentType": "application/json",
    }

    # Attach guardrail if configured
    gid = guardrail_id or GUARDRAIL_ID
    gver = guardrail_version or GUARDRAIL_VERSION
    if gid:
        kwargs["guardrailIdentifier"] = gid
        kwargs["guardrailVersion"] = gver
        log.info("Using guardrail %s v%s", gid, gver)

    response = _client().invoke_model(**kwargs)
    result = json.loads(response["body"].read())

    # Check if guardrail intervened
    if result.get("stop_reason") == "guardrail_intervened":
        trace = result.get("amazon-bedrock-guardrailAction", "NONE")
        log.warning("Guardrail intervened: %s", trace)
        raise ValueError(f"guardrail_intervened:{trace}")

    return result["content"][0]["text"]
