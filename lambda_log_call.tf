data "archive_file" "log_call_zip" {
  type        = "zip"
  source_file = "${path.module}/log_call.py"
  output_path = "${path.module}/log_call.zip"
}

resource "aws_iam_role" "log_call_role" {
  name = "crm-log-call-role"

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

resource "aws_iam_role_policy" "log_call_policy" {
  name = "crm-log-call-policy"
  role = aws_iam_role.log_call_role.id

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
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/crm-log-call:*"
      }
    ]
  })
}

resource "aws_lambda_function" "log_call" {
  function_name = "crm-log-call"
  role          = aws_iam_role.log_call_role.arn
  handler       = "log_call.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.log_call_zip.output_path
  source_code_hash = data.archive_file.log_call_zip.output_base64sha256

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