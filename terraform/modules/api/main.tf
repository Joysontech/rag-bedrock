# ----------------------------------------------------------------------
# Cognito User Pool
# ----------------------------------------------------------------------
resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-users"

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  tags = { Name = "${var.project}-users" }
}

# App client for API auth (USER_PASSWORD_AUTH for easy testing)
resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.project}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 60   # minutes
  id_token_validity      = 60
  refresh_token_validity = 30   # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}

# ----------------------------------------------------------------------
# API Gateway HTTP API
# ----------------------------------------------------------------------
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }

  tags = { Name = "${var.project}-api" }
}

# CloudWatch log group for API access logs
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.project}-api"
  retention_in_days = 7
  tags              = { Name = "${var.project}-api-logs" }
}

# Stage with auto-deploy and access logging
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
  }

  tags = { Name = "${var.project}-api-stage" }
}

# JWT Authorizer backed by Cognito
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# ----------------------------------------------------------------------
# Integrations
# ----------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "query" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.query_function_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "ingest" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.ingest_function_arn
  payload_format_version = "2.0"
}

# ----------------------------------------------------------------------
# Routes (JWT-protected)
# ----------------------------------------------------------------------
resource "aws_apigatewayv2_route" "query" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /query"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.query.id}"
}

resource "aws_apigatewayv2_route" "ingest" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /ingest"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.ingest.id}"
}

# ----------------------------------------------------------------------
# Lambda permissions (allow API GW to invoke)
# ----------------------------------------------------------------------
resource "aws_lambda_permission" "apigw_query" {
  statement_id  = "AllowAPIGWInvokeQuery"
  action        = "lambda:InvokeFunction"
  function_name = var.query_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/query"
}

resource "aws_lambda_permission" "apigw_ingest" {
  statement_id  = "AllowAPIGWInvokeIngest"
  action        = "lambda:InvokeFunction"
  function_name = var.ingest_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/ingest"
}
