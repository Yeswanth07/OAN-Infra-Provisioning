resource "aws_subnet" "oan_public_subnet" {
  count             = length(var.cidr_public_subnet)
  vpc_id            = aws_vpc.oan_vpc.id
  cidr_block        = element(var.cidr_public_subnet, count.index)
  availability_zone = element(var.ap_availability_zone, count.index)

  tags = {
    Name = "OAN Subnet: Public ${count.index + 1}"
  }
}

resource "aws_subnet" "oan_private_subnet" {
  count             = length(var.cidr_private_subnet)
  vpc_id            = aws_vpc.oan_vpc.id
  cidr_block        = element(var.cidr_private_subnet, count.index)
  availability_zone = element(var.ap_availability_zone, count.index)

  tags = {
    Name = "OAN Subnet: Private ${count.index + 1}"
  }
}
