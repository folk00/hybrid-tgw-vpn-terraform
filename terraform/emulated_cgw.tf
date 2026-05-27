locals {
  emulated_cgw_parameter_name = "/${var.project_name}/${var.environment}/emulated-cgw/config"
  emulated_cgw_branch_ip      = cidrhost(var.emulated_customer_gateway_remote_cidr, 1)
  emulated_cgw_branch_ip_cidr = "${local.emulated_cgw_branch_ip}/${split("/", var.emulated_customer_gateway_remote_cidr)[1]}"
}

data "aws_ami" "emulated_cgw_ubuntu" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  cidr_block           = var.emulated_customer_gateway_management_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-vpc"
  }
}

resource "aws_internet_gateway" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  vpc_id = aws_vpc.emulated_cgw[0].id

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-igw"
  }
}

resource "aws_subnet" "emulated_cgw_public" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  vpc_id                  = aws_vpc.emulated_cgw[0].id
  cidr_block              = var.emulated_customer_gateway_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-public"
    Tier = "public"
  }
}

resource "aws_route_table" "emulated_cgw_public" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  vpc_id = aws_vpc.emulated_cgw[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.emulated_cgw[0].id
  }

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-public-rt"
  }
}

resource "aws_route_table_association" "emulated_cgw_public" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  subnet_id      = aws_subnet.emulated_cgw_public[0].id
  route_table_id = aws_route_table.emulated_cgw_public[0].id
}

resource "aws_security_group" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  name        = "${local.name_prefix}-emulated-cgw-sg"
  description = "IPsec and optional SSH for the emulated Customer Gateway"
  vpc_id      = aws_vpc.emulated_cgw[0].id

  ingress {
    description = "IKE"
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "IPsec NAT-T"
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = length(var.emulated_customer_gateway_ssh_cidrs) > 0 ? [1] : []

    content {
      description = "Optional SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.emulated_customer_gateway_ssh_cidrs
    }
  }

  egress {
    description = "Outbound internet and AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-sg"
  }
}

resource "aws_iam_role" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  name = "${local.name_prefix}-emulated-cgw-role"

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
}

resource "aws_iam_role_policy_attachment" "emulated_cgw_ssm" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  role       = aws_iam_role.emulated_cgw[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  name = "${local.name_prefix}-emulated-cgw-profile"
  role = aws_iam_role.emulated_cgw[0].name
}

resource "aws_eip" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-eip"
  }
}

resource "aws_instance" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  ami                         = data.aws_ami.emulated_cgw_ubuntu[0].id
  instance_type               = var.emulated_customer_gateway_instance_type
  subnet_id                   = aws_subnet.emulated_cgw_public[0].id
  vpc_security_group_ids      = [aws_security_group.emulated_cgw[0].id]
  iam_instance_profile        = aws_iam_instance_profile.emulated_cgw[0].name
  key_name                    = var.emulated_customer_gateway_key_name
  associate_public_ip_address = true
  source_dest_check           = false

  user_data = templatefile("${path.module}/templates/emulated_cgw_bootstrap.sh.tftpl", {
    aws_region     = var.aws_region
    parameter_name = local.emulated_cgw_parameter_name
  })

  tags = {
    Name = "${local.name_prefix}-emulated-cgw"
    Role = "customer-gateway-appliance"
  }

  depends_on = [
    aws_iam_role_policy_attachment.emulated_cgw_ssm
  ]
}

resource "aws_eip_association" "emulated_cgw" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  allocation_id = aws_eip.emulated_cgw[0].id
  instance_id   = aws_instance.emulated_cgw[0].id
}

resource "aws_ssm_parameter" "emulated_cgw_config" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  name        = local.emulated_cgw_parameter_name
  description = "Generated strongSwan config for the emulated Customer Gateway lab appliance."
  type        = "SecureString"
  value = templatefile("${path.module}/templates/emulated_cgw_config.sh.tftpl", {
    branch_ip_cidr        = local.emulated_cgw_branch_ip_cidr
    customer_gateway_ip   = aws_eip.emulated_cgw[0].public_ip
    local_branch_cidr     = var.emulated_customer_gateway_remote_cidr
    remote_aws_vpc_cidr   = var.vpc_cidr
    tunnel1_address       = aws_vpn_connection.site[var.emulated_customer_gateway_site_name].tunnel1_address
    tunnel1_preshared_key = aws_vpn_connection.site[var.emulated_customer_gateway_site_name].tunnel1_preshared_key
    tunnel2_address       = aws_vpn_connection.site[var.emulated_customer_gateway_site_name].tunnel2_address
    tunnel2_preshared_key = aws_vpn_connection.site[var.emulated_customer_gateway_site_name].tunnel2_preshared_key
  })

  tags = {
    Name = "${local.name_prefix}-emulated-cgw-config"
  }
}

resource "aws_iam_role_policy" "emulated_cgw_config_reader" {
  count = var.enable_emulated_customer_gateway ? 1 : 0

  name = "${local.name_prefix}-emulated-cgw-config-reader"
  role = aws_iam_role.emulated_cgw[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = aws_ssm_parameter.emulated_cgw_config[0].arn
      }
    ]
  })
}
