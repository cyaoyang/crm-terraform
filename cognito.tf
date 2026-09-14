resource "aws_cognito_user_pool" "crm_users" {
  name = "crm-officer-pool"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = true
  }

  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  # Custom attributes to distinguish internal officers from external
  # law firm users, and scope law firm users to their own firm only.
  # NOTE: Cognito schema is immutable after pool creation - any future
  # change to these attributes requires recreating the pool.
  schema {
    name                     = "role"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints {
      min_length = 1
      max_length = 32
    }
  }

  schema {
    name                     = "law_firm_id"
    attribute_data_type      = "String"
    mutable                  = true
    developer_only_attribute = false
    string_attribute_constraints {
      min_length = 0
      max_length = 64
    }
  }

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_cognito_user_pool_client" "crm_app_client" {
  name         = "crm-frontend-client"
  user_pool_id = aws_cognito_user_pool.crm_users.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  generate_secret = false

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.crm_users.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.crm_app_client.id
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.crm_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "crm-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.crm_app_client.id]
    issuer   = "https://cognito-idp.ap-southeast-1.amazonaws.com/${aws_cognito_user_pool.crm_users.id}"
  }
}