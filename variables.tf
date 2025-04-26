variable "aws_region" {
  description = "AWS region to deploy resources"
  type = string
  default = "us-east-1"
}

variable "app_name" {
  description = "Name of the application"
  type = string
  default = "identity-verification"
}

variable "frontend_repository" {
  description = "Git repository URL for the frontend application"
  type = string
}

variable "github_token" {
  description = "GitHub OAuth token for Amplify to access the repository"
  type = string
  sensitive = true
}