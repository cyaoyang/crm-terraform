data "archive_file" "list_officers_zip" {
  type        = "zip"
  source_file = "${path.module}/list_officers.py"
  output_path = "${path.module}/list_officers.zip"
}

resource "aws_iam_role" "list_officers_role" {
  name = "crm-list-officers-role"

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

resource "aws_iam_role_policy" "list_officers_policy" {
  name = "crm-list-officers-policy"
  role = aws_iam_role.list_officers_role.id

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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-list-officers:*"
      }
    ]
  })
}

resource "aws_lambda_function" "list_officers" {
  function_name = "crm-list-officers"
  role          = aws_iam_role.list_officers_role.arn
  handler       = "list_officers.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.list_officers_zip.output_path
  source_code_hash = data.archive_file.list_officers_zip.output_base64sha256

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

resource "aws_apigatewayv2_integration" "list_officers_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_officers.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_officers" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /officers"
  target             = "integrations/${aws_apigatewayv2_integration.list_officers_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

resource "aws_lambda_permission" "allow_apigw_list_officers" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_officers.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}