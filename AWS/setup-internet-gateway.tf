resource "aws_internet_gateway" "oan_igw" {
  vpc_id = aws_vpc.oan_vpc.id

  tags = {
    Name = "OAN IGW: ${var.proj_name} AP South 1"
  }
}

resource "aws_route_table" "oan_public_rt" {
  vpc_id = aws_vpc.oan_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.oan_igw.id
  }

  tags = {
    Name = "OAN RT: Public Route Table"
  }
}

resource "aws_route_table_association" "oan_public_rt_assoc" {
  count          = length(var.cidr_public_subnet)
  subnet_id      = aws_subnet.oan_public_subnet[count.index].id
  route_table_id = aws_route_table.oan_public_rt.id
}
