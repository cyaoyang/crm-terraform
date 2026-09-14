resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.crm_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name    = "crm-private-subnet-a"
    Project = "crm-portfolio"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.crm_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-southeast-1b"

  tags = {
    Name    = "crm-private-subnet-b"
    Project = "crm-portfolio"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.crm_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name    = "crm-public-subnet-a"
    Project = "crm-portfolio"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.crm_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-southeast-1b"

  tags = {
    Name    = "crm-public-subnet-b"
    Project = "crm-portfolio"
  }
}