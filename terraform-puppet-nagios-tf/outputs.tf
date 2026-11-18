# Terraform Outputs for Campus Lost and Found AWS Infrastructure

output "vpc_id" {
  description = "ID of the provisioned custom VPC"
  value       = aws_vpc.main.id
}

output "master_subnet_id" {
  description = "ID of the Puppet Master subnet"
  value       = aws_subnet.master.id
}

output "agent_subnet_id" {
  description = "ID of the Puppet Agent subnet"
  value       = aws_subnet.agent.id
}

output "master_instance_id" {
  description = "EC2 Instance ID of the Puppet Master node"
  value       = aws_instance.master.id
}

output "agent_instance_id" {
  description = "EC2 Instance ID of the Puppet Agent node"
  value       = aws_instance.agent.id
}

output "master_public_ip" {
  description = "Public IPv4 address of the Puppet Master node"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Static private IPv4 address of the Puppet Master node"
  value       = aws_instance.master.private_ip
}

output "agent_public_ip" {
  description = "Public IPv4 address of the Puppet Agent node"
  value       = aws_instance.agent.public_ip
}

output "agent_private_ip" {
  description = "Static private IPv4 address of the Puppet Agent node"
  value       = aws_instance.agent.private_ip
}

output "master_security_group_id" {
  description = "Security group ID for Puppet Master"
  value       = aws_security_group.master.id
}

output "agent_security_group_id" {
  description = "Security group ID for Puppet Agent"
  value       = aws_security_group.agent.id
}

output "nagios_web_url" {
  description = "Nagios Core web monitoring dashboard URL"
  value       = "http://${aws_instance.master.public_ip}/nagios4/"
}

output "application_url" {
  description = "Campus Lost and Found web portal URL"
  value       = "http://${aws_instance.agent.public_ip}:${var.app_port}/"
}

output "ssh_command_master" {
  description = "Command to SSH connect into the Puppet Master instance"
  value       = "ssh -i ~/Downloads/${var.key_name}.pem ubuntu@${aws_instance.master.public_ip}"
}

output "ssh_command_agent" {
  description = "Command to SSH connect into the Puppet Agent instance"
  value       = "ssh -i ~/Downloads/${var.key_name}.pem ubuntu@${aws_instance.agent.public_ip}"
}
