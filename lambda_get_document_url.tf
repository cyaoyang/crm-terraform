data "archive_file" "get_document_url_zip" {
  type        = "zip"
  source_file = "${path.module}/get_document_url.py"
  output_path = "${path.module}/get_document_url.zip"
}

resource "aws_iam_role" "get_document_url_role" {
  name = "crm-get-document-url-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}

resource "aws_iam_role_policy" "get_document_url_policy" {
  name = "crm-get-document-url-policy"
  role = aws_iam_role.get_document_url_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowVPCNetworkInterfaceForRDSAccess", Effect = "Allow"
        Action = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      },
      {
        Sid = "AllowOwnLogGroupOnly", Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-get-document-url:*"
      },
      {
        Sid = "AllowReadLegalDocsPrefix", Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.legal_documents.arn}/legal-docs/*"
      },
      {
        Sid = "AllowUseOfLegalDocsKMSKey", Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = aws_kms_key.legal_docs_key.arn
      }
    ]
  })
}

resource "aws_lambda_function" "get_document_url" {
  function_name = "crm-get-document-url"
  role          = aws_iam_role.get_document_url_role.arn
  handler       = "get_document_url.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.get_document_url_zip.output_path
  source_code_hash = data.archive_file.get_document_url_zip.output_base64sha256
  layers           = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_HOST           = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME           = "crmdb"
      DB_USER           = "crmadmin"
      DB_PASSWORD       = random_password.rds_master_password.result
      LEGAL_DOCS_BUCKET = aws_s3_bucket.legal_documents.bucket
    }
  }
  tags = { Project = "crm-portfolio" }
}

resource "aws_apigatewayv2_integration" "get_document_url_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_document_url.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "get_document_url_route" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /documents/url"
  target             = "integrations/${aws_apigatewayv2_integration.get_document_url_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_get_document_url" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_document_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}