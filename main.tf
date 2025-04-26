terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket for storing verification documents and images
resource "aws_s3_bucket" "verification_assets" {
  bucket = "${var.app_name}-verification-assets-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "verification_assets" {
  bucket = aws_s3_bucket.verification_assets.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.app_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda functions
resource "aws_iam_policy" "lambda_execution_policy" {
  name = "${var.app_name}-lambda-execution-policy"
  description = "Policy for identity verification Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        Action = [
          "rekognition:CompareFaces",
          "rekognition:DetectText",
          "rekognition:DetectDocumentText"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = "${aws_s3_bucket.verification_assets.arn}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = aws_dynamodb_table.verification_results.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_execution" {
  role = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

# Lambda Functions
resource "aws_lambda_function" "face_verification" {
  filename = "${path.module}/lambda/face-verification/package.zip"
  function_name = "${var.app_name}-face-verification"
  role = aws_iam_role.lambda_execution_role.arn
  handler = "app.lambda_handler"
  runtime = "python3.9"
  timeout = 30
  memory_size = 512

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.verification_assets.bucket
      DYNAMODB_TABLE = aws_dynamodb_table.verification_results.name
      SIMILARITY_THRESHOLD = "90"
    }
  }
}

resource "aws_lambda_function" "document_verification" {
  filename = "${path.module}/lambda/document-verification/package.zip"
  function_name = "${var.app_name}-document-verification"
  role = aws_iam_role.lambda_execution_role.arn
  handler = "app.lambda_handler"
  runtime = "python3.9"
  timeout = 30
  memory_size = 512

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.verification_assets.bucket
      DYNAMODB_TABLE = aws_dynamodb_table.verification_results.name
    }
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "verification_api" {
  name = "${var.app_name}-verification-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "face_verification_integration" {
  api_id = aws_apigatewayv2_api.verification_api.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.face_verification.invoke_arn
}

resource "aws_apigatewayv2_integration" "document_verification_integration" {
  api_id = aws_apigatewayv2_api.verification_api.id
  integration_type = "AWS_PROXY"
  integration_uri = aws_lambda_function.document_verification.invoke_arn
}

resource "aws_apigatewayv2_route" "face_verification_route" {
  api_id = aws_apigatewayv2_api.verification_api.id
  route_key = "POST /verify/face"
  target = "integrations/${aws_apigatewayv2_integration.face_verification_integration.id}"
}

resource "aws_apigatewayv2_route" "document_verification_route" {
  api_id = aws_apigatewayv2_api.verification_api.id
  route_key = "POST /verify/document"
  target = "integrations/${aws_apigatewayv2_integration.document_verification_integration.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id = aws_apigatewayv2_api.verification_api.id
  name = "prod"
  auto_deploy = true
}

# Lambda Permissions
resource "aws_lambda_permission" "api_gw_face_verification" {
  statement_id = "AllowExecutionFromAPIGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.face_verification.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.verification_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_document_verification" {
  statement_id = "AllowExecutionFromAPIGateway"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_verification.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.verification_api.execution_arn}/*/*"
}

# DynamoDB for verification results
resource "aws_dynamodb_table" "verification_results" {
  name = "${var.app_name}-verification-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "userId"
  range_key = "verificationId"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "verificationId"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name = "StatusIndex"
    hash_key = "status"
    projection_type = "ALL"
    write_capacity = 5
    read_capacity = 5
  }
}

# AWS Amplify App
resource "aws_amplify_app" "identity_verification" {
  name = var.app_name
  repository = var.frontend_repository
  oauth_token = var.github_token

  # The default build_spec added by Amplify. Can be overridden with custom buildspec.yml
  build_spec = file("${path.module}/amplify/buildspec.yml")

  # The default rewrites and redirects added by the Amplify Console.
  custom_rule {
    source = "/<*>"
    status = "404"
    target = "/index.html"
  }

  environment_variables = {
    API_ENDPOINT = aws_apigatewayv2_api.verification_api.api_endpoint
    REGION = var.aws_region
  }
}

resource "aws_amplify_branch" "main" {
  app_id = aws_amplify_app.identity_verification.id
  branch_name = "main"
  framework = "React"
  stage = "PRODUCTION"
}

# Cognito User Pool for authentication
resource "aws_cognito_user_pool" "users" {
  name = "${var.app_name}-users"

  username_attributes = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length = 8
    require_lowercase = true
    require_numbers = true
    require_symbols = true
    require_uppercase = true
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject = "Your Verification Code"
    email_message = "Your verification code is {####}"
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name = "${var.app_name}-client"

  user_pool_id = aws_cognito_user_pool.users.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  callback_urls = ["https://${aws_amplify_app.identity_verification.default_domain}"]
  logout_urls = ["https://${aws_amplify_app.identity_verification.default_domain}"]
  allowed_oauth_flows = ["code", "implicit"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  supported_identity_providers = ["COGNITO"]
}