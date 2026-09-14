data "archive_file" "get_customer_detail_zip" {
  type        = "zip"
  source_file = "${path.module}/get_customer_detail.py"
  output_path = "${path.module}/get_customer_detail.zip"
}

resource "aws_iam_role" "get_customer_detail_role" {
  name = "crm-get-customer-detail-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_iam_role_policy" "get_customer_detail_policy" {
  name = "crm-get-customer-detail-policy"
  role = aws_iam_role.get_customer_detail_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowVPCNetworkInterfaceForRDSAccess"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowOwnLogGroupOnly"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-get-customer-detail:*"
      }
    ]
  })
}

resource "aws_lambda_function" "get_customer_detail" {
  function_name = "crm-get-customer-detail"
  role          = aws_iam_role.get_customer_detail_role.arn
  handler       = "get_customer_detail.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.get_customer_detail_zip.output_path
  source_code_hash = data.archive_file.get_customer_detail_zip.output_base64sha256

  layers = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME     = "crmdb"
      DB_USER     = "crmadmin"
      DB_PASSWORD = random_password.rds_master_password.result
    }
  }

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_apigatewayv2_integration" "get_customer_detail_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_customer_detail.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_customer_detail_route" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /customers/{customer_id}"
  target             = "integrations/${aws_apigatewayv2_integration.get_customer_detail_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_permission" "allow_apigw_get_customer_detail" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_customer_detail.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}