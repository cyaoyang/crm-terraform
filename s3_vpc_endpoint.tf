resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.crm_vpc.id
  service_name = "com.amazonaws.ap-southeast-1.s3"
  route_table_ids = [aws_vpc.crm_vpc.default_route_table_id]

  tags = {
    Project = "crm-portfolio"
  }
}