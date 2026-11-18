# IAM Role and Instance Profile for AWS Systems Manager (SSM) Integration
# Enables SSM Session Manager and least-privilege SSM Parameter Store access for EC2 instances.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  ssm_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_name}"
}

resource "aws_iam_role" "ec2_ssm" {
  name        = "${var.project_name}-ec2-ssm-role"
  description = "IAM role enabling SSM management and parameter retrieval for Puppet nodes"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-ssm-role"
    Role = "IAM-Role"
  })
}

# Attach standard AWS managed policy for SSM Session Manager
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped policy for retrieving the Puppet repository credential from SSM Parameter Store
resource "aws_iam_policy" "ssm_parameter_read" {
  name        = "${var.project_name}-ssm-parameter-read"
  description = "Least-privilege policy allowing retrieval of Puppet repository credential"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = local.ssm_parameter_arn
      },
      {
        Sid    = "KMSDecryptSSM"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ssm-parameter-read"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_read" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = aws_iam_policy.ssm_parameter_read.arn
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-instance-profile"
  })
}
