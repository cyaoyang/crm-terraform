resource "aws_internet_gateway" "crm_igw" {
  vpc_id = aws_vpc.crm_vpc.id

  tags = {
    Name    = "crm-igw"
    Project = "crm-portfolio"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.crm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.crm_igw.id
  }

  tags = {
    Name    = "crm-public-rt"
    Project = "crm-portfolio"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}