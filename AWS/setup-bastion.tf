# ==================================
# Bastion Host (Jump Server)
# ==================================
# SSH into the bastion first, then hop to any private instance.
# Usage: ssh -J ubuntu@<bastion-ip> ubuntu@<private-ip>

# Security Group: Allow SSH from anywhere (restrict in production)
resource "aws_security_group" "oan_bastion_sg" {
  name        = "${var.proj_name}-bastion-sg"
  description = "Security group for OAN Bastion Host (SSH jump server)"
  vpc_id      = aws_vpc.oan_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # TODO: Restrict to your IP for security
  }

  # Allow all internal VPC traffic (for Consul gossip)
  ingress {
    description = "Internal VPC traffic"
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
    Name = "OAN SG: Bastion"
  }
}

# Bastion EC2 Instance (Public Subnet)
resource "aws_instance" "oan_bastion" {
  ami                         = data.aws_ami.oan_ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.oan_public_subnet[0].id
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.oan_bastion_sg.id]

  user_data = <<-EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting OAN Bastion Host setup..."

apt-get update -y
apt-get install -y unzip dnsutils curl jq

# Install Consul agent (so bastion can resolve *.service.consul)
curl -fsSL "https://releases.hashicorp.com/consul/${var.consul_version}/consul_${var.consul_version}_linux_amd64.zip" -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
rm consul.zip
mkdir -p /etc/consul.d /opt/consul

cat > /etc/consul.d/consul.hcl <<CONSULHCL
datacenter  = "dc1"
data_dir    = "/opt/consul"
client_addr = "0.0.0.0"
bind_addr   = "{{ GetPrivateIP }}"
retry_join  = ["${var.consul_server_private_ip}"]
recursors   = ["10.0.0.2"]
CONSULHCL

cat > /etc/systemd/system/consul.service <<'SYSTEMD'
[Unit]
Description=HashiCorp Consul Agent - OAN Bastion
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable consul
systemctl start consul

# DNS forwarding for .consul domain
iptables -t nat -A OUTPUT -d localhost -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
iptables -t nat -A OUTPUT -d localhost -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
netfilter-persistent save

echo "OAN Bastion Host setup complete."
EOF

  tags = {
    Name = "OAN - Bastion (Jump Server)"
    Role = "bastion"
  }

  depends_on = [
    aws_route_table_association.oan_public_rt_assoc,
    aws_instance.oan_consul_server
  ]
}

# Elastic IP for Bastion (stable SSH endpoint)
resource "aws_eip" "oan_bastion_eip" {
  instance = aws_instance.oan_bastion.id
  domain   = "vpc"

  tags = {
    Name = "OAN EIP: Bastion"
  }

  depends_on = [aws_internet_gateway.oan_igw]
}
