# ==================================
# Outputs
# ==================================

output "bastion_elastic_ip" {
  description = "Public Elastic IP of the Bastion Host (SSH jump server)"
  value       = aws_eip.oan_bastion_eip.public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to the Bastion Host"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.oan_bastion_eip.public_ip}"
}

output "nginx_elastic_ip" {
  description = "Public Elastic IP of the Nginx reverse proxy / load balancer"
  value       = aws_eip.oan_nginx_eip.public_ip
}

output "nginx_public_dns" {
  description = "Public DNS of the Nginx instance"
  value       = aws_instance.oan_nginx.public_dns
}

output "vpc_id" {
  description = "The ID of the OAN VPC"
  value       = aws_vpc.oan_vpc.id
}

output "nat_gateway_eips" {
  description = "Public IPs of the NAT Gateway EIPs"
  value       = aws_eip.oan_nat_eip[*].public_ip
}

output "consul_server_private_ip" {
  description = "Private IP of the Consul server for service discovery"
  value       = aws_instance.oan_consul_server.private_ip
}

output "private_instance_ips" {
  description = "Private IPs of all service instances"
  value = {
    for role, instance in aws_instance.oan_instances :
    role => instance.private_ip
  }
}
