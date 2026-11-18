resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
    Role = "Network"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
    Role = "Internet-Gateway"
  })
}

resource "aws_subnet" "master" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.master_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_master

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-master-subnet"
    Tier = "public"
    Role = "puppet-master-subnet"
  })
}

resource "aws_subnet" "agent" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.agent_subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone_agent

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-agent-subnet"
    Tier = "public"
    Role = "puppet-agent-subnet"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
    Role = "public-routing"
  })
}

resource "aws_route_table_association" "master" {
  subnet_id      = aws_subnet.master.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "agent" {
  subnet_id      = aws_subnet.agent.id
  route_table_id = aws_route_table.public.id
}
