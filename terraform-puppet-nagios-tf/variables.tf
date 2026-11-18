variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Base project name used in resource naming and tags"
  type        = string
  default     = "campus-lost-and-found"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "master_subnet_cidr" {
  description = "Puppet Master subnet CIDR block"
  type        = string
  default     = "10.30.1.0/24"

  validation {
    condition     = can(cidrhost(var.master_subnet_cidr, 0))
    error_message = "master_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "agent_subnet_cidr" {
  description = "Puppet Agent subnet CIDR block"
  type        = string
  default     = "10.30.2.0/24"

  validation {
    condition     = can(cidrhost(var.agent_subnet_cidr, 0))
    error_message = "agent_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone_master" {
  description = "Availability Zone for Puppet Master subnet"
  type        = string
  default     = "ap-south-1a"
}

variable "availability_zone_agent" {
  description = "Availability Zone for Puppet Agent subnet"
  type        = string
  default     = "ap-south-1b"
}

variable "master_private_ip" {
  description = "Static private IP for Puppet Master"
  type        = string
  default     = "10.30.1.10"

  validation {
    condition     = can(cidrhost("${var.master_private_ip}/32", 0))
    error_message = "master_private_ip must be a valid IPv4 address."
  }
}

variable "agent_private_ip" {
  description = "Static private IP for Puppet Agent"
  type        = string
  default     = "10.30.2.10"

  validation {
    condition     = can(cidrhost("${var.agent_private_ip}/32", 0))
    error_message = "agent_private_ip must be a valid IPv4 address."
  }
}

variable "admin_cidr" {
  description = "Administrator public IPv4 address in /32 CIDR format for restricted SSH and Nagios access. Must not be 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid IPv4 CIDR block and must not be 0.0.0.0/0."
  }
}

variable "instance_type" {
  description = "EC2 instance type for master and agent"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Existing AWS EC2 key pair name registered in AWS"
  type        = string
  default     = "devpupAsia"
}

variable "app_port" {
  description = "Host TCP port for the Campus Lost and Found application"
  type        = number
  default     = 5001

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be between 1 and 65535."
  }
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks permitted to access the application port 5001"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_http_cidrs) > 0 && alltrue([for c in var.allowed_http_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_http_cidrs must contain at least one valid IPv4 CIDR block."
  }
}

variable "root_volume_size_gb" {
  description = "Size in GiB of the encrypted GP3 root volume on both EC2 instances"
  type        = number
  default     = 16

  validation {
    condition     = var.root_volume_size_gb >= 8
    error_message = "root_volume_size_gb must be at least 8 GiB."
  }
}

variable "ssm_parameter_name" {
  description = "Path of the SSM Parameter Store SecureString containing the Puppet repository token"
  type        = string
  default     = "/devops/puppet/apt_key"
}
