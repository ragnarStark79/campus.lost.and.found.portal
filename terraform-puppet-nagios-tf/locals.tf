locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Course      = "INT333"
    ManagedBy   = "Terraform"
  }
  master_hostname = "puppet-master"
  agent_hostname  = "puppet-agent"
}
