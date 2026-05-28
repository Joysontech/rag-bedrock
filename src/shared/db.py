"""Aurora pgvector connection and vector ops with retry for scale-to-zero."""
import json
import logging
import time
from functools import lru_cache
from typing import Any, Dict, List

import boto3
import psycopg
from psycopg.rows import dict_row

from shared.config import AURORA_DATABASE, AURORA_ENDPOINT, AURORA_SECRET_ARN

log = logging.getLogger(__name__)

_connection = None

_MAX_CONNECT_RETRIES = 8
_CONNECT_RETRY_DELAY = 15    # seconds between retries
_CONNECT_TIMEOUT = 20        # seconds per individual attempt


@lru_cache(maxsize=1)
def _get_db_credentials():
    secrets = boto3.client("secretsmanager")
    response = secrets.get_secret_value(SecretId=AURORA_SECRET_ARN)
    creds = json.loads(response["SecretString"])
    return creds["username"], creds["password"]


def get_connection():
    """Return a live psycopg connection. Retries for Aurora scale-to-zero wake-up."""
    global _connection

    if _connection is not None:
        try:
            with _connection.cursor() as cur:
                cur.execute("SELECT 1")
            return _connection
        except (psycopg.OperationalError, psycopg.InterfaceError):
            log.info("Stale connection detected, will reconnect")
            try:
                _connection.close()
            except Exception:
                pass
            _connection = None

    username, password = _get_db_credentials()
    last_error = None

    for attempt in range(1, _MAX_CONNECT_RETRIES + 1):
        try:
            log.info(
                "Aurora connect attempt %d/%d (host=%s)",
                attempt, _MAX_CONNECT_RETRIES, AURORA_ENDPOINT,
            )
            _connection = psycopg.connect(
                host=AURORA_ENDPOINT,
                port=5432,
                dbname=AURORA_DATABASE,
                user=username,
                password=password,
                sslmode="require",
                connect_timeout=_CONNECT_TIMEOUT,
            )
            log.info("Aurora connected on attempt %d", attempt)
            return _connection
        except Exception as exc:
            last_error = exc
            log.warning(
                "Aurora connect attempt %d/%d failed: %s",
                attempt, _MAX_CONNECT_RETRIES, exc,
            )
            if attempt < _MAX_CONNECT_RETRIES:
                log.info("Retrying in %ds (cluster may be waking from scale-to-zero)", _CONNECT_RETRY_DELAY)
                time.sleep(_CONNECT_RETRY_DELAY)

    raise ConnectionError(
        f"Aurora unreachable after {_MAX_CONNECT_RETRIES} attempts: {last_error}"
    )


def insert_chunks(chunks: List[Dict[str, Any]], source: str) -> int:
    """Idempotent insert: replaces all chunks for a given source."""
    conn = get_connection()

    with conn.cursor() as cur:
        cur.execute("DELETE FROM documents WHERE source = %s", (source,))

        for chunk in chunks:
            cur.execute(
                """
                INSERT INTO documents (source, chunk_index, content, embedding, metadata)
                VALUES (%s, %s, %s, %s::vector, %s::jsonb)
                """,
                (
                    chunk["source"],
                    chunk["chunk_index"],
                    chunk["content"],
                    str(chunk["embedding"]),
                    json.dumps(chunk.get("metadata", {})),
                ),
            )

        cur.execute(
            """
            INSERT INTO source_files (s3_key, chunk_count, ingested_at, metadata)
            VALUES (%s, %s, now(), %s::jsonb)
            ON CONFLICT (s3_key) DO UPDATE SET
                chunk_count = EXCLUDED.chunk_count,
                ingested_at = EXCLUDED.ingested_at,
                metadata    = EXCLUDED.metadata
            """,
            (source, len(chunks), json.dumps({})),
        )

    conn.commit()
    return len(chunks)


def vector_search(query_embedding: List[float], top_k: int = 5) -> List[Dict[str, Any]]:
    """Cosine similarity search. Returns list of dicts with score."""
    conn = get_connection()

    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            SELECT
                id::text,
                source,
                chunk_index,
                content,
                metadata,
                1 - (embedding <=> %s::vector) AS score
            FROM documents
            ORDER BY embedding <=> %s::vector
            LIMIT %s
            """,
            (str(query_embedding), str(query_embedding), top_k),
        )
        return cur.fetchall()
