#!/bin/bash
# ==================================
# OAN Service Instance Bootstrap Script
# ==================================
# This script runs on every private EC2 instance.
# It installs Docker, Consul agent, and the role-specific service.

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting OAN setup for role: ${role}"
echo "========================================="

# ----------------------------------
# 1. Install Docker (all instances)
# ----------------------------------
echo "[1/4] Installing Docker..."
apt-get update -y
apt-get install -y docker.io unzip
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# ----------------------------------
# 2. Install & Configure Consul Agent
# ----------------------------------
echo "[2/4] Installing Consul agent ${consul_version}..."
curl -fsSL "https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip" -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
rm consul.zip
mkdir -p /etc/consul.d /opt/consul

# Consul agent configuration
cat > /etc/consul.d/consul.hcl <<CONSULHCL
datacenter  = "dc1"
data_dir    = "/opt/consul"
client_addr = "0.0.0.0"
bind_addr   = "{{ GetPrivateIP }}"
retry_join  = ["${consul_server_ip}"]
recursors   = ["10.0.0.2"]
CONSULHCL

# Register this service with Consul for DNS-based discovery
# Other services can find this via: ${role}.service.consul
cat > /etc/consul.d/${role}.hcl <<CONSULSERVICE
service {
  name = "${role}"
  port = ${service_port}
  check {
    tcp      = "localhost:${service_port}"
    interval = "10s"
    timeout  = "3s"
  }
}
CONSULSERVICE

# Consul systemd service
cat > /etc/systemd/system/consul.service <<'SYSTEMD'
[Unit]
Description=HashiCorp Consul Agent - OAN Service Discovery
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

# ----------------------------------
# 3. Configure DNS forwarding for .consul domain
# ----------------------------------
echo "[3/4] Configuring DNS forwarding for Consul..."

# Redirect local DNS queries to Consul's DNS port (8600)
# This allows resolving <service>.service.consul via standard DNS
iptables -t nat -A OUTPUT -d localhost -p udp -m udp --dport 53 -j REDIRECT --to-ports 8600
iptables -t nat -A OUTPUT -d localhost -p tcp -m tcp --dport 53 -j REDIRECT --to-ports 8600

# Persist iptables rules across reboots (non-interactive)
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
netfilter-persistent save

# ----------------------------------
# 4. Role-specific service setup
# ----------------------------------
echo "[4/4] Setting up service for role: ${role}..."

# ==========================================
# ECR-based services (Application + Telemetry)
# ==========================================
# If ecr_image_uri is non-empty, this is an ECR service
%{ if ecr_image_uri != "" }
echo "ECR service detected. Installing AWS CLI and pulling image..."

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws/

# Login to ECR (retry up to 5 times)
n=0
until [ "$n" -ge 5 ]; do
  aws ecr get-login-password --region ap-south-1 | \
    docker login --username AWS --password-stdin 379220350808.dkr.ecr.ap-south-1.amazonaws.com && break
  n=$((n+1))
  echo "ECR login failed. Retrying in 5 seconds... (attempt $n/5)"
  sleep 5
done

# Pull the ECR image
IMAGE_URI="${ecr_image_uri}"
echo "Pulling image: $IMAGE_URI"
docker pull "$IMAGE_URI"

# Write .env file for this service (injected by Terraform)
mkdir -p /opt/oan
cat > /opt/oan/.env.raw <<'ENVFILE'
${env_content}
ENVFILE

# Strip comments, blank lines, header lines, and lines with spaces around '='
# so Docker only sees clean KEY=VALUE pairs
grep -v '^\s*#' /opt/oan/.env.raw | grep -v '^\s*$' | grep -v '^==' | grep -v '^---' | sed 's/ *= */=/' > /opt/oan/.env
rm -f /opt/oan/.env.raw
echo "Environment file written to /opt/oan/.env with $(wc -l < /opt/oan/.env) variables"

# Run the container
# Maps host port ${service_port} -> container port ${container_port}
echo "Running container: ${role} on port ${service_port}:${container_port}"
docker run -d \
  --name ${role} \
  --restart unless-stopped \
  --env-file /opt/oan/.env \
  -p ${service_port}:${container_port} \
  "$IMAGE_URI"

%{ endif }

# ==========================================
# Docker Hub services (Data Layer)
# ==========================================

%{ if role == "postgresql" }
echo "Setting up PostgreSQL via Docker..."
docker run -d \
  --name postgresql \
  --restart unless-stopped \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -v pgdata:/var/lib/postgresql/data \
  postgres:latest
# NOTE: Change POSTGRES_PASSWORD in production!
%{ endif }

%{ if role == "redis" }
echo "Setting up Redis via Docker..."
docker run -d \
  --name redis \
  --restart unless-stopped \
  -p 6379:6379 \
  -v redisdata:/data \
  redis:latest \
  redis-server --appendonly yes
%{ endif }

%{ if role == "opensearch" }
echo "Setting up OpenSearch via Docker..."
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -p 9200:9200 -p 9600:9600 \
  -e "discovery.type=single-node" \
  -e "OPENSEARCH_INITIAL_ADMIN_PASSWORD=MyStrongPassword123!" \
  -v osdata:/usr/share/opensearch/data \
  opensearchproject/opensearch:latest
# NOTE: Change OPENSEARCH_INITIAL_ADMIN_PASSWORD in production!
%{ endif }

%{ if role == "marqo" }
echo "Setting up Marqo via Docker..."
# TODO: Uncomment and configure once Marqo setup is finalized
# docker run -d \
#   --name marqo \
#   --restart unless-stopped \
#   -p 8882:8882 \
#   --add-host host.docker.internal:host-gateway \
#   marqoai/marqo:latest
echo "Marqo placeholder - uncomment docker run command when ready."
%{ endif }

%{ if role == "Key-cloak" }
echo "Setting up Keycloak via Docker..."
docker run -d \
  --name keycloak \
  --restart unless-stopped \
  -p 8080:8080 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  quay.io/keycloak/keycloak:latest \
  start-dev
# NOTE: Change admin credentials and use 'start' (not start-dev) in production!
%{ endif }

%{ if role == "nominatim" }
echo "Setting up Nominatim via Docker..."
# TODO: Uncomment and configure once Nominatim PBF data source is decided
# docker run -d \
#   --name nominatim \
#   --restart unless-stopped \
#   -p 8080:8080 \
#   -e PBF_URL=https://download.geofabrik.de/asia/india-latest.osm.pbf \
#   mediagis/nominatim:4.4
echo "Nominatim placeholder - uncomment docker run command when ready."
%{ endif }

echo "========================================="
echo "OAN setup complete for role: ${role}"
echo "Service registered with Consul as: ${role}.service.consul:${service_port}"
echo "========================================="
