# ==================================
# Consul Server Instance
# ==================================
# Consul provides open-source service discovery via DNS.
# All other instances run Consul agents that register with this server.
# Services discover each other using DNS: <service>.service.consul
# Example: postgresql.service.consul -> private IP of postgresql instance

resource "aws_instance" "oan_consul_server" {
  ami           = data.aws_ami.oan_ubuntu.id
  instance_type = var.consul_instance_type
  key_name      = var.ssh_key_name

  subnet_id  = aws_subnet.oan_private_subnet[0].id
  private_ip = var.consul_server_private_ip

  vpc_security_group_ids = [aws_security_group.oan_private_sg.id]

  user_data = templatefile("consul_server_user_data.sh.tpl", {
    consul_version = var.consul_version
  })

  tags = {
    Name = "OAN - Consul Server"
    Role = "consul-server"
  }

  depends_on = [aws_route_table_association.oan_private_rt_assoc]
}
