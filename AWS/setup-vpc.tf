resource "aws_vpc" "oan_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "VPC: OAN ${var.proj_name}"
  }
}
