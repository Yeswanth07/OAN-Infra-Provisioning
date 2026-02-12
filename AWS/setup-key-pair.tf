# ==================================
# SSH Key Pair (auto-generated)
# ==================================
# Creates a new key pair for SSH access to all instances.
# The private key is saved to a local file.

resource "tls_private_key" "oan_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "oan_key_pair" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.oan_ssh_key.public_key_openssh

  tags = {
    Name = "OAN SSH Key Pair"
  }
}

# Save private key to a local file
resource "local_file" "oan_private_key" {
  content         = tls_private_key.oan_ssh_key.private_key_pem
  filename        = "${path.module}/oan-key.pem"
  file_permission = "0400"
}
