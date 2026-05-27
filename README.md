# rag-bedrock

Production-shaped RAG system on AWS Bedrock, built from scratch with Terraform.

## Architecture

- **Bedrock**: Claude Haiku 4.5 for generation, Titan Text Embeddings V2 for embeddings
- **Aurora Serverless v2 (PostgreSQL 16)**: pgvector for vector storage, scale-to-zero with 5-minute auto-pause
- **Lambda (Python 3.12)**: ingest and query functions deployed in private VPC subnets
- **DynamoDB**: chat session history with TTL
- **S3**: source document storage with event-driven ingestion
- **VPC endpoints**: bedrock-runtime, secretsmanager, logs (interface), S3, DynamoDB (gateway). No NAT Gateway.
- **Encryption**: AWS-managed KMS keys (alias/aws/rds, aws/secretsmanager)

## Quick start

Requires AWS credentials, Terraform 1.10+, Python 3.12, Make.

```bash
# Update the bucket name in terraform/backend.tf to your S3 state bucket
make init
make package
make plan
make apply
```

## Common workflows

```bash
make plan          # see what would change
make apply         # apply approved plan
make pause         # snapshot Aurora, then destroy everything (saves cost between sessions)
make resume        # instructions for restoring from snapshot
make costs         # last 7 days of spend by service
make destroy       # tear down without snapshotting
make nuke          # destroy + list any orphaned tagged resources
```

## Project status

- [x] Backend (S3 + native locking)
- [x] Networking module (VPC, subnets, security groups, VPC endpoints)
- [x] Database module (Aurora Serverless v2 with pgvector, Data API, AWS-managed KMS)
- [x] Lambda module (ingest + query stubs, IAM, S3 trigger, DynamoDB sessions)
- [ ] Real handler code with RAG logic (Step 7b)
- [ ] Bedrock Guardrails
- [ ] Bedrock Prompt Management
- [ ] API Gateway + Cognito
- [ ] Bedrock Knowledge Bases comparison
- [ ] Bedrock AgentCore

## Notes

- Built as study and portfolio for the AWS Certified Generative AI Developer (AIP-C01) certification.
- Region: eu-west-2 (London).
- Tear down between work sessions: `make pause`, then `make resume` next time.
- Build log lives in [BUILD_LOG.md](./BUILD_LOG.md).
