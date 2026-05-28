# ----------------------------------------------------------------------
# Account identity for deterministic, globally-unique bucket naming
# ----------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ----------------------------------------------------------------------
# S3 bucket for source documents
# ----------------------------------------------------------------------
resource "aws_s3_bucket" "docs" {
  bucket        = "${var.project}-docs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # dev project: allow destroy even with objects present
  tags          = { Name = "${var.project}-docs" }
}

resource "aws_s3_bucket_versioning" "docs" {
  bucket = aws_s3_bucket.docs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket                  = aws_s3_bucket.docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------------------
# DynamoDB table for chat sessions
# ----------------------------------------------------------------------
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = { Name = "${var.project}-sessions" }
}

# ----------------------------------------------------------------------
# IAM execution role
# ----------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-lambda-role" }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:ApplyGuardrail",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecretsRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [var.aurora_secret_arn]
  }

  statement {
    sid    = "KmsDecryptViaServices"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${var.region}.amazonaws.com",
        "rds.${var.region}.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "S3DocsAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.docs.arn,
      "${aws_s3_bucket.docs.arn}/*",
    ]
  }

  statement {
    sid    = "DynamoSessions"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.sessions.arn]
  }
}

resource "aws_iam_policy" "lambda" {
  name   = "${var.project}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# ----------------------------------------------------------------------
# Log groups (explicit, with retention)
# ----------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${var.project}-ingest"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project}-ingest-logs" }
}

resource "aws_cloudwatch_log_group" "query" {
  name              = "/aws/lambda/${var.project}-query"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project}-query-logs" }
}

# ----------------------------------------------------------------------
# Lambda functions
# ----------------------------------------------------------------------
locals {
  common_env = {
    AURORA_SECRET_ARN  = var.aurora_secret_arn
    AURORA_ENDPOINT    = var.aurora_endpoint
    AURORA_DATABASE    = var.aurora_database_name
    SESSIONS_TABLE     = aws_dynamodb_table.sessions.name
    DOCS_BUCKET        = aws_s3_bucket.docs.id
    BEDROCK_REGION     = var.region
    EMBEDDING_MODEL_ID = "amazon.titan-embed-text-v2:0"
    # Claude 3.5 Haiku: fast, cheap, no Marketplace subscription required
    GENERATION_MODEL_ID = "anthropic.claude-3-5-haiku-20241022-v1:0"
    LOG_LEVEL           = "INFO"
  }
}

resource "aws_lambda_function" "ingest" {
  function_name = "${var.project}-ingest"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  filename         = "${path.root}/../dist/ingest.zip"
  source_code_hash = filebase64sha256("${path.root}/../dist/ingest.zip")

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = local.common_env
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy_attachment.lambda_custom,
    aws_cloudwatch_log_group.ingest,
  ]

  tags = { Name = "${var.project}-ingest" }
}

resource "aws_lambda_function" "query" {
  function_name = "${var.project}-query"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = var.lambda_runtime
  memory_size   = var.lambda_memory
  timeout       = var.lambda_timeout

  filename         = "${path.root}/../dist/query.zip"
  source_code_hash = filebase64sha256("${path.root}/../dist/query.zip")

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = local.common_env
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy_attachment.lambda_custom,
    aws_cloudwatch_log_group.query,
  ]

  tags = { Name = "${var.project}-query" }
}

# ----------------------------------------------------------------------
# S3 -> Lambda event notification
# ----------------------------------------------------------------------
resource "aws_lambda_permission" "s3_invoke_ingest" {
  statement_id  = "AllowS3InvokeIngest"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.docs.arn
}

resource "aws_s3_bucket_notification" "docs" {
  bucket = aws_s3_bucket.docs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingest.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_ingest]
}
