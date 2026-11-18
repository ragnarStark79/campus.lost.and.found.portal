# Security Groups and Ingress/Egress Rules
# Least-privilege firewall rules for Master and Agent instances.

resource "aws_security_group" "master" {
  name        = "${var.project_name}-master-sg"
  description = "Security group for Puppet Master and Nagios Server"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Outbound access for packages and updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-master-sg"
    Role = "master-security"
  })
}

resource "aws_security_group" "agent" {
  name        = "${var.project_name}-agent-sg"
  description = "Security group for Puppet Agent and Docker App Host"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Outbound access for container images, Docker repos, and packages"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-agent-sg"
    Role = "agent-security"
  })
}

# ── Master Ingress Rules ─────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "master_ssh" {
  security_group_id = aws_security_group.master.id
  description       = "SSH administrative access from trusted admin CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "master_http" {
  security_group_id = aws_security_group.master.id
  description       = "Nagios Core web dashboard access from trusted admin CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "master_puppet" {
  security_group_id            = aws_security_group.master.id
  description                  = "Puppet Server communication strictly from Puppet Agent SG"
  referenced_security_group_id = aws_security_group.agent.id
  from_port                    = 8140
  to_port                      = 8140
  ip_protocol                  = "tcp"
}

# ── Agent Ingress Rules ──────────────────────────────────────────────────────

resource "aws_vpc_security_group_ingress_rule" "agent_ssh" {
  security_group_id = aws_security_group.agent.id
  description       = "SSH administrative access from trusted admin CIDR"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "agent_app" {
  for_each          = toset(var.allowed_http_cidrs)
  security_group_id = aws_security_group.agent.id
  description       = "Campus Lost and Found application traffic on port 5001"
  cidr_ipv4         = each.value
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "agent_http_check" {
  security_group_id            = aws_security_group.agent.id
  description                  = "HTTP port 80 check strictly from Nagios Master"
  referenced_security_group_id = aws_security_group.master.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "agent_nrpe" {
  security_group_id            = aws_security_group.agent.id
  description                  = "NRPE metrics monitoring strictly from Nagios Master"
  referenced_security_group_id = aws_security_group.master.id
  from_port                    = 5666
  to_port                      = 5666
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "agent_icmp" {
  security_group_id            = aws_security_group.agent.id
  description                  = "ICMP echo (PING) check strictly from Nagios Master"
  referenced_security_group_id = aws_security_group.master.id
  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "icmp"
}
