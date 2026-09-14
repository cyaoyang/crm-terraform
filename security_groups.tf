resource "aws_security_group" "lambda_sg" {
  name        = "crm-lambda-sg"
  description = "Security group attached to CRM Lambda functions"
  vpc_id      = aws_vpc.crm_vpc.id

  tags = {
    Name    = "crm-lambda-sg"
    Project = "crm-portfolio"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "crm-rds-sg"
  description = "Security group for RDS - only Lambda may connect"
  vpc_id      = aws_vpc.crm_vpc.id
 
  tags = {
    Name    = "crm-rds-sg"
    Project = "crm-portfolio"
  }
}

resource "aws_security_group_rule" "rds_from_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id
  source_security_group_id = aws_security_group.lambda_sg.id
  description              = "PostgreSQL from Lambda only"
}

resource "aws_security_group_rule" "lambda_to_rds_egress" {
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.lambda_sg.id
  source_security_group_id = aws_security_group.rds_sg.id
  description              = "Allow Lambda outbound to RDS only"
}

resource "aws_security_group_rule" "lambda_to_s3_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.lambda_sg.id
  prefix_list_ids   = [aws_vpc_endpoint.s3.prefix_list_id]
  description       = "Allow Lambda outbound HTTPS to S3 via VPC endpoint only"
}