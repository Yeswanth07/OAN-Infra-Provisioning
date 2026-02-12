# ==================================
# Nginx Security Group
# ==================================

resource "aws_security_group" "oan_nginx_sg" {
  name        = "${var.proj_name}-nginx-sg"
  description = "Security group for OAN Nginx reverse proxy / load balancer"
  vpc_id      = aws_vpc.oan_vpc.id

  # Allow HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS from anywhere (for future SSL setup)
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal VPC traffic (for Consul gossip + internal communication)
  ingress {
    description = "Internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow SSH (for management - restrict to your IP in production)
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP for security
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "OAN SG: Nginx"
  }
}

# ==================================
# Nginx EC2 Instance (Public Subnet)
# ==================================

resource "aws_instance" "oan_nginx" {
  ami                         = data.aws_ami.oan_ubuntu.id
  instance_type               = var.nginx_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = aws_subnet.oan_public_subnet[0].id
  associate_public_ip_address = true

  vpc_security_group_ids = [aws_security_group.oan_nginx_sg.id]

  user_data = templatefile("nginx_user_data.sh.tpl", {
    consul_server_ip    = var.consul_server_private_ip
    consul_version      = var.consul_version
    frontend_port       = var.service_ports["frontend"]
    llm_port            = var.service_ports["LLM"]
    mock_port           = var.service_ports["mock"]
    telemetry_svc_port  = var.service_ports["Telemetry-service"]
    telemetry_dash_port = var.service_ports["Telemetry-dashboard"]
    keycloak_port       = var.service_ports["Key-cloak"]
  })

  tags = {
    Name = "OAN - Nginx (Reverse Proxy + LB)"
    Role = "nginx"
  }

  depends_on = [
    aws_route_table_association.oan_public_rt_assoc,
    aws_instance.oan_consul_server
  ]
}

# ==================================
# Elastic IP for Nginx
# ==================================

resource "aws_eip" "oan_nginx_eip" {
  instance = aws_instance.oan_nginx.id
  domain   = "vpc"

  tags = {
    Name = "OAN EIP: Nginx"
  }

  depends_on = [aws_internet_gateway.oan_igw]
}
