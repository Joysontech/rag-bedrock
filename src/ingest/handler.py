"""S3-triggered ingestion: chunk, embed, upsert into pgvector."""
import json
import logging
import os
import urllib.parse

import boto3
from botocore.config import Config

from shared.bedrock import get_embedding
from shared.chunking import chunk_text
from shared.db import insert_chunks

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_S3_CONFIG = Config(connect_timeout=10, read_timeout=30)
s3 = boto3.client("s3", config=_S3_CONFIG)
DOCS_BUCKET = os.environ["DOCS_BUCKET"]


def handler(event, context):
    """S3-triggered ingestion. Also handles direct invokes for testing."""
    records = event.get("Records", [])
    if not records:
        log.info("No Records in event; nothing to ingest")
        return {
            "statusCode": 200,
            "body": json.dumps({"status": "no-records"}),
        }

    processed = []
    errors = []

    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if bucket != DOCS_BUCKET:
            log.warning("Skipping unexpected bucket: %s", bucket)
            continue

        log.info("Processing s3://%s/%s", bucket, key)

        # --- Step 1: read from S3 ---
        try:
            log.info("[step 1/4] Reading from S3")
            response = s3.get_object(Bucket=bucket, Key=key)
            content = response["Body"].read().decode("utf-8", errors="replace")
            log.info("[step 1/4] Read %d bytes from %s", len(content), key)
        except Exception as e:
            log.error("Failed to read s3://%s/%s: %s", bucket, key, e)
            errors.append({"key": key, "error": "read_failed"})
            continue

        # --- Step 2: chunk ---
        log.info("[step 2/4] Chunking content")
        chunks = chunk_text(content, max_tokens=800, overlap_tokens=100)
        log.info("[step 2/4] Created %d chunks from %s", len(chunks), key)

        if not chunks:
            errors.append({"key": key, "error": "no_chunks"})
            continue

        # --- Step 3: embed ---
        chunk_records = []
        for i, chunk in enumerate(chunks):
            try:
                log.info("[step 3/4] Embedding chunk %d/%d", i + 1, len(chunks))
                embedding = get_embedding(chunk)
                chunk_records.append({
                    "source": key,
                    "chunk_index": i,
                    "content": chunk,
                    "embedding": embedding,
                    "metadata": {"bucket": bucket},
                })
                log.info("[step 3/4] Chunk %d/%d embedded (%d dims)", i + 1, len(chunks), len(embedding))
            except Exception as e:
                log.error("Embed failed for chunk %d of %s: %s", i, key, e)

        if not chunk_records:
            errors.append({"key": key, "error": "all_embeds_failed"})
            continue

        # --- Step 4: insert into pgvector ---
        try:
            log.info("[step 4/4] Inserting %d chunks for %s into pgvector", len(chunk_records), key)
            count = insert_chunks(chunk_records, source=key)
            processed.append({"key": key, "chunks": count})
            log.info("[step 4/4] Inserted %d chunks for %s", count, key)
        except Exception as e:
            log.error("Insert failed for %s: %s", key, e)
            errors.append({"key": key, "error": "insert_failed"})

    return {
        "statusCode": 200 if not errors else 207,
        "body": json.dumps({
            "status": "ok" if not errors else "partial",
            "processed": processed,
            "errors": errors,
        }),
    }
