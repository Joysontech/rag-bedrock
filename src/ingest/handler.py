"""S3-triggered ingestion: chunk, embed, upsert into pgvector."""
import json
import logging
import os
import urllib.parse

import boto3

from shared.bedrock import get_embedding
from shared.chunking import chunk_text
from shared.db import insert_chunks

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")
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

        try:
            response = s3.get_object(Bucket=bucket, Key=key)
            content = response["Body"].read().decode("utf-8", errors="replace")
        except Exception as e:
            log.error("Failed to read s3://%s/%s: %s", bucket, key, e)
            errors.append({"key": key, "error": "read_failed"})
            continue

        chunks = chunk_text(content, max_tokens=800, overlap_tokens=100)
        log.info("Created %d chunks from %s", len(chunks), key)

        if not chunks:
            errors.append({"key": key, "error": "no_chunks"})
            continue

        chunk_records = []
        for i, chunk in enumerate(chunks):
            try:
                embedding = get_embedding(chunk)
                chunk_records.append({
                    "source": key,
                    "chunk_index": i,
                    "content": chunk,
                    "embedding": embedding,
                    "metadata": {"bucket": bucket},
                })
            except Exception as e:
                log.error("Embed failed for chunk %d of %s: %s", i, key, e)

        if not chunk_records:
            errors.append({"key": key, "error": "all_embeds_failed"})
            continue

        try:
            count = insert_chunks(chunk_records, source=key)
            processed.append({"key": key, "chunks": count})
            log.info("Inserted %d chunks for %s", count, key)
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
