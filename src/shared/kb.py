"""Bedrock Knowledge Base query using RetrieveAndGenerate API."""
import logging
from functools import lru_cache
from typing import Any, Dict

import boto3

from shared.config import BEDROCK_REGION, KB_GENERATION_MODEL_ID, KNOWLEDGE_BASE_ID

log = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _runtime_client():
    return boto3.client("bedrock-agent-runtime", region_name=BEDROCK_REGION)


def query_knowledge_base(question: str, num_results: int = 5) -> Dict[str, Any]:
    """
    Query a Bedrock Knowledge Base using RetrieveAndGenerate.

    Note: modelArn must be a direct foundation model ARN - NOT a
    cross-region inference profile ID (no eu./us. prefix).
    RetrieveAndGenerate validates against GetInferenceProfile which
    rejects cross-region profiles.
    """
    if not KNOWLEDGE_BASE_ID:
        raise ValueError("KNOWLEDGE_BASE_ID env var not set")

    model_arn = (
        f"arn:aws:bedrock:{BEDROCK_REGION}::foundation-model/{KB_GENERATION_MODEL_ID}"
    )

    log.info("KB query: kb=%s model=%s", KNOWLEDGE_BASE_ID, KB_GENERATION_MODEL_ID)

    response = _runtime_client().retrieve_and_generate(
        input={"text": question},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": KNOWLEDGE_BASE_ID,
                "modelArn": model_arn,
                "retrievalConfiguration": {
                    "vectorSearchConfiguration": {
                        "numberOfResults": num_results,
                    }
                },
            },
        },
    )

    answer = response["output"]["text"]

    sources = []
    seen = set()
    for citation in response.get("citations", []):
        for ref in citation.get("retrievedReferences", []):
            uri = ref.get("location", {}).get("s3Location", {}).get("uri", "")
            if uri and uri not in seen:
                seen.add(uri)
                key = "/".join(uri.split("/")[3:]) if uri.startswith("s3://") else uri
                sources.append({"key": key})

    log.info("KB answer: %d chars, %d sources", len(answer), len(sources))
    return {"answer": answer, "sources": sources}
