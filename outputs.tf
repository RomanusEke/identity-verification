output "amplify_app_url" {
  value = "https://main.${aws_amplify_app.identity_verification.default_domain}"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.verification_api.api_endpoint
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.users.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.verification_assets.bucket
}