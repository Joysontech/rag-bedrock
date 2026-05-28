"""Environment-driven config shared across handlers."""
import os

AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_ENDPOINT = os.environ["AURORA_ENDPOINT"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]
BEDROCK_REGION = os.environ["BEDROCK_REGION"]

EMBEDDING_MODEL_ID = os.environ.get(
    "EMBEDDING_MODEL_ID", "amazon.titan-embed-text-v2:0"
)

# EU cross-region inference profile for Claude Haiku 4.5.
# Requires aws-marketplace:Subscribe on the invoking principal (one-time account setup).
GENERATION_MODEL_ID = os.environ.get(
    "GENERATION_MODEL_ID", "eu.anthropic.claude-haiku-4-5-20251001-v1:0"
)

# Embedding dimensions must match pgvector index (1024 for Titan v2)
EMBEDDING_DIMENSIONS = 1024
