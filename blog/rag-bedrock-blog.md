---
title: "Build a Production RAG System on AWS Bedrock — No Terraform, Console-First (Full AIP-C01 Prep)"
published: false
description: "A complete hands-on guide to building Retrieval Augmented Generation on AWS Bedrock using the AWS console. Covers pgvector, Guardrails, Prompt Management, Knowledge Bases, Evaluations and API Gateway — everything you need to pass the AWS Certified Generative AI Developer exam."
tags: aws, bedrock, ai, machinelearning
cover_image: https://dev-to-uploads.s3.amazonaws.com/uploads/articles/placeholder.png
---

> 📌 **GitHub repo**: [github.com/joysontech/rag-bedrock](https://github.com/joysontech/rag-bedrock) — Lambda code, schema scripts and packaging helpers are all here. You only need it for the Lambda code. Every AWS service is set up via the console.

> 🎓 **AIP-C01 prep**: This guide covers all five exam domains with real infrastructure. I also recommend the [Ultimate AWS Certified Generative AI Developer Professional](https://www.udemy.com/course/ultimate-aws-certified-generative-ai-developer-professional/) course alongside this.

---

## What You Will Build

A production-shaped Retrieval Augmented Generation system on AWS Bedrock — set up entirely through the AWS console, no Terraform or CDK required.

By the end of this guide you will have:

- Documents stored in **S3** and automatically chunked, embedded, and indexed into **Aurora Serverless v2 with pgvector**
- Semantic search over your documents using **Titan Embeddings v2** (1024-dimension vectors, HNSW index)
- Grounded answers from **Claude Haiku 4.5** using retrieved context
- **Bedrock Guardrails** blocking prompt injection, PII leakage, and off-topic queries
- **Bedrock Prompt Management** for versioned, auditable prompts with A/B testing capability
- **Bedrock Knowledge Bases** as the managed alternative — compared side-by-side with your DIY system
- **Bedrock Evaluations** running LLM-as-judge quality scoring
- A secured **API Gateway + Cognito** HTTPS endpoint usable from any client
- Everything runs in a **private VPC with no internet access** — all Bedrock calls go through PrivateLink

> 📸 **Screenshot placeholder**: Architecture diagram showing all services

---

## AIP-C01 Exam Domain Coverage

| Domain | Weight | What this guide covers |
|--------|--------|----------------------|
| Foundation Model Integration and Data Management | 31% | RAG, embeddings, pgvector, Bedrock model IDs, Knowledge Bases, chunking strategies, vector store options |
| GenAI Application Implementation and Integration | 26% | Lambda orchestration, API Gateway, Prompt Management, session history, inference profiles |
| AI Safety, Security and Governance | 20% | Guardrails, IAM least-privilege, VPC endpoints, JWT auth, PII filtering |
| Operational Excellence and Efficiency | 12% | Model selection, cost optimisation, inference profiles, Aurora scale-to-zero |
| Testing, Validation and Troubleshooting | 11% | LLM-as-judge evaluation, groundedness scoring, correctness metrics |

---

## Architecture Overview

The system has two main data flows:

**Document Ingest**: Upload a file to S3 under the `docs/` prefix → S3 event triggers the Ingest Lambda → Lambda chunks the text (800 tokens, 100 overlap) → embeds each chunk via Titan Embeddings v2 → upserts the 1024-dimension vectors into Aurora pgvector with an HNSW index.

**Query**: Client sends `POST /query` with a JWT token → API Gateway validates via Cognito → Query Lambda embeds the question → runs cosine similarity search in pgvector → fetches the versioned prompt from Prompt Management → calls Claude Haiku 4.5 with the context, applying Guardrails → returns grounded answer with sources, scores, and the prompt ARN used.

A second path, `POST /query-kb`, routes to Bedrock's managed `RetrieveAndGenerate` API instead of the custom pgvector retrieval, letting you compare both approaches on the same question.

All compute runs in private subnets. Every AWS service call goes through VPC PrivateLink endpoints. No NAT Gateway, no internet egress.

---

## Prerequisites

Before starting you need:

- An AWS account with an **admin IAM user** configured via `aws configure`
- Python 3.12, Git, and the AWS CLI installed locally
- The GitHub repo cloned: `git clone https://github.com/joysontech/rag-bedrock.git`

**Add Marketplace permissions to your IAM user.** The newer Claude models (Haiku 4.5, the EU cross-region inference profiles) require your IAM user to have these permissions to invoke them the first time:

1. IAM console → Users → your user → **Add permissions** → **Create inline policy**
2. Choose JSON editor and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "aws-marketplace:ViewSubscriptions",
      "aws-marketplace:Subscribe",
      "aws-marketplace:Unsubscribe"
    ],
    "Resource": "*"
  }]
}
```

3. Name the policy `bedrock-marketplace` and save.

> **AIP-C01 note**: Cross-region inference profiles (the `eu.` prefix on a model ID) route requests across AWS regions for higher availability. The first invocation per AWS account requires Marketplace subscription by the invoking principal. Direct foundation model IDs (e.g. `anthropic.claude-3-7-sonnet-20250219-v1:0`) do not require this.

---

## Phase 1: Supporting Resources

### 1.1 Create the S3 Docs Bucket

1. **S3 console → Create bucket**
2. Bucket name: `rag-bedrock-docs-YOURACCOUNTID` (replace with your 12-digit account ID for global uniqueness)
3. Region: `eu-west-2`
4. Block all public access: **enabled** (leave default)
5. Versioning: **Enable**
6. Default encryption: **SSE-S3**
7. Create bucket

> 📸 **Screenshot**: S3 bucket creation form with versioning and encryption enabled

After creating the bucket, create two prefixes by uploading a placeholder file:
- Upload any text file to `docs/` (drag and drop into the console, prefix the filename with `docs/`)
- Upload any text file to `evals/` for evaluation datasets

> **Why the docs/ prefix matters**: The Lambda S3 event notification is filtered to `docs/` only. Evaluation datasets, results files, and anything else you upload to the bucket will not trigger ingestion. This prevents eval data from contaminating your vector store — a real production concern.

### 1.2 Create the DynamoDB Sessions Table

1. **DynamoDB console → Create table**
2. Table name: `rag-bedrock-sessions`
3. Partition key: `session_id` (String)
4. Sort key: `timestamp` (Number)
5. Table settings: **Customize settings**
6. Capacity mode: **On-demand**
7. Encryption: **Owned by Amazon DynamoDB**
8. Create table

After creation, enable TTL:
1. Open the table → **Additional settings** tab
2. Time to live (TTL): **Enable** → attribute name: `expires_at`

> **Why DynamoDB for sessions**: Lambda is stateless. Each invocation needs to load the last N conversation turns to maintain context. DynamoDB with TTL gives you automatic expiry (30 days), millisecond reads, and no server to manage. The sort key on `timestamp` lets you query the N most recent turns efficiently.

---

## Phase 2: VPC and Networking

This is the most console-intensive phase. Take your time — getting the VPC right means no debugging later.

### 2.1 Create the VPC

1. **VPC console → Your VPCs → Create VPC**
2. Resources to create: **VPC and more**
3. Name tag: `rag-bedrock`
4. IPv4 CIDR: `10.42.0.0/16`
5. Number of Availability Zones: **2** (eu-west-2a, eu-west-2b)
6. Number of public subnets: **0** (no public subnets needed)
7. Number of private subnets: **2**
8. NAT gateways: **None** (we use VPC endpoints instead — saves ~£30/month)
9. VPC endpoints: **None** (we create them manually below for full control)
10. Create VPC

> 📸 **Screenshot**: VPC creation wizard showing 0 public subnets, 2 private subnets, no NAT gateway

Note the VPC ID and both private subnet IDs — you need them when creating Lambda functions.

### 2.2 Create a Route Table

The VPC wizard creates subnets but may not create a dedicated route table. Create one explicitly:

1. **VPC console → Route tables → Create route table**
2. Name: `rag-bedrock-private-rt`
3. VPC: `rag-bedrock-vpc`
4. Create route table
5. Select the new route table → **Subnet associations** tab → **Edit subnet associations**
6. Tick both private subnets → Save associations

### 2.3 Create Security Groups

You need three security groups. Create each via **VPC console → Security Groups → Create security group**, selecting your new VPC.

**Security Group 1: Lambda**
- Name: `rag-bedrock-lambda-sg`
- Description: Lambda functions
- Inbound rules: none
- Outbound rules:
  - Type: Custom TCP, Port: 5432, Destination: `10.42.0.0/16` (Aurora access within VPC)
  - Type: HTTPS (443), Destination: `10.42.0.0/16` (for VPC interface endpoints)
  - Type: HTTPS (443), Destination: `0.0.0.0/0` (for S3 and DynamoDB gateway endpoints)

> **Why the third outbound rule**: S3 and DynamoDB use gateway endpoints (free, route-table based) rather than interface endpoints. Even with gateway endpoints configured, the Lambda security group still needs outbound 443 to `0.0.0.0/0` because the gateway endpoint routes traffic via the routing table using the S3/DynamoDB public IP ranges. Without this, S3 calls silently hang for 5 minutes.

**Security Group 2: Aurora**
- Name: `rag-bedrock-aurora-sg`
- Inbound rules: Custom TCP, Port 5432, Source: `rag-bedrock-lambda-sg` (select the SG by ID)
- Outbound rules: none needed

**Security Group 3: VPC Endpoints**
- Name: `rag-bedrock-endpoints-sg`
- Inbound rules: HTTPS (443), Source: `10.42.0.0/16`
- Outbound rules: none needed

> 📸 **Screenshot**: Lambda security group showing the three outbound rules

### 2.4 Create VPC Endpoints

You need five interface endpoints and two gateway endpoints. Create each via **VPC console → Endpoints → Create endpoint**.

**Gateway endpoints (free — create these first):**

Endpoint 1 — S3:
- Service category: **AWS services**
- Service name: search for `s3` and select `com.amazonaws.eu-west-2.s3` (Gateway type)
- VPC: your VPC
- Route tables: select `rag-bedrock-private-rt`

Endpoint 2 — DynamoDB:
- Service name: `com.amazonaws.eu-west-2.dynamodb` (Gateway type)
- Same VPC and route tables

**Interface endpoints (billable at ~£0.008/hr/AZ each):**

For each of the five below, use:
- Service category: AWS services
- VPC: your VPC
- Subnets: both private subnets
- Security group: `rag-bedrock-endpoints-sg`
- Private DNS enabled: **Yes**

| Service Name | What it enables |
|-------------|----------------|
| `com.amazonaws.eu-west-2.bedrock-runtime` | `InvokeModel` — embeddings and generation |
| `com.amazonaws.eu-west-2.bedrock-agent` | `GetPrompt` — Prompt Management fetch |
| `com.amazonaws.eu-west-2.bedrock-agent-runtime` | `RetrieveAndGenerate` — Knowledge Bases |
| `com.amazonaws.eu-west-2.secretsmanager` | `GetSecretValue` — Aurora credentials |
| `com.amazonaws.eu-west-2.logs` | CloudWatch log delivery |

> 📸 **Screenshot**: VPC endpoints list showing all 7 endpoints in Available state

> **AIP-C01 note — VPC endpoint to Bedrock service mapping**: A common exam scenario is "a Lambda in a private subnet cannot reach Bedrock Knowledge Bases." The answer is a missing `bedrock-agent-runtime` endpoint. Know which endpoint enables which API:
> - `bedrock-runtime` → `InvokeModel`
> - `bedrock-agent` → `GetPrompt` (Prompt Management)
> - `bedrock-agent-runtime` → `RetrieveAndGenerate` and `Retrieve` (Knowledge Bases)

---

## Phase 3: Aurora Serverless v2 with pgvector

### 3.1 Create the Aurora Cluster

1. **RDS console → Create database**
2. Engine: **Aurora (PostgreSQL Compatible)**
3. Engine version: **Aurora PostgreSQL 16.4** (or latest 16.x)
4. Templates: **Dev/Test**
5. DB cluster identifier: `rag-bedrock-cluster`
6. Credentials: **Managed in AWS Secrets Manager** (check this box — it auto-creates and rotates the password)
7. Instance configuration: **Serverless v2**
8. Capacity range: Min **0** ACU, Max **2** ACU (scale-to-zero when idle)
9. Connectivity:
   - VPC: your VPC
   - Subnets: create a new DB subnet group using both private subnets
   - Public access: **No**
   - VPC security group: `rag-bedrock-aurora-sg`
10. Additional configuration:
    - Enable the **RDS Data API** checkbox (required for the schema bootstrap)
    - Initial database name: `ragdb`
11. Encryption: **AWS managed key** (do NOT use a customer-managed key — if you destroy the cluster, a CMK goes into PendingDeletion for 7-30 days and makes automated snapshots unrestorable)
12. Create database

> 📸 **Screenshot**: Aurora creation showing Serverless v2 with scale-to-zero, Data API enabled, Secrets Manager credentials

Wait for the cluster status to show **Available** (3-5 minutes).

Note the **cluster endpoint** (not the instance endpoint) — it looks like `rag-bedrock-cluster.cluster-xxxx.eu-west-2.rds.amazonaws.com`. Also note the **Secret ARN** from the Secrets Manager console.

### 3.2 Bootstrap the Database Schema

Aurora is now running but has no tables. Use the **RDS Query Editor** (built into the console — no VPN or bastion needed) to run the setup SQL.

1. **RDS console → Query Editor**
2. Cluster: `rag-bedrock-cluster`
3. Database: `ragdb`
4. Authentication: **Connect with a Secrets Manager ARN** → paste your Secret ARN
5. Run the following SQL statements one at a time:

```sql
-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Source files tracking table
CREATE TABLE IF NOT EXISTS source_files (
  id        bigserial PRIMARY KEY,
  s3_key    text NOT NULL UNIQUE,
  ingested_at timestamptz DEFAULT now()
);

-- Document chunks with 1024-dimension vectors (Titan v2)
CREATE TABLE IF NOT EXISTS documents (
  id          bigserial PRIMARY KEY,
  source      text NOT NULL,
  chunk_index integer NOT NULL,
  content     text NOT NULL,
  embedding   vector(1024),
  metadata    jsonb,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(source, chunk_index)
);

-- HNSW index for fast approximate nearest-neighbour search
CREATE INDEX IF NOT EXISTS documents_embedding_idx
  ON documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

> 📸 **Screenshot**: RDS Query Editor showing successful extension creation

> **AIP-C01 note — pgvector index types**:
> - **Flat (none)**: exact search, O(n), fine for < 10k vectors
> - **IVFFlat**: approximate, good recall for large datasets (1M+), needs training
> - **HNSW**: approximate, best recall/speed tradeoff for typical RAG (10k–1M vectors), higher memory usage
>
> For RAG, HNSW with `vector_cosine_ops` is the standard choice. The `<=>` operator computes cosine distance; subtracting from 1 gives cosine similarity.

---

## Phase 4: Lambda Functions

### 4.1 Create the Lambda IAM Role

1. **IAM console → Roles → Create role**
2. Trusted entity: **AWS service → Lambda**
3. Attach these managed policies:
   - `AWSLambdaBasicExecutionRole`
   - `AWSLambdaVPCAccessExecutionRole`
4. Name the role: `rag-bedrock-lambda-role`
5. Create role

Now add a custom inline policy. Open the role → **Add permissions → Create inline policy → JSON**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ApplyGuardrail"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockKB",
      "Effect": "Allow",
      "Action": [
        "bedrock:Retrieve",
        "bedrock:RetrieveAndGenerate",
        "bedrock:GetPrompt"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsRead",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:eu-west-2:YOURACCOUNTID:secret:rds!*"
    },
    {
      "Sid": "S3Docs",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::rag-bedrock-docs-YOURACCOUNTID",
        "arn:aws:s3:::rag-bedrock-docs-YOURACCOUNTID/*"
      ]
    },
    {
      "Sid": "DynamoSessions",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:eu-west-2:YOURACCOUNTID:table/rag-bedrock-sessions"
    },
    {
      "Sid": "KmsViaSvc",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": [
            "secretsmanager.eu-west-2.amazonaws.com",
            "rds.eu-west-2.amazonaws.com"
          ]
        }
      }
    }
  ]
}
```

Replace `YOURACCOUNTID` with your 12-digit AWS account ID. Name the policy `rag-bedrock-lambda-policy`.

### 4.2 Package the Lambda Code

```bash
cd ~/rag-bedrock
git fetch origin && git reset --hard origin/main

rm -rf ~/Desktop/lambda-packages
mkdir -p ~/Desktop/lambda-packages/ingest-package
mkdir -p ~/Desktop/lambda-packages/query-package

# Ingest Lambda — pure Python driver, no platform flags needed
pip3 install -r src/ingest/requirements.txt \
  -t ~/Desktop/lambda-packages/ingest-package
cp src/ingest/handler.py ~/Desktop/lambda-packages/ingest-package/
cp -r src/shared ~/Desktop/lambda-packages/ingest-package/
cd ~/Desktop/lambda-packages/ingest-package
zip -r ~/Desktop/lambda-packages/ingest.zip .
cd ~/rag-bedrock

# Query Lambda
pip3 install -r src/query/requirements.txt \
  -t ~/Desktop/lambda-packages/query-package
cp src/query/handler.py ~/Desktop/lambda-packages/query-package/
cp -r src/shared ~/Desktop/lambda-packages/query-package/
cd ~/Desktop/lambda-packages/query-package
zip -r ~/Desktop/lambda-packages/query.zip .
cd ~/rag-bedrock

# Verify pg8000 is in both zips
echo "=== ingest.zip ===" && unzip -l ~/Desktop/lambda-packages/ingest.zip | grep pg8000
echo "=== query.zip ===" && unzip -l ~/Desktop/lambda-packages/query.zip | grep pg8000
```

Both `ingest.zip` and `query.zip` will be on your Desktop inside `lambda-packages/`.

### 4.3 Create the Ingest Lambda

1. **Lambda console → Create function → Author from scratch**
2. Function name: `rag-bedrock-ingest`
3. Runtime: **Python 3.12**, Architecture: x86_64
4. Execution role: **Use an existing role** → `rag-bedrock-lambda-role`
5. Create function
6. **Code** tab → **Upload from → .zip file** → upload `ingest.zip`
7. **Code** tab → scroll to **Runtime settings** → **Edit** → Handler: `handler.handler` → Save
8. **Configuration → General configuration** → Edit: Memory **1024 MB**, Timeout **5 min**
9. **Configuration → VPC** → Edit: your VPC, both private subnets, `rag-bedrock-lambda-sg`
10. **Configuration → Environment variables** → Add:

| Key | Value |
|-----|-------|
| `AURORA_SECRET_ARN` | Your Secret ARN from Secrets Manager |
| `AURORA_ENDPOINT` | Your cluster writer endpoint |
| `AURORA_DATABASE` | `ragdb` |
| `DOCS_BUCKET` | `rag-bedrock-docs-YOURACCOUNTID` |
| `BEDROCK_REGION` | `eu-west-2` |
| `EMBEDDING_MODEL_ID` | `amazon.titan-embed-text-v2:0` |
| `GENERATION_MODEL_ID` | `eu.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `LOG_LEVEL` | `INFO` |

> 📸 **Screenshot**: Lambda VPC configuration showing private subnets and security group

> **Important**: The default handler in the Lambda console is `lambda_function.lambda_handler`. You must change it to `handler.handler` via the **Runtime settings** section on the Code tab. Without this change the Lambda will fail with `No module named 'lambda_function'`.

### 4.4 Create the Query Lambda

Same steps as the Ingest Lambda with:
- Function name: `rag-bedrock-query`
- Upload `query.zip`
- Handler: `handler.handler` (same change required)
- Same env vars plus:

| Key | Value |
|-----|-------|
| `SESSIONS_TABLE` | `rag-bedrock-sessions` |
| `GUARDRAIL_ID` | *(fill in after Phase 6)* |
| `GUARDRAIL_VERSION` | `1` |
| `PROMPT_ARN` | *(fill in after Phase 7)* |
| `KNOWLEDGE_BASE_ID` | *(fill in after Phase 8)* |
| `KB_GENERATION_MODEL_ID` | `anthropic.claude-3-7-sonnet-20250219-v1:0` |

### 4.5 Set Up the S3 Event Notification

1. **Lambda console → rag-bedrock-ingest → Configuration → Triggers → Add trigger**
2. Source: **S3**
3. Bucket: `rag-bedrock-docs-YOURACCOUNTID`
4. Event types: **All object create events**
5. Prefix: `docs/`
6. Acknowledge the recursive invocation warning → Add

> 📸 **Screenshot**: S3 trigger configuration showing docs/ prefix filter

---

## Phase 4.6: Ingest Your First Document

With the Ingest Lambda deployed and the S3 trigger configured, the ingestion pipeline is fully working. You do **not** need API Gateway or Cognito for this step — ingestion runs entirely on the S3 → Lambda → Bedrock Titan → Aurora path.

Upload the AIP-C01 exam guide from the repo via the S3 console:

1. S3 console → your bucket → click into the `docs/` folder
2. **Upload → Add files** → select `docs/aip-c01-exam-guide.md` from the repo
3. Upload

The upload triggers the Ingest Lambda automatically. Watch it process:

```bash
aws logs tail /aws/lambda/rag-bedrock-ingest --since 2m --follow
```

You should see four steps complete:

```
[step 1/4] Reading from S3
[step 2/4] Created N chunks from docs/aip-c01-exam-guide.md
[step 3/4] Embedding chunk 1/N (1024 dims)
[step 4/4] Inserted N chunks for docs/aip-c01-exam-guide.md
```

Verify the chunks landed in pgvector via RDS Query Editor:

```sql
SELECT source, count(*) AS chunks
FROM documents
GROUP BY source;
```

You should see `docs/aip-c01-exam-guide.md` with several rows. Once this returns data, your RAG system has something to retrieve from and you can continue to Phase 5.

> **Why this document**: The exam guide covers all five AIP-C01 domains with detailed factual content. Once ingested, you can ask the RAG system questions like "Which VPC endpoint enables the Knowledge Bases API?" or "What percentage of the exam does Domain 1 cover?" and get grounded, cited answers drawn directly from the document.

> **Why the docs/ prefix matters**: The S3 event notification is filtered to `docs/` only. If you later upload eval datasets or results files to `evals/`, they will not trigger ingestion and cannot contaminate your vector store. Without this filter, every file upload into the bucket gets embedded — a subtle but common production data quality issue.

---

## Phase 5: API Gateway and Cognito

### 5.1 Create the Cognito User Pool

1. **Cognito console → Create user pool**
2. Sign-in options: **Email**
3. Password policy: minimum 12 characters, upper, lower, numbers
4. MFA: **No MFA**
5. Self-registration: disable (you will create the test user manually)
6. User pool name: `rag-bedrock-users`
7. App client:
   - App type: **Public client** (no secret — required for CLI token requests)
   - App client name: `rag-bedrock-cli`
   - Auth flows: enable **ALLOW_USER_PASSWORD_AUTH** and **ALLOW_REFRESH_TOKEN_AUTH**
   - Client secret: **toggle OFF** (critical — a secret requires a HMAC on every auth call)
8. Access token expiry: **60 minutes**, Refresh token: **30 days**
9. Create user pool

Note the **User Pool ID** and **App client ID**.

**Create and confirm a test user:**

```bash
# Create the user (note: --user-attributes required when email is a required field)
aws cognito-idp sign-up \
  --client-id YOUR_CLIENT_ID \
  --username your@email.com \
  --password YourPassword123 \
  --user-attributes Name=email,Value=your@email.com \
  --region eu-west-2

# Set password as permanent (skips the forced reset flow)
aws cognito-idp admin-set-user-password \
  --user-pool-id YOUR_POOL_ID \
  --username your@email.com \
  --password YourPassword123 \
  --permanent \
  --region eu-west-2
```

> 📸 **Screenshot**: Cognito user showing Confirmed status

> **Important**: The console creates a confidential client with a secret by default when you choose "Traditional web application". Always create a **Public client** with the secret toggle off for CLI and API testing. A client secret requires computing a SECRET_HASH on every auth call — not supported by the plain `initiate-auth` CLI command.

### 5.2 Create the API Gateway HTTP API

1. **API Gateway console → Create API → HTTP API → Build**
2. Integration: Lambda → `rag-bedrock-query`
3. API name: `rag-bedrock-api`
4. Stage name: `$default`, Auto-deploy: **On**
5. Create

Note the **Invoke URL** from the Stages page.

### 5.3 Add the JWT Authorizer

1. Your API → **Authorization → Manage authorizers → Create**
2. Type: **JWT**, Name: `cognito-jwt`
3. Identity source: `$request.header.Authorization`
4. Issuer URL: `https://cognito-idp.eu-west-2.amazonaws.com/YOUR_POOL_ID`
5. Audience: your app client ID
6. Create

> 📸 **Screenshot**: JWT authorizer configuration showing Cognito issuer URL

### 5.4 Configure Routes

Create three routes, each with the `cognito-jwt` authorizer attached:

| Method | Path | Integration |
|--------|------|-------------|
| POST | `/query` | `rag-bedrock-query` |
| POST | `/query-kb` | `rag-bedrock-query` |
| POST | `/ingest` | `rag-bedrock-ingest` |

> 📸 **Screenshot**: API Gateway routes list showing three routes with JWT authorizer attached

> **AIP-C01 note — HTTP API vs REST API**: HTTP APIs support JWT authorizers natively, cost ~70% less than REST APIs, and use payload format 2.0. Use REST API only when you specifically need API keys, WAF integration, or request/response transformations.

---

## Phase 6: Bedrock Guardrails

1. **Bedrock console → Guardrails → Create guardrail**
2. Name: `rag-bedrock-guardrail`
3. **Content filters**: all six categories → **Medium**, Prompt Attack → **High**
4. **Denied topics**: add `Personal financial advice`
5. **Sensitive information filters**: Email/Phone → **Mask**, Credit card/NI → **Block**
6. **Contextual grounding**: enable both, threshold **0.75**
7. Create → **Create version**

Note the **Guardrail ID**. Update Query Lambda env vars:
- `GUARDRAIL_ID` = your ID
- `GUARDRAIL_VERSION` = `1`

> 📸 **Screenshot**: Contextual grounding configuration with 0.75 thresholds

> **AIP-C01 note**: Contextual grounding checks the answer against the retrieved context, not against ground truth. Threshold 0.75 means answers less than 75% supported by context are blocked — catching hallucinations before they reach the user. This is particularly important for document-grounded Q&A: if the answer contains a claim that isn't clearly supported by the retrieved chunks, the Guardrail blocks it and substitutes a safe message.

---

## Phase 7: Bedrock Prompt Management

Prompt Management versions your system prompt like code. Instead of hardcoding it in Lambda, it lives in Bedrock with a version history and an audit trail in every API response.

1. **Bedrock console → Prompt management → Create prompt**
2. Name: `rag-query-generate`
3. Description: `RAG generation prompt for AIP-C01 exam guide Q&A`
4. Model: Claude Haiku 4.5, Temperature: **0.2**, Max tokens: **1024**
5. System instructions:
```
You are a helpful assistant answering questions about AWS certifications and cloud services using only the provided context. Never use outside knowledge. Cite sources inline as [source-key].
```
6. User message:
```
Context:
{{context}}

User question: {{question}}

Answer using only the context above. If the answer is not in the context, say "I don't have enough information to answer that." Cite sources inline as [source-key].
```
7. Delete the Assistant message field if it appears (empty block causes a `ContentBlock is blank` validation error)
8. In the **Test variables** section fill in:
   - **context**: `[Source: docs/aip-c01-exam-guide.md] The AIP-C01 exam is divided into five domains. Domain 1: Foundation Model Integration and Data Management covers 31% of the exam. Domain 2: GenAI Application Implementation and Integration covers 26%. Domain 3: AI Safety, Security and Governance covers 20%. Domain 4: Operational Excellence and Efficiency covers 12%. Domain 5: Testing, Validation and Troubleshooting covers 11%.`
   - **question**: `What percentage of the AIP-C01 exam does Domain 1 cover?`
9. Click **Run** — expected answer: Domain 1 covers 31%
10. Click **Create version** → note the **Prompt ARN**

> 📸 **Screenshot**: Prompt Management builder showing system instructions, two variables, and a successful test run

Update Query Lambda:
- `PROMPT_ARN` = `arn:aws:bedrock:eu-west-2:ACCOUNTID:prompt/PROMPTID:1`

> **AIP-C01 note — prompt versioning workflow**: To roll out a new prompt without redeploying Lambda: edit in the console → create version 2 → update the Lambda env var `PROMPT_ARN` from `:1` to `:2`. The `prompt_arn` field in every API response provides a complete audit trail: you know exactly which prompt version generated any given answer.

> **Gotcha**: The console prompt builder creates CHAT-type prompts (with system instructions + message turns), not TEXT-type. The Lambda code in this repo handles both types.

---

## Phase 8: Bedrock Knowledge Bases

Knowledge Bases are the managed alternative to your DIY pgvector pipeline. Bedrock handles chunking, embedding, indexing, retrieval, and generation. Compare it against your DIY system on the same question.

1. **Bedrock console → Knowledge bases → Create**
2. Name: `rag-bedrock-kb`
3. IAM role: **Create and use a new service role**
4. Data source: **Amazon S3** → `s3://rag-bedrock-docs-YOURACCOUNTID/`
5. Parsing: **Amazon Bedrock default parser**
6. Chunking: **Default chunking** (300 tokens, 20% overlap)
7. Embeddings: **Titan Text Embeddings V2**
8. Vector store: **Quick create → Amazon S3 Vectors**
9. Create → **Sync**

Note the **Knowledge Base ID**. Update Query Lambda:
- `KNOWLEDGE_BASE_ID` = your KB ID

> 📸 **Screenshot**: Knowledge Base showing S3 Vectors vector store and Sync Complete status

**Run the side-by-side comparison:**

```bash
QUESTION="Which AWS service should I use as a vector store for large-scale RAG with hybrid search support?"

echo "=== DIY RAG (pgvector + Claude Haiku 4.5) ===" && \
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"question\":\"$QUESTION\",\"session_id\":\"compare-diy\"}" \
  | python3 -m json.tool

echo "=== Knowledge Base (managed + Claude 3.7 Sonnet) ===" && \
curl -s -X POST "YOUR_API_ENDPOINT/query-kb" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"question\":\"$QUESTION\",\"session_id\":\"compare-kb\"}" \
  | python3 -m json.tool
```

Both return **Amazon OpenSearch Serverless** as the answer. The difference is in the response structure:

### DIY RAG vs Knowledge Bases — side by side

| Dimension | DIY RAG | Knowledge Base |
|-----------|---------|----------------|
| Answer | Grounded, cited with chunk numbers and similarity scores | Grounded, cited with source file only |
| Inline citations | Yes: `[source-key, Chunk: N]` | No |
| Similarity scores | Exposed (e.g. 0.786) | Not exposed |
| Prompt versioning | Yes — `prompt_arn` in every response | No |
| Session history | Yes — DynamoDB | Not built in |
| Chunking control | Full — 800 tokens, 100 overlap | Fixed at creation — 300 tokens |
| Model | Claude Haiku 4.5 (cheap, fast) | Claude 3.7 Sonnet (stronger) |
| Setup complexity | High — VPC, pgvector, Lambda, IAM | Low — console wizard |

Both systems return factually correct, grounded answers. The difference is observability. DIY tells you exactly what was retrieved, how similar it was, which prompt version generated the answer, and what the user asked before. Knowledge Base gives you the answer with no visibility into the why.

---

## Phase 9: Bedrock Evaluations

### 9.1 Create the Evaluation Dataset

The eval dataset is already in the repo at `docs/evals/eval-dataset.jsonl`. Upload it directly to S3:

```bash
aws s3 cp docs/evals/eval-dataset.jsonl \
  s3://rag-bedrock-docs-YOURACCOUNTID/evals/eval-dataset.jsonl
```

Or via the S3 console: navigate to your bucket → `evals/` folder → Upload → select `docs/evals/eval-dataset.jsonl`.

The dataset contains 8 AIP-C01 questions with reference answers covering all five domains:

```jsonl
{"prompt": "Which VPC endpoint enables the RetrieveAndGenerate API?", "referenceResponse": "The bedrock-agent-runtime VPC endpoint enables the RetrieveAndGenerate and Retrieve APIs for Knowledge Bases.", "category": "question_answering"}
{"prompt": "What percentage of the AIP-C01 exam does Domain 1 cover?", "referenceResponse": "Domain 1 (Foundation Model Integration and Data Management) covers 31% of the AIP-C01 exam.", "category": "question_answering"}
{"prompt": "When should I use RAG instead of fine-tuning?", "referenceResponse": "Use RAG for frequently updated knowledge, large document corpora, and when auditability matters. Use fine-tuning for style consistency, domain vocabulary, and classification tasks with static training data.", "category": "question_answering"}
```

### 9.2 Create the Evaluation Job

1. **Bedrock console → Evaluations → Create → Automatic: LLM as a judge**
2. Job name: `rag-bedrock-eval-v1`
3. Evaluator (judge): **Claude Sonnet 4.6** (stronger than the evaluated model)
4. Generator (evaluated model): **Claude Haiku 4.5**
5. Metrics: **Correctness, Faithfulness, Completeness, Relevance**
6. Dataset S3 URI: `s3://rag-bedrock-docs-YOURACCOUNTID/evals/eval-dataset.jsonl`
7. Output S3 URI: `s3://rag-bedrock-docs-YOURACCOUNTID/evals/results/`
8. IAM role: **Create and use a new service role**
9. Create

> 📸 **Screenshot**: Evaluation results showing scores for all four metrics

> **AIP-C01 note**: The judge should be stronger than the evaluated model. Sonnet judges Haiku here. Faithfulness near 1.0 means the model is not hallucinating — everything it says is traceable to the retrieved context. Correctness compares against your reference answers.

---

## Errors I Hit and How to Fix Them

These are the real errors encountered when building this system. Every one of them will appear in some form when you follow this guide.

---

### Error 1: `Runtime.ImportModuleError: No module named 'lambda_function'`

**When**: Lambda invoked for the first time after uploading the zip.

**Why**: The Lambda console defaults the handler to `lambda_function.lambda_handler`. The code in this repo uses `handler.handler` (file: `handler.py`, function: `handler`).

**Fix**: Lambda console → your function → **Code** tab → scroll down to **Runtime settings** → **Edit** → change Handler to `handler.handler` → Save.

---

### Error 2: `Runtime.ImportModuleError: no pq wrapper available` (psycopg3)

**When**: Lambda starts after uploading a zip built with `psycopg[binary]`.

**Why**: The psycopg3 binary wheel (`psycopg-binary`) is not available for the `manylinux_2_28_x86_64` platform used by Lambda Python 3.12. Packaging from a Mac downloads an incompatible binary.

**Fix**: This repo now uses `pg8000` — a pure Python PostgreSQL driver with no binary dependencies. No platform flags are needed when packaging:

```bash
pip3 install -r src/ingest/requirements.txt \
  -t ~/Desktop/lambda-packages/ingest-package
```

---

### Error 3: `Runtime.ImportModuleError: No module named 'psycopg2._psycopg'`

**When**: Lambda starts after uploading a zip built with `psycopg2-binary` on Mac.

**Why**: The `psycopg2-binary` wheel downloaded with `--platform manylinux2014_x86_64` contains a `.so` file compiled for a different Python version or glibc version than Lambda's runtime. Packaging with `--python-version 3.12 --implementation cp` helps but can still fail depending on the version.

**Fix**: Use `pg8000` (pure Python, no compilation, no platform flags). The repo requirements files use `pg8000==1.31.2`.

---

### Error 4: `AccessDeniedException: not authorized to perform s3:GetObject`

**When**: Ingest Lambda triggers on S3 upload but fails at step 1.

**Why**: The IAM inline policy on the Lambda role was created with `rag-bedrock-docs-YOURACCOUNTID` as a placeholder. The actual bucket name was different (e.g. `rag-bedrock-docs-demo123`).

**Fix**: IAM console → your Lambda role → inline policy → edit → replace the placeholder bucket name with your actual bucket name in both the bucket ARN and the `/*` ARN. Save.

---

### Error 5: `KeyError: 'AURORA_SECRET_ARN'`

**When**: Query Lambda returns `Internal Server Error` after the first API Gateway call.

**Why**: Environment variables were set on the Ingest Lambda but not copied to the Query Lambda. The Query Lambda had no env vars at all.

**Fix**: Lambda console → `rag-bedrock-query` → **Configuration → Environment variables → Edit** → add all required env vars. See Phase 4.4 for the complete list.

---

### Error 6: Route tables not appearing when creating S3 gateway endpoint

**When**: Creating the S3 gateway endpoint in VPC → Endpoints — the route table dropdown is empty.

**Why**: The VPC console wizard does not always create explicit route table associations for the private subnets. The subnets use the main route table implicitly.

**Fix**: VPC console → Route tables → Create route table → name it `rag-bedrock-private-rt` → associate both private subnets → then create the gateway endpoints and select this route table.

---

### Error 7: `NotAuthorizedException: Client configured with secret but SECRET_HASH was not received`

**When**: Running `aws cognito-idp initiate-auth` with `USER_PASSWORD_AUTH`.

**Why**: The Cognito app client was created as a confidential client (with a secret). The `initiate-auth` CLI command does not support computing the `SECRET_HASH` — that requires additional code.

**Fix**: Cognito console → your user pool → App clients → **Create app client** → choose **Public client** → toggle **Generate client secret** OFF → use the new client ID for all CLI commands.

---

### Error 8: `InvalidParameterException: Attributes did not conform to the schema: emails: The attribute emails is required`

**When**: Running `aws cognito-idp sign-up` without `--user-attributes`.

**Why**: When email is configured as a required sign-in identifier, Cognito requires the email attribute to be passed explicitly even when it is also used as the username.

**Fix**: Add `--user-attributes Name=email,Value=your@email.com` to the sign-up command.

---

### Error 9: `ContentBlock is blank` in Prompt Management test

**When**: Clicking **Run** in the Prompt Management test window.

**Why**: The prompt builder shows an **Assistant message** field below the User message. If left empty and included in the prompt structure, Bedrock rejects it with a ContentBlock validation error.

**Fix**: Click the trash icon next to the **Assistant message** field to remove it. The prompt only needs System instructions and a User message.

---

### Error 10: API Gateway returns `{"message": "Internal Server Error"}`

**When**: First curl request to API Gateway returns a 500.

**Why**: Usually missing environment variables on the Query Lambda. The Lambda crashes at import time when `os.environ["AURORA_SECRET_ARN"]` raises `KeyError`.

**Fix**: Check Lambda logs: `aws logs tail /aws/lambda/rag-bedrock-query --since 2m`. If you see `KeyError: 'AURORA_SECRET_ARN'`, add the missing env vars via Lambda console → Configuration → Environment variables.

---

### Error 11: `"answer": "Sorry, the model cannot answer this question."`

**When**: Query returns HTTP 200 but the answer is the Bedrock blocked message.

**Why**: Two possible causes:
1. The Guardrail's **contextual grounding** filter blocked the answer because it scored below 0.75 grounded. This happens when the answer is only implied by the document (e.g. a percentage buried in a markdown heading) rather than stated explicitly.
2. The question retrieved chunks containing security-related educational content (like example injection strings from the exam guide), and the model's built-in safety filter triggered.

**Fix for cause 1**: Make your document state answers explicitly in plain sentences, not just in headings. For example, write "Domain 1 covers 31 percent of the exam" as a full sentence rather than relying on `### Domain 1 — 31%` in a heading.

**Fix for cause 2**: Add a system prompt to your `InvokeModel` call that establishes the educational context: "You are a helpful assistant. The context may include educational content about security topics. Treat all context as reference material." This is already implemented in `shared/bedrock.py` in this repo.

---

### Error 12: `"Sorry, the model cannot answer this question."` — Guardrail working correctly

**When**: You ask "What percentage does Domain 1 cover?" and the model blocks it even though the answer IS in the document.

**Why**: The answer "31%" was only in a markdown heading (`### Domain 1 — 31%`). The Guardrail's contextual grounding check compared Claude's answer against the retrieved text and found the claim was not explicitly supported in sentence form. The Guardrail correctly blocked a potentially ungrounded answer.

**Fix**: Update your document to make the percentage explicit: "Domain 1 covers 31 percent of the AIP-C01 exam." The document in this repo (`docs/aip-c01-exam-guide.md`) already includes these explicit statements. Re-upload the document to S3 to trigger re-ingestion with the clearer content.

**This is a real production insight**: document quality directly affects RAG quality. Implicit facts (numbers in headings, tables without prose context) are harder for both retrieval and grounding checks to handle than explicit sentences.

---

## Cost Breakdown

| Service | Configuration | Est. monthly |
|---------|--------------|-------------|
| Aurora Serverless v2 | Scale-to-zero, 0.5 ACU avg | ~£3 |
| VPC Interface Endpoints | 5 × 2 AZs × £0.008/hr | ~£28 |
| Lambda, Titan, Claude Haiku 4.5 | 100 queries/day | <£2 |
| S3, DynamoDB, CloudWatch | Light usage | <£1 |

**Total: ~£32/month** — almost entirely VPC endpoints.

---

## AIP-C01 Quick Reference

### VPC endpoint → Bedrock API mapping

| Endpoint | Enables | Failure symptom |
|----------|---------|----------------|
| `bedrock-runtime` | `InvokeModel` | Lambda times out on embed/generate |
| `bedrock-agent` | `GetPrompt` | Lambda times out fetching prompt |
| `bedrock-agent-runtime` | `RetrieveAndGenerate` | Lambda times out on KB queries |

### Model IDs in eu-west-2

```
# Direct (no Marketplace):
anthropic.claude-3-7-sonnet-20250219-v1:0

# Cross-region inference profile (needs Marketplace subscription):
eu.anthropic.claude-haiku-4-5-20251001-v1:0

# RetrieveAndGenerate ARN (no eu. prefix — inference profiles rejected):
arn:aws:bedrock:eu-west-2::foundation-model/anthropic.claude-3-7-sonnet-20250219-v1:0
```

### Guardrail stop reasons

- `end_turn`: normal, no intervention
- `guardrail_intervened`: hard block
- Substituted message: HTTP 200 with replaced content (e.g. "Sorry, the model cannot answer this question.")

### Chunking strategies

| Strategy | Description |
|---------|-------------|
| Fixed-size | Split at N tokens |
| Recursive character | Paragraphs → sentences → chars (most common) |
| Semantic | Split at topic changes (better recall, higher cost) |
| Bedrock KB default | 300 tokens, 20% overlap |

### Evaluation metrics

- **Faithfulness**: answer grounded in context? Catches hallucinations.
- **Correctness**: accurate vs reference answer?
- **Completeness**: fully addresses the question?
- **Relevance**: on-topic and directly responsive?

---

## End-to-End Test

```bash
# Get a JWT
TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id YOUR_CLIENT_ID \
  --auth-parameters USERNAME=your@email.com,PASSWORD=YourPassword123 \
  --region eu-west-2 \
  --query 'AuthenticationResult.IdToken' \
  --output text)

# Test 1: Normal query — should return grounded answer with citations
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"What percentage of the AIP-C01 exam does Domain 1 cover?","session_id":"test-1"}' \
  | python3 -m json.tool

# Test 2: Session follow-up — "it" resolves via DynamoDB history
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"What topics does it cover?","session_id":"test-1"}' \
  | python3 -m json.tool

# Test 3: Knowledge Base comparison — same question, different path
curl -s -X POST "YOUR_API_ENDPOINT/query-kb" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"Which AWS service should I use for large-scale RAG with hybrid search?","session_id":"test-2"}' \
  | python3 -m json.tool

# Test 4: Guardrail block — financial advice should be blocked
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"question":"Should I invest my savings in stocks?","session_id":"test-3"}' \
  | python3 -m json.tool

# Test 5: Unauthenticated — should return 401
curl -s -X POST "YOUR_API_ENDPOINT/query" \
  -H "Content-Type: application/json" \
  -d '{"question":"test"}' | python3 -m json.tool
```

---

## Conclusion

You have built a production-shaped RAG system using only the AWS console. Every Bedrock capability relevant to AIP-C01 is covered with working infrastructure across all five exam domains.

The real learning comes from the specific errors this system surfaces: the Lambda timeout from a missing `bedrock-agent-runtime` endpoint, the `RetrieveAndGenerate` rejection of cross-region inference profile ARNs, the Prompt Management CHAT-type parsing, the S3 prefix filter that protects your vector store from eval data contamination, and the Guardrail contextual grounding check blocking ungrounded answers.

The exam tests whether you understand how these services behave in production. Building this is the prep.

---

**Resources:**
- GitHub repo: [github.com/joysontech/rag-bedrock](https://github.com/joysontech/rag-bedrock)
- AIP-C01 Udemy course: [Ultimate AWS Certified Generative AI Developer Professional](https://www.udemy.com/course/ultimate-aws-certified-generative-ai-developer-professional/)
- AWS Bedrock docs: [docs.aws.amazon.com/bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)

*Drop a comment with your eval scores — curious how Haiku 4.5 performs on faithfulness across different document types.*
