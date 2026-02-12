#!/bin/bash
# ==================================
# OAN Nginx Reverse Proxy + Load Balancer Bootstrap
# ==================================
# Nginx sits in the public subnet, receives all external traffic,
# and routes to internal services via Consul DNS.

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================="
echo "Starting OAN Nginx setup..."
echo "========================================="

# ----------------------------------
# 1. Install Nginx
# ----------------------------------
echo "[1/3] Installing Nginx..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx unzip

# ----------------------------------
# 2. Install & Configure Consul Agent
# ----------------------------------
echo "[2/3] Installing Consul agent..."
curl -fsSL "https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip" -o consul.zip
unzip consul.zip
mv consul /usr/local/bin/
rm consul.zip
mkdir -p /etc/consul.d /opt/consul

# Consul agent configuration (client mode)
cat > /etc/consul.d/consul.hcl <<CONSULHCL
datacenter  = "dc1"
data_dir    = "/opt/consul"
client_addr = "0.0.0.0"
bind_addr   = "{{ GetPrivateIP }}"
retry_join  = ["${consul_server_ip}"]
recursors   = ["10.0.0.2"]
CONSULHCL

# Register Nginx itself with Consul
cat > /etc/consul.d/nginx.hcl <<CONSULSERVICE
service {
  name = "nginx"
  port = 80
  check {
    http     = "http://localhost:80/health"
    interval = "10s"
    timeout  = "3s"
  }
}
CONSULSERVICE

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

# Wait for Consul to be ready
echo "Waiting for Consul agent to join cluster..."
sleep 10

# ----------------------------------
# 3. Configure Nginx
# ----------------------------------
echo "[3/3] Configuring Nginx reverse proxy + load balancer..."

cat > /etc/nginx/sites-available/default <<'NGINXCONF'
# ==================================
# OAN Nginx - Reverse Proxy + Load Balancer
# ==================================
# Uses Consul DNS (port 8600) for service discovery.
# When scaling a service, add more servers to the upstream block.
#
# How Consul DNS works:
#   frontend.service.consul  -> resolves to private IP of frontend instance
#   postgresql.service.consul -> resolves to private IP of postgresql instance

# Consul DNS resolver - re-resolves every 5 seconds
resolver 127.0.0.1:8600 valid=5s ipv6=off;

# ==========================================
# Upstream blocks (for load balancing)
# ==========================================
# When you scale a service to multiple instances, Consul DNS will
# return multiple IPs. Nginx upstream handles load distribution.
# For now, each upstream has 1 server resolved via Consul.
#
# NOTE: Upstream blocks with DNS require the "resolve" parameter
#       in Nginx Plus only. For open-source Nginx, we use variables
#       in proxy_pass instead (see location blocks below).

server {
    listen 80;
    server_name _;

    # ----------------------------------
    # Health check endpoint for Nginx itself
    # ----------------------------------
    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    # ----------------------------------
    # Frontend (default route)
    # ----------------------------------
    location / {
        set $frontend_backend "frontend.service.consul";
NGINXCONF

# Now append the dynamic port values (these come from Terraform template variables)
cat >> /etc/nginx/sites-available/default <<NGINXDYNAMIC
        proxy_pass http://\$frontend_backend:${frontend_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ----------------------------------
    # LLM Service
    # TODO: Update path once API routes are finalized
    # ----------------------------------
    location /api/llm/ {
        set \$llm_backend "LLM.service.consul";
        proxy_pass http://\$llm_backend:${llm_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ----------------------------------
    # Mock Service
    # TODO: Update path once API routes are finalized
    # ----------------------------------
    location /api/mock/ {
        set \$mock_backend "mock.service.consul";
        proxy_pass http://\$mock_backend:${mock_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ----------------------------------
    # Keycloak Auth Check (internal subrequest)
    # Used by Telemetry routes to verify admin access
    # ----------------------------------
    location = /_auth_check {
        internal;
        set \$keycloak_auth "Key-cloak.service.consul";
        proxy_pass http://\$keycloak_auth:${keycloak_port}/auth/realms/master/protocol/openid-connect/userinfo;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI \$request_uri;
    }

    # ----------------------------------
    # Telemetry Service API (ADMIN ONLY)
    # Access is gated by Keycloak authentication.
    # Only authenticated admin users can access telemetry endpoints.
    # TODO: Update path and Keycloak realm once auth is configured
    # ----------------------------------
    location /api/telemetry/ {
        # Uncomment the line below once Keycloak is fully configured
        auth_request /_auth_check;
        set \$telsvc_backend "Telemetry-service.service.consul";
        proxy_pass http://\$telsvc_backend:${telemetry_svc_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ----------------------------------
    # Telemetry Dashboard (ADMIN ONLY)
    # Access is gated by Keycloak authentication.
    # Only authenticated admin users can access the dashboard.
    # TODO: Update path and Keycloak realm once auth is configured
    # ----------------------------------
    location /dashboard/ {
        # Uncomment the line below once Keycloak is fully configured
        # auth_request /_auth_check;
        set \$teldash_backend "Telemetry-dashboard.service.consul";
        proxy_pass http://\$teldash_backend:${telemetry_dash_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ----------------------------------
    # Keycloak (Auth)
    # TODO: Update path once auth routes are finalized
    # ----------------------------------
    location /auth/ {
        set \$keycloak_backend "Key-cloak.service.consul";
        proxy_pass http://\$keycloak_backend:${keycloak_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXDYNAMIC

# Test and reload Nginx config
nginx -t && systemctl restart nginx

echo "========================================="
echo "OAN Nginx setup complete."
echo "Reverse proxy routes configured via Consul DNS."
echo "========================================="
