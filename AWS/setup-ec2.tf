# ==================================
# Security Group for Private Instances
# ==================================

resource "aws_security_group" "oan_private_sg" {
  name        = "${var.proj_name}-private-sg"
  description = "Security group for OAN private instances - allows all intra-VPC traffic"
  vpc_id      = aws_vpc.oan_vpc.id

  ingress {
    description = "Allow all internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "OAN SG: Private Instances"
  }
}

# ==================================
# Ubuntu AMI Data Source
# ==================================

data "aws_ami" "oan_ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ==================================
# Private EC2 Instances (All Services)
# ==================================

resource "aws_instance" "oan_instances" {
  for_each = toset(var.ec2_roles)

  ami           = data.aws_ami.oan_ubuntu.id
  instance_type = var.ec2_instance_types[each.key]
  key_name      = var.ssh_key_name

  # Using existing IAM Role (Instance Profile) from the account
  iam_instance_profile = "EC2-ECR-Read-Role"

  # Deploy in the first private subnet
  subnet_id = aws_subnet.oan_private_subnet[0].id

  vpc_security_group_ids = [aws_security_group.oan_private_sg.id]

  user_data = templatefile("user_data.sh.tpl", {
    role             = each.key
    consul_server_ip = var.consul_server_private_ip
    consul_version   = var.consul_version
    service_port     = var.service_ports[each.key]
    container_port   = var.container_ports[each.key]
    ecr_image_uri    = lookup(var.ecr_image_uris, each.key, "")
    env_content      = lookup(var.service_env_files, each.key, "") != "" ? file("${path.module}/${var.service_env_files[each.key]}") : ""
  })

  tags = {
    Name = "OAN - ${title(each.key)}"
    Role = each.key
  }

  depends_on = [
    aws_route_table_association.oan_private_rt_assoc,
    aws_instance.oan_consul_server
  ]
}
