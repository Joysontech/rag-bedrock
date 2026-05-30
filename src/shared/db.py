"""Aurora pgvector connection and vector ops with retry for scale-to-zero."""
import json
import logging
import ssl
import time
from functools import lru_cache
from typing import Any, Dict, List

import boto3
import pg8000.dbapi

from shared.config import AURORA_DATABASE, AURORA_ENDPOINT, AURORA_SECRET_ARN

log = logging.getLogger(__name__)

_connection = None

_MAX_CONNECT_RETRIES = 8
_CONNECT_RETRY_DELAY = 15
_CONNECT_TIMEOUT     = 20


@lru_cache(maxsize=1)
def _get_db_credentials():
    secrets = boto3.client("secretsmanager")
    response = secrets.get_secret_value(SecretId=AURORA_SECRET_ARN)
    creds = json.loads(response["SecretString"])
    return creds["username"], creds["password"]


def _make_ssl_context():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def get_connection():
    """Return a live pg8000 connection. Retries for Aurora scale-to-zero wake-up."""
    global _connection

    if _connection is not None:
        try:
            cur = _connection.cursor()
            cur.execute("SELECT 1")
            cur.close()
            return _connection
        except Exception:
            log.info("Stale connection, reconnecting")
            try:
                _connection.close()
            except Exception:
                pass
            _connection = None

    username, password = _get_db_credentials()
    last_error = None

    for attempt in range(1, _MAX_CONNECT_RETRIES + 1):
        try:
            log.info("Aurora connect attempt %d/%d", attempt, _MAX_CONNECT_RETRIES)
            _connection = pg8000.dbapi.connect(
                host=AURORA_ENDPOINT,
                port=5432,
                database=AURORA_DATABASE,
                user=username,
                password=password,
                ssl_context=_make_ssl_context(),
                timeout=_CONNECT_TIMEOUT,
            )
            log.info("Aurora connected on attempt %d", attempt)
            return _connection
        except Exception as exc:
            last_error = exc
            log.warning("Connect attempt %d/%d failed: %s", attempt, _MAX_CONNECT_RETRIES, exc)
            if attempt < _MAX_CONNECT_RETRIES:
                log.info("Retrying in %ds", _CONNECT_RETRY_DELAY)
                time.sleep(_CONNECT_RETRY_DELAY)

    raise ConnectionError(f"Aurora unreachable after {_MAX_CONNECT_RETRIES} attempts: {last_error}")


def _rows_as_dicts(cursor) -> List[Dict[str, Any]]:
    """Convert pg8000 cursor results to list of dicts."""
    if cursor.description is None:
        return []
    columns = [col[0] for col in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def insert_chunks(chunks: List[Dict[str, Any]], source: str) -> int:
    """Idempotent insert: replaces all chunks for a given source."""
    conn = get_connection()
    cur  = conn.cursor()

    try:
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
            INSERT INTO source_files (s3_key, ingested_at)
            VALUES (%s, now())
            ON CONFLICT (s3_key) DO UPDATE SET ingested_at = EXCLUDED.ingested_at
            """,
            (source,),
        )

        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()

    return len(chunks)


def vector_search(query_embedding: List[float], top_k: int = 5) -> List[Dict[str, Any]]:
    """Cosine similarity search. Returns list of dicts with score."""
    conn = get_connection()
    cur  = conn.cursor()

    try:
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
        return _rows_as_dicts(cur)
    finally:
        cur.close()
