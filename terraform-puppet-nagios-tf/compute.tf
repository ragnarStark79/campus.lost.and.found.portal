# EC2 Instances
# Provisions puppet-master and puppet-agent on Ubuntu 24.04 LTS (Noble)
# Both instances use 16 GiB encrypted GP3 root volumes (32 GiB total storage).

resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.master.id
  private_ip                  = var.master_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.master.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-master-root"
      Role = "root-volume"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforcement
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/bootstrap/master-bootstrap.sh", {
    master_private_ip  = var.master_private_ip
    agent_private_ip   = var.agent_private_ip
    master_hostname    = local.master_hostname
    agent_hostname     = local.agent_hostname
    admin_cidr         = var.admin_cidr
    aws_region         = var.aws_region
    ssm_parameter_name = var.ssm_parameter_name
  })

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-master"
    Role     = "puppet-master"
    Hostname = local.master_hostname
  })
}

resource "aws_instance" "agent" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.agent.id
  private_ip                  = var.agent_private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.agent.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-agent-root"
      Role = "root-volume"
    })
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforcement
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/bootstrap/agent-bootstrap.sh", {
    master_private_ip  = var.master_private_ip
    agent_private_ip   = var.agent_private_ip
    master_hostname    = local.master_hostname
    agent_hostname     = local.agent_hostname
    aws_region         = var.aws_region
    ssm_parameter_name = var.ssm_parameter_name
  })

  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name     = "${var.project_name}-agent"
    Role     = "puppet-agent"
    Hostname = local.agent_hostname
  })
}
