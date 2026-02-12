resource "aws_eip" "oan_nat_eip" {
  count  = length(var.cidr_private_subnet)
  domain = "vpc"

  tags = {
    Name = "OAN EIP: NAT Gateway ${count.index + 1}"
  }
}

resource "aws_nat_gateway" "oan_nat_gw" {
  count         = length(var.cidr_private_subnet)
  allocation_id = aws_eip.oan_nat_eip[count.index].id
  subnet_id     = aws_subnet.oan_public_subnet[count.index].id

  tags = {
    Name = "OAN NAT GW: ${var.proj_name} ${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.oan_igw]
}

resource "aws_route_table" "oan_private_rt" {
  count  = length(var.cidr_private_subnet)
  vpc_id = aws_vpc.oan_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.oan_nat_gw[count.index].id
  }

  tags = {
    Name = "OAN RT: Private Route Table ${count.index + 1}"
  }
}

resource "aws_route_table_association" "oan_private_rt_assoc" {
  count          = length(var.cidr_private_subnet)
  subnet_id      = aws_subnet.oan_private_subnet[count.index].id
  route_table_id = aws_route_table.oan_private_rt[count.index].id
}
