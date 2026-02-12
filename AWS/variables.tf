# ==================================
# Project Configuration
# ==================================

variable "proj_name" {
  description = "Name tag for the project"
  type        = string
  default     = "OAN"
}

# ==================================
# VPC & Networking
# ==================================

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "cidr_public_subnet" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
}

variable "cidr_private_subnet" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  default     = ["10.0.2.0/24", "10.0.4.0/24"]
}

variable "ap_availability_zone" {
  type        = list(string)
  description = "Availability Zones"
  default     = ["ap-south-1a", "ap-south-1b"]
}

# ==================================
# Consul Configuration
# ==================================

variable "consul_server_private_ip" {
  type        = string
  description = "Fixed private IP for the Consul server (must be within the first private subnet CIDR)"
  default     = "10.0.2.10"
}

variable "consul_version" {
  type        = string
  description = "HashiCorp Consul version to install"
  default     = "1.17.0"
}

variable "consul_instance_type" {
  type        = string
  description = "Instance type for the Consul server"
  default     = "t2.micro"
}

# ==================================
# EC2 Instance Configuration
# ==================================

variable "ec2_roles" {
  type        = list(string)
  description = "Roles for EC2 instances in private subnets"
  default     = ["frontend", "redis", "LLM", "Telemetry-dashboard", "Telemetry-process", "Telemetry-service", "postgresql", "opensearch", "marqo", "mock", "Key-cloak", "nominatim"]
}

variable "ec2_instance_types" {
  type        = map(string)
  description = "Instance types for each role"
  default = {
    "frontend"            = "t2.micro"
    "redis"               = "t2.micro"
    "LLM"                 = "t2.medium"
    "Telemetry-dashboard" = "t2.micro"
    "Telemetry-process"   = "t2.micro"
    "Telemetry-service"   = "t2.micro"
    "postgresql"          = "t2.micro"
    "opensearch"          = "t2.micro"
    "marqo"               = "t3.medium"
    "mock"                = "t2.micro"
    "Key-cloak"           = "t3.small"
    "nominatim"           = "t2.micro"
  }
}

variable "nginx_instance_type" {
  type        = string
  description = "Instance type for the Nginx reverse proxy / load balancer"
  default     = "t2.micro"
}

variable "bastion_instance_type" {
  type        = string
  description = "Instance type for the Bastion Host (jump server)"
  default     = "t2.micro"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the AWS key pair for SSH access (must already exist in your AWS account)"
  # TODO: Replace with your actual AWS key pair name
  default = "oan-key"
}

# ==================================
# Service Ports (Host Ports)
# ==================================

variable "service_ports" {
  type        = map(number)
  description = "Port each service listens on (host port exposed to VPC)"
  default = {
    "frontend"            = 80
    "redis"               = 6379
    "LLM"                 = 8080
    "Telemetry-dashboard" = 3000
    "Telemetry-process"   = 8081 # Background worker — no port exposed by container
    "Telemetry-service"   = 8082
    "postgresql"          = 5432
    "opensearch"          = 9200
    "marqo"               = 8882
    "mock"                = 8083
    "Key-cloak"           = 8080
    "nominatim"           = 8084
  }
}

# ==================================
# Container Ports (Internal)
# ==================================

variable "container_ports" {
  type        = map(number)
  description = "Internal container port (may differ from host port)"
  default = {
    "frontend"            = 8081 # Container listens on 8081, mapped to host 80
    "redis"               = 6379
    "LLM"                 = 8080
    "Telemetry-dashboard" = 3000
    "Telemetry-process"   = 8081 # Background worker — no port exposed
    "Telemetry-service"   = 8082
    "postgresql"          = 5432
    "opensearch"          = 9200
    "marqo"               = 8882
    "mock"                = 8083
    "Key-cloak"           = 8080
    "nominatim"           = 8084
  }
}

# ==================================
# ECR Image URIs
# ==================================
# NOTE: These are PLACEHOLDER URIs. Replace with actual ECR image URIs
# once the images are built and pushed to your ECR repository.

variable "ecr_image_uris" {
  type        = map(string)
  description = "ECR image URIs for OAN application and telemetry services"
  default = {
    # --- OAN Application Layer ---
    "frontend" = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:oan-ui-service-latest"
    "LLM"      = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:mh-oan-api-LLM"
    "mock"     = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:Beckn-mock-latest"

    # --- Telemetry ---
    "Telemetry-service"   = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:telemetry-dashboard-service"
    "Telemetry-process"   = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:telemetry-dashboard-processor"
    "Telemetry-dashboard" = "379220350808.dkr.ecr.ap-south-1.amazonaws.com/oan:telemetry-dashboard-ui-latest"
  }
}

# ==================================
# Service Environment Files
# ==================================
# Maps each role to its .env file path (relative to module root).
# These are injected into containers at boot time via --env-file.

variable "service_env_files" {
  type        = map(string)
  description = "Map of role name to .env file path (relative to module root)"
  default = {
    "frontend"            = "Env-path-file/frontend.txt"
    "LLM"                 = "Env-path-file/LLM.txt"
    "mock"                = "Env-path-file/mock.txt"
    "Telemetry-dashboard" = "Env-path-file/telemetry-dashbord.txt"
    "Telemetry-process"   = "Env-path-file/telemetry-process.txt"
    "Telemetry-service"   = "Env-path-file/telemetry-service.txt"
  }
}
