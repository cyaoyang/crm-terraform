data "archive_file" "create_legal_referral_zip" {
  type        = "zip"
  source_file = "${path.module}/create_legal_referral.py"
  output_path = "${path.module}/create_legal_referral.zip"
}
data "archive_file" "list_law_firms_zip" {
  type        = "zip"
  source_file = "${path.module}/list_law_firms.py"
  output_path = "${path.module}/list_law_firms.zip"
}
data "archive_file" "list_firm_referrals_zip" {
  type        = "zip"
  source_file = "${path.module}/list_firm_referrals.py"
  output_path = "${path.module}/list_firm_referrals.zip"
}
data "archive_file" "get_firm_case_detail_zip" {
  type        = "zip"
  source_file = "${path.module}/get_firm_case_detail.py"
  output_path = "${path.module}/get_firm_case_detail.zip"
}
data "archive_file" "mark_referral_sent_zip" {
  type        = "zip"
  source_file = "${path.module}/mark_referral_sent.py"
  output_path = "${path.module}/mark_referral_sent.zip"
}

resource "aws_iam_role" "create_legal_referral_role" {
  name = "crm-create-legal-referral-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}

resource "aws_iam_role_policy" "create_legal_referral_policy" {
  name = "crm-create-legal-referral-policy"
  role = aws_iam_role.create_legal_referral_role.id
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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-create-legal-referral:*"
      },
      {
        Sid = "AllowWritePDFToLegalDocsPrefix", Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.legal_documents.arn}/legal-docs/*"
      },
      {
        Sid = "AllowUseOfLegalDocsKMSKey", Effect = "Allow"
        Action = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.legal_docs_key.arn
      }
    ]
  })
}

resource "aws_lambda_function" "create_legal_referral" {
  function_name = "crm-create-legal-referral"
  role          = aws_iam_role.create_legal_referral_role.arn
  handler       = "create_legal_referral.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.create_legal_referral_zip.output_path
  source_code_hash = data.archive_file.create_legal_referral_zip.output_base64sha256

  layers = [
    "arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1",
    "arn:aws:lambda:ap-southeast-1:476405983532:layer:reportlab-layer:1",
  ]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST              = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME              = "crmdb"
      DB_USER              = "crmadmin"
      DB_PASSWORD          = random_password.rds_master_password.result
      LEGAL_DOCS_BUCKET    = aws_s3_bucket.legal_documents.bucket
      LEGAL_DOCS_KMS_KEY_ID = aws_kms_key.legal_docs_key.key_id
    }
  }

  tags = { Project = "crm-portfolio" }
}

resource "aws_apigatewayv2_integration" "create_legal_referral_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.create_legal_referral.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "post_legal_referrals" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "POST /legal-referrals"
  target             = "integrations/${aws_apigatewayv2_integration.create_legal_referral_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_create_legal_referral" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_legal_referral.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_iam_role" "list_law_firms_role" {
  name = "crm-list-law-firms-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}
resource "aws_iam_role_policy" "list_law_firms_policy" {
  name = "crm-list-law-firms-policy"
  role = aws_iam_role.list_law_firms_role.id
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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-list-law-firms:*"
      }
    ]
  })
}
resource "aws_lambda_function" "list_law_firms" {
  function_name = "crm-list-law-firms"
  role          = aws_iam_role.list_law_firms_role.arn
  handler       = "list_law_firms.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.list_law_firms_zip.output_path
  source_code_hash = data.archive_file.list_law_firms_zip.output_base64sha256
  layers           = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_HOST = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME = "crmdb"
      DB_USER = "crmadmin"
      DB_PASSWORD = random_password.rds_master_password.result
    }
  }
  tags = { Project = "crm-portfolio" }
}
resource "aws_apigatewayv2_integration" "list_law_firms_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_law_firms.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "get_law_firms" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /law-firms"
  target             = "integrations/${aws_apigatewayv2_integration.list_law_firms_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_list_law_firms" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_law_firms.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_iam_role" "list_firm_referrals_role" {
  name = "crm-list-firm-referrals-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}
resource "aws_iam_role_policy" "list_firm_referrals_policy" {
  name = "crm-list-firm-referrals-policy"
  role = aws_iam_role.list_firm_referrals_role.id
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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-list-firm-referrals:*"
      }
    ]
  })
}
resource "aws_lambda_function" "list_firm_referrals" {
  function_name = "crm-list-firm-referrals"
  role          = aws_iam_role.list_firm_referrals_role.arn
  handler       = "list_firm_referrals.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.list_firm_referrals_zip.output_path
  source_code_hash = data.archive_file.list_firm_referrals_zip.output_base64sha256
  layers           = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_HOST = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME = "crmdb"
      DB_USER = "crmadmin"
      DB_PASSWORD = random_password.rds_master_password.result
    }
  }
  tags = { Project = "crm-portfolio" }
}
resource "aws_apigatewayv2_integration" "list_firm_referrals_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.list_firm_referrals.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "get_firm_referrals" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /firm/referrals"
  target             = "integrations/${aws_apigatewayv2_integration.list_firm_referrals_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_list_firm_referrals" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_firm_referrals.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_iam_role" "get_firm_case_detail_role" {
  name = "crm-get-firm-case-detail-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}
resource "aws_iam_role_policy" "get_firm_case_detail_policy" {
  name = "crm-get-firm-case-detail-policy"
  role = aws_iam_role.get_firm_case_detail_role.id
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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-get-firm-case-detail:*"
      }
    ]
  })
}
resource "aws_lambda_function" "get_firm_case_detail" {
  function_name = "crm-get-firm-case-detail"
  role          = aws_iam_role.get_firm_case_detail_role.arn
  handler       = "get_firm_case_detail.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.get_firm_case_detail_zip.output_path
  source_code_hash = data.archive_file.get_firm_case_detail_zip.output_base64sha256
  layers           = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_HOST = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME = "crmdb"
      DB_USER = "crmadmin"
      DB_PASSWORD = random_password.rds_master_password.result
    }
  }
  tags = { Project = "crm-portfolio" }
}
resource "aws_apigatewayv2_integration" "get_firm_case_detail_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_firm_case_detail.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "get_firm_case_detail_route" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "GET /firm/referrals/{escalation_id}"
  target             = "integrations/${aws_apigatewayv2_integration.get_firm_case_detail_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_get_firm_case_detail" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_firm_case_detail.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}

resource "aws_iam_role" "mark_referral_sent_role" {
  name = "crm-mark-referral-sent-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = { Project = "crm-portfolio" }
}
resource "aws_iam_role_policy" "mark_referral_sent_policy" {
  name = "crm-mark-referral-sent-policy"
  role = aws_iam_role.mark_referral_sent_role.id
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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-mark-referral-sent:*"
      },
      {
        Sid = "AllowWriteConfirmationDocToLegalDocsPrefix", Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.legal_documents.arn}/legal-docs/*"
      },
      {
        Sid = "AllowUseOfLegalDocsKMSKey", Effect = "Allow"
        Action = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.legal_docs_key.arn
      }
    ]
  })
}
resource "aws_lambda_function" "mark_referral_sent" {
  function_name = "crm-mark-referral-sent"
  role          = aws_iam_role.mark_referral_sent_role.arn
  handler       = "mark_referral_sent.handler"
  runtime       = "python3.12"
  timeout       = 15
  memory_size   = 256

  filename         = data.archive_file.mark_referral_sent_zip.output_path
  source_code_hash = data.archive_file.mark_referral_sent_zip.output_base64sha256
  layers           = ["arn:aws:lambda:ap-southeast-1:476405983532:layer:psycopg2-layer:1"]

  vpc_config {
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  environment {
    variables = {
      DB_HOST               = split(":", aws_db_instance.crm_db.endpoint)[0]
      DB_NAME                = "crmdb"
      DB_USER                = "crmadmin"
      DB_PASSWORD            = random_password.rds_master_password.result
      LEGAL_DOCS_BUCKET      = aws_s3_bucket.legal_documents.bucket
      LEGAL_DOCS_KMS_KEY_ID  = aws_kms_key.legal_docs_key.key_id
    }
  }
  tags = { Project = "crm-portfolio" }
}
resource "aws_apigatewayv2_integration" "mark_referral_sent_integration" {
  api_id                 = aws_apigatewayv2_api.crm_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.mark_referral_sent.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_route" "post_mark_referral_sent" {
  api_id             = aws_apigatewayv2_api.crm_api.id
  route_key          = "POST /firm/referrals/{escalation_id}/mark-sent"
  target             = "integrations/${aws_apigatewayv2_integration.mark_referral_sent_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}
resource "aws_lambda_permission" "allow_apigw_mark_referral_sent" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mark_referral_sent.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.crm_api.execution_arn}/*/*"
}