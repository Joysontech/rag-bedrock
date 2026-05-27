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

