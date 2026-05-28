#!/usr/bin/env bash
#
# Bootstrap the pgvector schema on an Aurora Serverless v2 cluster
# using the RDS Data API (HTTPS, IAM-auth, no VPC access needed).
#
# Usage:
#   bootstrap_db.sh <cluster_arn> <secret_arn> <database> [region]
#
# Idempotent: safe to run repeatedly (all statements use IF NOT EXISTS).

set -euo pipefail

CLUSTER_ARN="${1:?cluster ARN required}"
SECRET_ARN="${2:?secret ARN required}"
DATABASE="${3:?database name required}"
REGION="${4:-eu-west-2}"

run_sql() {
  aws rds-data execute-statement \
    --resource-arn "$CLUSTER_ARN" \
    --secret-arn "$SECRET_ARN" \
    --database "$DATABASE" \
    --region "$REGION" \
    --sql "$1" \
    --no-cli-pager >/dev/null
}

echo "==> Waiting for cluster to accept Data API connections (scale-to-zero wake-up)..."
connected=0
for i in $(seq 1 12); do
  if run_sql "SELECT 1" 2>/dev/null; then
    echo "    connected on attempt $i"
    connected=1
    break
  fi
  echo "    attempt $i failed, cluster waking up, retry in 15s..."
  sleep 15
done

if [ "$connected" -ne 1 ]; then
  echo "ERROR: could not connect to cluster via Data API after 12 attempts" >&2
  exit 1
fi

echo "==> Creating pgvector extension..."
run_sql "CREATE EXTENSION IF NOT EXISTS vector;"

echo "==> Creating documents table..."
run_sql "CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL,
  chunk_index INT NOT NULL,
  content TEXT NOT NULL,
  embedding vector(1024),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);"

echo "==> Creating indexes..."
run_sql "CREATE INDEX IF NOT EXISTS documents_embedding_idx ON documents USING hnsw (embedding vector_cosine_ops);"
run_sql "CREATE INDEX IF NOT EXISTS documents_source_idx ON documents (source);"

echo "==> Creating source_files table..."
run_sql "CREATE TABLE IF NOT EXISTS source_files (
  s3_key TEXT PRIMARY KEY,
  title TEXT,
  chunk_count INT,
  ingested_at TIMESTAMPTZ DEFAULT now(),
  metadata JSONB DEFAULT '{}'::jsonb
);"

echo "==> Verifying..."
run_sql "SELECT extname FROM pg_extension WHERE extname = 'vector';"

echo "==> Schema bootstrap complete."
