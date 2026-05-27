"""Bedrock client wrappers for embeddings and generation."""
import json
import logging
from functools import lru_cache
from typing import List

import boto3

from shared.config import (
    BEDROCK_REGION,
    EMBEDDING_MODEL_ID,
    GENERATION_MODEL_ID,
    EMBEDDING_DIMENSIONS,
)

log = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _client():
    return boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)


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
    prompt: str, max_tokens: int = 1024, temperature: float = 0.2
) -> str:
    """Single-turn Claude invocation. Returns the assistant text."""
    response = _client().invoke_model(
        modelId=GENERATION_MODEL_ID,
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": max_tokens,
            "temperature": temperature,
            "messages": [{"role": "user", "content": prompt}],
        }),
        accept="application/json",
        contentType="application/json",
    )
    result = json.loads(response["body"].read())
    return result["content"][0]["text"]
