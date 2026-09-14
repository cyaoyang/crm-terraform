data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_role" "bastion_role" {
  name = "crm-bastion-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = "crm-portfolio"
  }
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "crm-bastion-profile"
  role = aws_iam_role.bastion_role.name
}

resource "aws_security_group" "bastion_sg" {
  name        = "crm-bastion-sg"
  description = "Bastion host - no inbound needed, SSM only"
  vpc_id      = aws_vpc.crm_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "crm-bastion-sg"
    Project = "crm-portfolio"
  }
}

resource "aws_security_group_rule" "rds_from_bastion" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
  description               = "PostgreSQL from bastion host"
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion_profile.name
  associate_public_ip_address = true
key_name                    = aws_key_pair.bastion_key.key_name
root_block_device {
    encrypted = true
  }

user_data = <<-EOT
    #!/bin/bash
    dnf install -y postgresql15 amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOT

  tags = {
    Name    = "crm-bastion"
    Project = "crm-portfolio"
  }
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "crm-bastion-key"
  public_key = file("crm-bastion-key.pub")
}