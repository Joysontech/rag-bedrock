output "api_endpoint" {
  value       = aws_apigatewayv2_stage.default.invoke_url
  description = "HTTPS endpoint for the API"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "user_pool_endpoint" {
  value = aws_cognito_user_pool.main.endpoint
}
