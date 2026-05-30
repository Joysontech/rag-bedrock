# rag-bedrock

Production-shaped RAG system on AWS Bedrock — built entirely via the AWS console, no Terraform or CDK required.

Built as hands-on prep for the **AWS Certified Generative AI Developer Professional (AIP-C01)** certification.

📝 **Medium article**: [Build a Production RAG System on AWS Bedrock from Scratch](https://joysonfernandes.medium.com/build-a-production-rag-system-on-aws-bedrock-from-scratch-c6449d4de8e5)

📖 **Full guide (repo)**: [blog/rag-bedrock-blog.md](./blog/rag-bedrock-blog.md)

---

## What This Is

A complete Retrieval Augmented Generation system using AWS Bedrock and supporting services. You upload a document, it gets chunked, embedded, and indexed. You ask a question, it retrieves relevant chunks and generates a grounded, cited answer.

Two RAG paths for comparison:
- **DIY RAG** (`POST /query`): pgvector retrieval + Claude Haiku 4.5 + Prompt Management + Guardrails
- **Managed RAG** (`POST /query-kb`): Bedrock Knowledge Bases RetrieveAndGenerate

---

## Architecture

```
S3 (docs/)
  └── S3 event → Lambda Ingest → Titan Embeddings v2 → Aurora pgvector

API Gateway (JWT auth via Cognito)
  └── POST /query    → Lambda Query → pgvector search → Claude Haiku 4.5
  └── POST /query-kb → Lambda Query → Bedrock Knowledge Base
  └── POST /ingest   → Lambda Ingest (manual trigger)

All traffic stays inside AWS via VPC PrivateLink — no NAT Gateway, no internet egress.
```

| Service | Role |
|---------|------|
| Amazon Bedrock | Claude Haiku 4.5 (generation), Titan Embeddings V2 (1024-dim vectors) |
| Amazon Aurora Serverless v2 | pgvector store, HNSW index, scale-to-zero |
| AWS Lambda (Python 3.12) | Ingest and query orchestration, private VPC subnets |
| Amazon DynamoDB | Session history with TTL (30 days) |
| Amazon S3 | Document storage, eval datasets |
| Amazon API Gateway | HTTP API with JWT authoriser |
| Amazon Cognito | User Pool, public client, USER_PASSWORD_AUTH |
| Bedrock Guardrails | Content filters, denied topics, PII masking, contextual grounding (0.75) |
| Bedrock Prompt Management | Versioned prompt templates, audit trail via prompt_arn |
| Bedrock Knowledge Bases | Managed RAG with S3 Vectors store |
| Bedrock Evaluations | LLM-as-judge: Sonnet judges Haiku on 8 AIP-C01 questions |
| VPC PrivateLink | bedrock-runtime, bedrock-agent, bedrock-agent-runtime, secretsmanager, logs |

---

## Repository Structure

```
rag-bedrock/
├── src/
│   ├── ingest/
│   │   ├── handler.py          # S3 event handler: chunk → embed → upsert
│   │   └── requirements.txt    # pg8000==1.31.2
│   ├── query/
│   │   ├── handler.py          # API handler: embed → search → generate
│   │   └── requirements.txt    # pg8000==1.31.2
│   └── shared/
│       ├── bedrock.py          # Titan embeddings + Claude generation with system prompt
│       ├── chunking.py         # Recursive text chunking (800 tokens, 100 overlap)
│       ├── config.py           # env var loading
│       ├── db.py               # pg8000 Aurora connection + vector search
│       ├── kb.py               # Bedrock Knowledge Base RetrieveAndGenerate
│       └── prompts.py          # Prompt Management fetch + fallback template
├── docs/
│   ├── aip-c01-exam-guide.md  # RAG corpus: AIP-C01 exam guide (all 5 domains)
│   └── evals/
│       └── eval-dataset.jsonl # 8 AIP-C01 Q&A pairs for Bedrock Evaluations
├── blog/
│   └── rag-bedrock-blog.md    # Full console-first build guide
└── README.md
```

---

## Setup

Every AWS resource is created via the console. The repo only provides the Lambda code.

**Full step-by-step guide**: [Medium article](https://joysonfernandes.medium.com/build-a-production-rag-system-on-aws-bedrock-from-scratch-c6449d4de8e5) or [blog/rag-bedrock-blog.md](./blog/rag-bedrock-blog.md)

**Quick summary of phases:**

1. S3 bucket + DynamoDB sessions table
2. VPC: 2 private subnets, 3 security groups, 7 VPC endpoints (2 gateway, 5 interface)
3. Aurora Serverless v2 + pgvector schema via RDS Query Editor
4. Lambda functions: package, upload, set handler to `handler.handler`, configure env vars
5. API Gateway HTTP API + Cognito User Pool (public client, no secret)
6. Bedrock Guardrails: content filters, denied topics, contextual grounding 0.75
7. Bedrock Prompt Management: versioned RAG prompt with `{{context}}` and `{{question}}`
8. Bedrock Knowledge Bases: S3 Vectors store, sync docs
9. Bedrock Evaluations: LLM-as-judge with 8-question AIP-C01 dataset

---

## Lambda Packaging

No platform flags needed — `pg8000` is pure Python:

```bash
cd ~/rag-bedrock
git fetch origin && git reset --hard origin/main

rm -rf ~/Desktop/lambda-packages
mkdir -p ~/Desktop/lambda-packages/ingest-package
mkdir -p ~/Desktop/lambda-packages/query-package

pip3 install -r src/ingest/requirements.txt -t ~/Desktop/lambda-packages/ingest-package
cp src/ingest/handler.py ~/Desktop/lambda-packages/ingest-package/
cp -r src/shared ~/Desktop/lambda-packages/ingest-package/
cd ~/Desktop/lambda-packages/ingest-package && zip -r ~/Desktop/lambda-packages/ingest.zip . && cd ~/rag-bedrock

pip3 install -r src/query/requirements.txt -t ~/Desktop/lambda-packages/query-package
cp src/query/handler.py ~/Desktop/lambda-packages/query-package/
cp -r src/shared ~/Desktop/lambda-packages/query-package/
cd ~/Desktop/lambda-packages/query-package && zip -r ~/Desktop/lambda-packages/query.zip . && cd ~/rag-bedrock
```

Upload both zips via the Lambda console (Code tab → Upload from → .zip file).

> **Important**: After uploading, change the handler in **Runtime settings** from `lambda_function.lambda_handler` to `handler.handler`.

---

## Query Lambda Environment Variables

| Key | Value |
|-----|-------|
| `AURORA_SECRET_ARN` | Secrets Manager ARN for Aurora credentials |
| `AURORA_ENDPOINT` | Aurora cluster writer endpoint |
| `AURORA_DATABASE` | `ragdb` |
| `SESSIONS_TABLE` | `rag-bedrock-sessions` |
| `DOCS_BUCKET` | Your S3 bucket name |
| `BEDROCK_REGION` | `eu-west-2` |
| `EMBEDDING_MODEL_ID` | `amazon.titan-embed-text-v2:0` |
| `GENERATION_MODEL_ID` | `eu.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `KB_GENERATION_MODEL_ID` | `anthropic.claude-3-7-sonnet-20250219-v1:0` |
| `GUARDRAIL_ID` | Your Guardrail ID |
| `GUARDRAIL_VERSION` | `1` |
| `PROMPT_ARN` | `arn:aws:bedrock:eu-west-2:ACCOUNTID:prompt/PROMPTID:1` |
| `KNOWLEDGE_BASE_ID` | Your Knowledge Base ID |
| `LOG_LEVEL` | `INFO` |

---

## Test

```bash
# Get a JWT
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id YOUR_CLIENT_ID \
  --auth-parameters USERNAME=your@email.com,PASSWORD=YourPassword \
  --region eu-west-2 \
  --query 'AuthenticationResult.IdToken' \
  --output text)

# DIY RAG query
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"What percentage of the AIP-C01 exam does Domain 1 cover?","session_id":"test-1"}' \
  | python3 -m json.tool

# Knowledge Base query
curl -s -X POST "YOUR_API_ENDPOINT/query-kb" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"Which AWS service should I use for large-scale RAG with hybrid search?","session_id":"test-2"}' \
  | python3 -m json.tool

# Guardrail block test
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"Should I invest my savings in stocks?","session_id":"test-3"}' \
  | python3 -m json.tool
```

---

## AIP-C01 Coverage

| Domain | Weight | Covered by |
|--------|--------|-----------|
| Foundation Model Integration and Data Management | 31% | pgvector, Titan Embeddings, Knowledge Bases, chunking |
| GenAI Application Implementation and Integration | 26% | Lambda, API Gateway, Prompt Management, session history |
| AI Safety, Security and Governance | 20% | Guardrails, IAM, VPC endpoints, Cognito JWT |
| Operational Excellence and Efficiency | 12% | Scale-to-zero Aurora, model cost comparison, inference profiles |
| Testing, Validation and Troubleshooting | 11% | Bedrock Evaluations, LLM-as-judge, faithfulness scoring |

---

## Region

`eu-west-2` (London). Cross-region inference profile used for Claude Haiku 4.5: `eu.anthropic.claude-haiku-4-5-20251001-v1:0`.

---

## Resources

- [Medium article](https://joysonfernandes.medium.com/build-a-production-rag-system-on-aws-bedrock-from-scratch-c6449d4de8e5)
- [Full build guide (repo)](./blog/rag-bedrock-blog.md)
- [AIP-C01 exam guide doc](./docs/aip-c01-exam-guide.md)
- [Eval dataset](./docs/evals/eval-dataset.jsonl)
- [AIP-C01 Udemy course](https://www.udemy.com/course/ultimate-aws-certified-generative-ai-developer-professional/)
- [AWS Bedrock docs](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
