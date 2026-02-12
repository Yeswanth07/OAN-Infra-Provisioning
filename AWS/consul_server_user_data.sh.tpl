#!/bin/bash
# ==================================
# Consul Server Bootstrap Script
# ==================================

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting OAN Consul Server setup..."
echo "========================================="

# Install dependencies
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip

# Install Consul
echo "Installing Consul ${consul_version}..."
curl -fsSL "https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip" -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
rm consul.zip
mkdir -p /etc/consul.d /opt/consul

# Create Consul server configuration
cat > /etc/consul.d/consul.hcl <<'CONSULHCL'
datacenter       = "dc1"
data_dir         = "/opt/consul"
server           = true
bootstrap_expect = 1
client_addr      = "0.0.0.0"
bind_addr        = "{{ GetPrivateIP }}"

ui_config {
  enabled = true
}

dns_config {
  allow_stale = true
}

# Forward non-.consul DNS queries to VPC DNS resolver
recursors = ["10.0.0.2"]
CONSULHCL

# Create systemd service for Consul
cat > /etc/systemd/system/consul.service <<'SYSTEMD'
[Unit]
Description=HashiCorp Consul Server - OAN Service Discovery
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable consul
systemctl start consul

echo "========================================="
echo "OAN Consul Server setup complete."
echo "Consul UI available at: http://<private-ip>:8500"
echo "========================================="
