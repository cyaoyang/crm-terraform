resource "aws_apigatewayv2_api" "crm_api" {
  name          = "crm-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
  }

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_apigatewayv2_stage" "crm_api_stage" {
  api_id      = aws_apigatewayv2_api.crm_api.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_apigatewayv2_integration" "list_accounts_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_accounts.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_accounts" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /accounts"
  target             = "integrations/${aws_apigatewayv2_integration.list_accounts_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_permission" "allow_apigw_list_accounts" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_accounts.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "log_call_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.log_call.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_calls" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "POST /calls"
  target             = "integrations/${aws_apigatewayv2_integration.log_call_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_permission" "allow_apigw_log_call" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_call.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

output "api_base_url" {
  value       = aws_apigatewayv2_api.crm_api.api_endpoint
  description = "Base URL for the CRM API"
}