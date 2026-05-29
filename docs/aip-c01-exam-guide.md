# AWS Certified Generative AI Developer Professional (AIP-C01)
## Complete Exam Guide

The AWS Certified Generative AI Developer Professional (AIP-C01) validates your ability to design, build, deploy, and maintain generative AI applications using AWS services. It is a professional-level certification targeting developers and engineers who work with foundation models, RAG pipelines, Bedrock services, and AI safety controls on AWS.

---

## Exam Overview

- **Exam code**: AIP-C01
- **Level**: Professional
- **Duration**: 170 minutes
- **Questions**: 85 questions (multiple choice and multiple response)
- **Passing score**: 720 out of 1000
- **Cost**: $300 USD
- **Languages**: English, Japanese, Korean, Simplified Chinese
- **Delivery**: Pearson VUE testing centre or online proctored

The exam is designed for developers who have hands-on experience building AI and generative AI applications on AWS. Candidates are expected to understand foundation model selection, RAG architecture, prompt engineering, responsible AI, and operational best practices.

---

## Exam Domains and Weightings

### Domain 1: Foundation Model Integration and Data Management — 31%

This is the highest-weighted domain and focuses on how you select, configure, and integrate foundation models with data sources.

**Key topics:**
- Selecting the right foundation model for a task based on modality (text, image, multimodal), context window size, latency requirements, and cost
- Embedding models: Titan Embeddings V2, dimensions (256, 512, 1024), normalisation, input types (search_document vs search_query)
- Vector databases: pgvector (PostgreSQL), OpenSearch Serverless, Amazon MemoryDB, Aurora with pgvector
- Vector index types: flat (exact), IVFFlat (approximate, large datasets), HNSW (approximate, best recall/speed tradeoff)
- Chunking strategies: fixed-size, recursive character, semantic, Bedrock default (300 tokens, 20% overlap)
- RAG architecture: ingestion pipeline (chunk → embed → index) and query pipeline (embed → retrieve → generate)
- Amazon Bedrock Knowledge Bases: S3 data sources, managed ingestion, vector store options (OpenSearch, Aurora, S3 Vectors, MemoryDB, Neptune)
- Retrieve vs RetrieveAndGenerate APIs: when to use each, trade-offs
- Cross-region inference profiles: eu./us. prefix model IDs, Marketplace subscription requirements, latency routing
- Bedrock model IDs: direct foundation model ARNs vs cross-region inference profile IDs (RetrieveAndGenerate rejects inference profiles)
- Fine-tuning vs RAG: when to fine-tune (style, domain vocabulary, classification) vs when to use RAG (current information, large corpus, auditability)

**Critical exam gotchas:**
- The `RetrieveAndGenerate` API requires a direct foundation model ARN, not a cross-region inference profile ID. The model ARN format is `arn:aws:bedrock:REGION::foundation-model/MODEL_ID`.
- pgvector cosine distance operator is `<=>`. For normalised embeddings, cosine distance equals 1 minus cosine similarity.
- Bedrock Knowledge Bases default chunking is 300 tokens with 20% overlap. You cannot change the chunking strategy after creating a data source.

---

### Domain 2: GenAI Application Implementation and Integration — 26%

Covers the application layer: orchestration, prompt engineering, session management, and API integration.

**Key topics:**
- Prompt engineering techniques: zero-shot, few-shot, chain-of-thought, role prompting, instruction tuning
- Bedrock Prompt Management: creating versioned prompt templates, variable substitution with `{{double_braces}}` syntax, CHAT vs TEXT template types, `GetPrompt` API via `bedrock-agent` service
- Bedrock Agents: multi-step task automation, action groups, knowledge base integration, session attributes
- LangChain and LlamaIndex integration patterns with Bedrock
- Session history management: DynamoDB for conversation turns, TTL-based expiry, sort key patterns for efficient history queries
- API Gateway + Lambda patterns: HTTP API vs REST API (HTTP API for JWT auth, REST API for API keys and WAF), payload format 2.0
- Cognito integration: User Pools (authentication, tokens) vs Identity Pools (AWS credential exchange), JWT authoriser configuration
- Inference parameters: temperature (0=deterministic, 1=creative), top_p, top_k, max_tokens, stop sequences
- Streaming responses: InvokeModelWithResponseStream for real-time token delivery

**Critical exam gotchas:**
- The Bedrock console Prompt Management builder creates CHAT-type prompts (with system instructions + message turns), not TEXT-type. Your code must parse `templateConfiguration.chat.messages` not `templateConfiguration.text`.
- API Gateway HTTP API costs ~70% less than REST API and supports native JWT authorisation with Cognito. Use HTTP API for Lambda backends unless you specifically need REST API features (WAF, API keys, request transformation).
- An empty variable in a Prompt Management template causes a ContentBlock validation error. Remove unused variables or ensure all variables have values at invocation time.

---

### Domain 3: AI Safety, Security and Governance — 20%

Covers responsible AI, security controls, and compliance mechanisms.

**Key topics:**
- Bedrock Guardrails: content filters (Hate, Insults, Sexual, Violence, Misconduct, Prompt Attack), denied topics, sensitive information filters (PII masking vs blocking), contextual grounding checks
- Guardrail intervention modes: hard block (`stop_reason = "guardrail_intervened"`) vs message substitution (HTTP 200 with replaced content)
- Contextual grounding threshold: 0 to 1, where higher means stricter checking. 0.75 is a common production value.
- Prompt injection attacks: indirect prompt injection (via document content), direct prompt injection (via user input). Prompt Attack filter set to High detects both.
- PII types: email, phone (mask), credit card, National Insurance, SSN (block)
- IAM least-privilege for Bedrock: `bedrock:InvokeModel`, `bedrock:GetPrompt`, `bedrock:Retrieve`, `bedrock:RetrieveAndGenerate`, `bedrock:ApplyGuardrail`
- VPC endpoints for Bedrock: `bedrock-runtime` (InvokeModel), `bedrock-agent` (GetPrompt), `bedrock-agent-runtime` (RetrieveAndGenerate/Retrieve)
- Encryption: AWS-managed KMS keys vs customer-managed KMS keys, KMS key policy requirements for Bedrock
- Model access and Marketplace subscriptions: newer models require `aws-marketplace:Subscribe` by the invoking principal
- Service Control Policies (SCPs) for restricting model access at the organisation level
- AWS AI Service Cards and responsible AI principles

**Critical exam gotchas:**
- A Lambda in a private VPC cannot call Knowledge Bases without a `bedrock-agent-runtime` VPC endpoint. Without it, the Lambda call silently hangs for the full timeout duration.
- Customer-managed KMS keys used with Aurora go into PendingDeletion (7-30 days minimum) on deletion, making automated snapshots unrestorable. Use AWS-managed keys (`alias/aws/rds`) for development clusters.
- Guardrail contextual grounding checks the answer against the retrieved context, not against ground truth. It catches hallucination (answer not supported by context) but not factual errors (answer in context is wrong).

---

### Domain 4: Operational Excellence and Efficiency — 12%

Covers cost optimisation, performance, scaling, and model lifecycle management.

**Key topics:**
- Provisioned throughput vs on-demand throughput: on-demand for variable workloads, provisioned for consistent high-volume workloads
- Aurora Serverless v2 scale-to-zero: requires PostgreSQL 15.5+ or 16.1+, min_capacity=0, auto-pause after configurable idle period. First query after scale-to-zero takes 10-20 seconds (cold start).
- Lambda cost optimisation: memory allocation affects CPU allocation, right-sizing for RAG workloads (1024 MB balances cost and cold start time)
- Bedrock model cost comparison: Haiku (cheapest) → Sonnet → Opus. Embedding models cheaper than generation models.
- Cross-region inference profiles: route to least-loaded region, higher availability at slightly higher latency
- Caching strategies: prompt caching, semantic caching (cache similar questions), `@lru_cache` for prompt template fetching in Lambda
- CloudWatch metrics for Bedrock: InvocationLatency, InputTokenCount, OutputTokenCount, ThrottledRequests
- Bedrock model evaluation for cost optimisation: comparing cheaper models against reference responses before production deployment

**Critical exam gotchas:**
- Aurora Serverless v2 with `min_capacity=0` scales to zero but has a cold start penalty. For latency-sensitive RAG, set `min_capacity=0.5` ACU to keep the cluster warm.
- Lambda SG in a private VPC needs outbound HTTPS to `0.0.0.0/0` even with S3 and DynamoDB gateway endpoints configured. Gateway endpoints use route table rules but the SG still needs the outbound rule matching the public IP ranges.

---

### Domain 5: Testing, Validation and Troubleshooting — 11%

Covers evaluation frameworks, quality measurement, and debugging AI systems.

**Key topics:**
- Bedrock Model Evaluation: automated (programmatic metrics), automatic (LLM-as-judge), human (bring your own workforce)
- Automatic vs Programmatic evaluation: programmatic uses ROUGE/BERTScore (string matching, best for translation), LLM-as-judge uses a stronger model to evaluate quality (better for open-ended Q&A)
- LLM-as-judge pattern: judge model should be stronger than evaluated model (e.g. Sonnet judges Haiku). Judge scores against a reference response.
- RAG evaluation metrics:
  - **Faithfulness**: is the answer grounded in the retrieved context? Detects hallucination.
  - **Correctness**: is the answer factually accurate vs a reference answer?
  - **Completeness**: does the answer fully address the question?
  - **Relevance**: is the answer on-topic and directly responsive?
- Evaluation dataset format for Bedrock: JSONL with `prompt`, `referenceResponse`, and `category` fields
- Human evaluation: when to use (subjective quality, tone, cultural sensitivity), workforce types (internal, Mechanical Turk, vendor)
- A/B testing prompts using Prompt Management version comparison
- Debugging RAG: checking retrieval quality (similarity scores), chunk size tuning, embedding model selection, index type selection

**Critical exam gotchas:**
- ROUGE and BERTScore are string-matching metrics. They penalise semantically correct answers with different wording. Use LLM-as-judge for Q&A evaluation.
- Bedrock Evaluations results are stored in S3. The eval JSONL output contains per-question scores. Watch out: if your eval dataset lives in the same S3 bucket as your docs, the S3 event notification can trigger your Ingest Lambda, contaminating your vector store with eval data. Use separate S3 prefixes and event notification filters.

---

## Key AWS Services for AIP-C01

| Service | Exam relevance |
|---------|---------------|
| Amazon Bedrock | Core service — foundation models, Guardrails, Prompt Management, Knowledge Bases, Agents, Evaluations |
| Amazon Aurora (pgvector) | Vector store for DIY RAG, Serverless v2 scale-to-zero |
| Amazon OpenSearch Serverless | Vector store for large-scale RAG, hybrid search (vector + keyword) |
| Amazon S3 | Document storage, Knowledge Base data source, eval datasets |
| Amazon Lambda | RAG orchestration, embedding, retrieval, generation |
| Amazon API Gateway | HTTP API with JWT auth, REST API with API keys |
| Amazon Cognito | User Pool (auth tokens), Identity Pool (AWS credentials) |
| Amazon DynamoDB | Session history, on-demand pricing, TTL |
| AWS Secrets Manager | Credential management, auto-rotation |
| Amazon CloudWatch | Metrics, logs, alarms for AI systems |
| AWS IAM | Least-privilege policies, service roles, KMS conditions |
| Amazon VPC | Private subnets, VPC endpoints (PrivateLink) |
| Amazon SageMaker | Custom model training, fine-tuning, endpoints |

---

## Bedrock Foundation Model Quick Reference

| Model | Use case | Key property |
|-------|---------|-------------|
| Claude Haiku 4.5 | Fast, cheap generation | Requires EU inference profile in eu-west-2 |
| Claude Sonnet 4.6 | Balanced quality/cost | Works directly, no inference profile needed |
| Claude 3.7 Sonnet | Strong reasoning | Hybrid reasoning mode available |
| Titan Embeddings V2 | Text embeddings | 256/512/1024 dims, normalise flag |
| Titan Multimodal Embeddings | Image + text | 384/1024 dims, image similarity |
| Llama 3 (70B/8B) | Open weights | Fine-tunable on Bedrock |
| Mistral | European data residency | Available in EU regions |
| Stable Diffusion | Image generation | Text-to-image, not Q&A |

---

## Top Exam Scenarios

**Scenario: Lambda in private subnet cannot reach Bedrock**
Answer: Missing VPC interface endpoint. Check which API is failing: `bedrock-runtime` for InvokeModel, `bedrock-agent` for GetPrompt, `bedrock-agent-runtime` for RetrieveAndGenerate.

**Scenario: RAG system returns hallucinated answers not in the documents**
Answer: Enable Bedrock Guardrails with contextual grounding filter (threshold 0.75+). This checks whether the generated answer is supported by the retrieved context.

**Scenario: You need to update the system prompt without redeploying Lambda**
Answer: Use Bedrock Prompt Management. Store the prompt as a versioned template. Lambda fetches it via GetPrompt API and caches it. Update by creating a new version and changing the environment variable.

**Scenario: A user asks the RAG system about competitor products**
Answer: Add a denied topic in Bedrock Guardrails defining the topic and example phrases. The Guardrail will block or substitute responses matching the denied topic.

**Scenario: Choose between RAG and fine-tuning for a customer support use case**
Answer: RAG for frequently updated knowledge bases (current product information, policies). Fine-tuning for style consistency, domain-specific terminology, or classification tasks where the training data is static.

**Scenario: RetrieveAndGenerate API returns a ValidationException**
Answer: The model ARN uses a cross-region inference profile ID (eu.anthropic.* prefix). RetrieveAndGenerate only accepts direct foundation model ARNs. Remove the regional prefix.

**Scenario: Compare Knowledge Bases with DIY RAG**
Answer: Knowledge Bases offer managed ingestion, zero infrastructure, and built-in sync but no session history, no similarity scores, no inline citations, and limited model choice. DIY RAG gives full observability (scores, chunks, prompt versioning) and model flexibility at the cost of higher setup complexity.

---

## Study Tips

1. **Build it, don't just read it**: spin up a Bedrock Knowledge Base, a Guardrail, and a Prompt Management template in the console. The exam tests operational knowledge, not documentation recall.

2. **Know the VPC endpoint mapping cold**: which service name enables which API. This appears in multiple scenario questions.

3. **Understand inference profiles**: know the difference between `eu.anthropic.claude-haiku-4-5-20251001-v1:0` (cross-region profile) and `anthropic.claude-haiku-4-5-20251001-v1:0` (direct). Know which APIs accept each.

4. **Distinguish RAG vs fine-tuning**: the exam frequently asks you to choose between them. RAG for current/large/auditable knowledge, fine-tuning for style/vocabulary/classification.

5. **Guardrail thresholds**: understand that contextual grounding threshold closer to 1 means stricter. A threshold of 0.75 means answers less than 75% supported by the retrieved context are blocked.

6. **Evaluation metrics**: know the four RAG metrics (faithfulness, correctness, completeness, relevance) and when to use LLM-as-judge vs programmatic metrics.

7. **Cost model**: Haiku < Sonnet < Opus for generation cost. On-demand < provisioned for variable workloads. Scale-to-zero Aurora for dev builds.

---

## Recommended Study Resources

- AWS Bedrock documentation: https://docs.aws.amazon.com/bedrock/latest/userguide/
- AWS Bedrock service quotas and limits: check which models are available per region
- Udemy course: Ultimate AWS Certified Generative AI Developer Professional — hands-on labs covering all five domains
- AWS Skill Builder: official practice exams and sample questions
- Build a real RAG system: the best preparation is deploying Guardrails, Prompt Management, Knowledge Bases, and Evaluations yourself
