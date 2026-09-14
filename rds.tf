resource "random_password" "rds_master_password" {
  length  = 20
  special = false
}

resource "aws_db_subnet_group" "crm_db_subnet_group" {
  name       = "crm-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name    = "crm-db-subnet-group"
    Project = "crm-portfolio"
  }
}

resource "aws_db_instance" "crm_db" {
  identifier     = "crm-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = "crmdb"
  username = "crmadmin"
  password = random_password.rds_master_password.result

  db_subnet_group_name   = aws_db_subnet_group.crm_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 7

  deletion_protection = false

  skip_final_snapshot = true

  tags = {
    Name    = "crm-db"
    Project = "crm-portfolio"
  }
}