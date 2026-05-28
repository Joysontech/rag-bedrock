## Day 1: Terraform backend bootstrap
- Created bucket: joysontech-tf-state-e3ca4053 (eu-west-2)
- Versioning: enabled
- Encryption: AES256 with bucket key
- Public access: blocked
- Lifecycle: noncurrent versions expire after 90 days
- State key: rag-bedrock/terraform.tfstate
- Locking: S3 native (Terraform 1.10+ use_lockfile)
- This bucket is NOT managed by Terraform; it is the chicken before the egg.

## Day 2: Networking module
- VPC: 10.42.0.0/16 (2 private subnets, no public, no NAT, no IGW)
- Gateway endpoints: S3, DynamoDB
- Interface endpoints: bedrock-runtime, secretsmanager, logs
- Lambda SG: egress only to Aurora SG (5432) and endpoints SG (443)
- Aurora SG: ingress from Lambda SG only
- Endpoints SG: ingress 443 from VPC CIDR
- Cost estimate: ~£30-35/month if left running 24/7; ~£3-5/month with regular teardown
- Module under terraform/modules/networking/

## Day 1-2: Database module
- Aurora Serverless v2 PostgreSQL 16.4
- Min 0.5 ACU, max 2 ACU (region doesn't support 0 yet at apply time)
- KMS-encrypted storage + KMS-encrypted master secret
- Master password auto-managed by Secrets Manager (no manual passwords)
- VPC: deployed into networking module's private subnets
- Security group: aurora-sg (ingress from lambda-sg only)
- Parameter group: rds.force_ssl=1, pg_stat_statements preloaded
- Backup retention: 1 day (learning project)
- Schema bootstrapped via RDS Query Editor (console, one-off)
- pgvector version: 0.7.x (capture exact version on next connect)
- TODO: move schema bootstrap into a null_resource with local-exec via psql in week 4
- TODO: add `make pause` / `make resume` targets for snapshot-and-destroy

## Day 2: Data API enable (Terraform fix)
- Added enable_http_endpoint = true to aws_rds_cluster.aurora
- Required for RDS Query Editor to work
- No cost impact, no downtime
- TIL: not enabled by default in Terraform; AWS console-created clusters are also off by default


## Day 4: Step 7a complete - infrastructure live
- Full fresh build after the KMS migration cleanup
- 35 resources created from empty state: VPC, endpoints, Aurora pgvector, Lambdas, S3, DynamoDB
- pgvector + documents/source_files tables bootstrapped via RDS Query Editor
- Lambda stubs respond correctly to direct invoke (ingest + query)
- S3 -> ingest Lambda event trigger confirmed working end-to-end
- Cold start 139ms, warm invokes 2-3ms, 36MB of 1024MB used
- Logs flowing to CloudWatch with 7-day retention
- Next: Step 7b - replace stubs with real RAG code

## Day 4-5: Step 7b complete - real RAG handlers
- Ingest: S3 trigger, Titan embed, pgvector upsert (idempotent per source)
- Query: vector search top-5, DynamoDB session history, Claude Haiku 4.5 generation
- Model: eu.anthropic.claude-haiku-4-5-20251001-v1:0 (EU inference profile)
- Embedding: amazon.titan-embed-text-v2:0 (1024 dims)
- Fixes: Lambda SG egress for gateway endpoints, Aurora retry loop,
  Marketplace permissions on IAM user Joyson
- Cost per query: ~$0.0009 (Haiku 4.5 + Titan)
- Both queries confirmed grounded, cited, correct
- Session history (DynamoDB) confirmed working via context-dependent question

## Day 5: Phase 3 - Bedrock Guardrails live
- Guardrail ID: hy14n4r45o6f, Version 1
- Content filters: all Medium, Prompt Attack High
- Denied topic: personal financial advice
- PII: Email/Phone masked, CC/NI blocked
- Grounding: 0.75, Relevance: 0.75
- Wired into query Lambda via GUARDRAIL_ID + GUARDRAIL_VERSION env vars
- Normal queries pass through unaffected
- Denied topic (stocks) blocked with message substitution
- Prompt injection ("ignore all previous instructions") blocked
- ManagedBy: console (Terraform import planned for Phase 6 cleanup)

## Day 5: Phase 4 complete - Bedrock Prompt Management wired
- Prompt: rag-query-generate (ID: JRKRWLNLD2, Version 1)
- VPC endpoint added for bedrock-agent (GetPrompt API)
- Template type: CHAT (console builder format), handled in prompts.py
- prompt_arn returned in every response for auditability
- Template cached via lru_cache, zero extra latency on warm invocations
- Quality improvement: structured markdown answers from system instructions
- To roll out new prompt version: edit console, create v2, bump PROMPT_ARN :1 -> :2, apply
