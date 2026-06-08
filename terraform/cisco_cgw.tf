locals {
  cisco_cgw_day0_parameter_name = "/${var.project_name}/${var.environment}/cisco-cgw/day0-config"
  cisco_cgw_branch_ip           = cidrhost(var.cisco_customer_gateway_remote_cidr, 1)
  cisco_cgw_branch_mask         = cidrnetmask(var.cisco_customer_gateway_remote_cidr)
  cisco_cgw_branch_network      = cidrhost(var.cisco_customer_gateway_remote_cidr, 0)
}

resource "aws_vpc" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  cidr_block           = var.cisco_customer_gateway_management_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-vpc"
  }
}

resource "aws_internet_gateway" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  vpc_id = aws_vpc.cisco_cgw[0].id

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-igw"
  }
}

resource "aws_subnet" "cisco_cgw_public" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  vpc_id                  = aws_vpc.cisco_cgw[0].id
  cidr_block              = var.cisco_customer_gateway_public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-public"
    Tier = "public"
  }
}

resource "aws_route_table" "cisco_cgw_public" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  vpc_id = aws_vpc.cisco_cgw[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cisco_cgw[0].id
  }

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-public-rt"
  }
}

resource "aws_route_table_association" "cisco_cgw_public" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  subnet_id      = aws_subnet.cisco_cgw_public[0].id
  route_table_id = aws_route_table.cisco_cgw_public[0].id
}

resource "aws_security_group" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  name        = "${local.name_prefix}-cisco-cgw-sg"
  description = "Cisco C8000V IPsec and SSH access"
  vpc_id      = aws_vpc.cisco_cgw[0].id

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
    for_each = length(var.cisco_customer_gateway_ssh_cidrs) > 0 ? [1] : []

    content {
      description = "SSH management"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.cisco_customer_gateway_ssh_cidrs
    }
  }

  egress {
    description = "Outbound internet and VPN initiation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-sg"
  }
}

resource "aws_eip" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-eip"
  }
}

resource "aws_instance" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  ami                         = var.cisco_customer_gateway_ami_id
  instance_type               = var.cisco_customer_gateway_instance_type
  subnet_id                   = aws_subnet.cisco_cgw_public[0].id
  vpc_security_group_ids      = [aws_security_group.cisco_cgw[0].id]
  key_name                    = var.cisco_customer_gateway_key_name
  associate_public_ip_address = true
  source_dest_check           = false
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/cisco_cgw_day0_config.tftpl", {
    hostname                   = "${local.name_prefix}-c8000v"
    admin_username             = var.cisco_customer_gateway_admin_username
    admin_password             = var.cisco_customer_gateway_admin_password
    branch_ip                  = local.cisco_cgw_branch_ip
    branch_mask                = local.cisco_cgw_branch_mask
    branch_network             = local.cisco_cgw_branch_network
    customer_gateway_ip        = aws_eip.cisco_cgw[0].public_ip
    bgp_asn                    = var.cisco_customer_gateway_bgp_asn
    tunnel1_address            = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_address
    tunnel1_cgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_cgw_inside_address
    tunnel1_vgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_vgw_inside_address
    tunnel1_inside_netmask     = cidrnetmask(aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_inside_cidr)
    tunnel1_preshared_key      = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_preshared_key
    tunnel1_aws_bgp_asn        = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_bgp_asn
    tunnel2_address            = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_address
    tunnel2_cgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_cgw_inside_address
    tunnel2_vgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_vgw_inside_address
    tunnel2_inside_netmask     = cidrnetmask(aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_inside_cidr)
    tunnel2_preshared_key      = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_preshared_key
    tunnel2_aws_bgp_asn        = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_bgp_asn
    remote_aws_vpc_cidr        = var.vpc_cidr
  })

  tags = {
    Name = "${local.name_prefix}-cisco-cgw"
    Role = "cisco-customer-gateway-appliance"
  }
}

resource "aws_eip_association" "cisco_cgw" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  allocation_id = aws_eip.cisco_cgw[0].id
  instance_id   = aws_instance.cisco_cgw[0].id
}

resource "aws_ssm_parameter" "cisco_cgw_day0_config" {
  count = var.enable_cisco_customer_gateway ? 1 : 0

  name        = local.cisco_cgw_day0_parameter_name
  description = "Generated Cisco IOS XE Day 0 configuration for the C8000V Customer Gateway lab."
  type        = "SecureString"
  value = templatefile("${path.module}/templates/cisco_cgw_day0_config.tftpl", {
    hostname                   = "${local.name_prefix}-c8000v"
    admin_username             = var.cisco_customer_gateway_admin_username
    admin_password             = var.cisco_customer_gateway_admin_password
    branch_ip                  = local.cisco_cgw_branch_ip
    branch_mask                = local.cisco_cgw_branch_mask
    branch_network             = local.cisco_cgw_branch_network
    customer_gateway_ip        = aws_eip.cisco_cgw[0].public_ip
    bgp_asn                    = var.cisco_customer_gateway_bgp_asn
    tunnel1_address            = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_address
    tunnel1_cgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_cgw_inside_address
    tunnel1_vgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_vgw_inside_address
    tunnel1_inside_netmask     = cidrnetmask(aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_inside_cidr)
    tunnel1_preshared_key      = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_preshared_key
    tunnel1_aws_bgp_asn        = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel1_bgp_asn
    tunnel2_address            = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_address
    tunnel2_cgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_cgw_inside_address
    tunnel2_vgw_inside_address = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_vgw_inside_address
    tunnel2_inside_netmask     = cidrnetmask(aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_inside_cidr)
    tunnel2_preshared_key      = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_preshared_key
    tunnel2_aws_bgp_asn        = aws_vpn_connection.site[var.cisco_customer_gateway_site_name].tunnel2_bgp_asn
    remote_aws_vpc_cidr        = var.vpc_cidr
  })

  tags = {
    Name = "${local.name_prefix}-cisco-cgw-day0-config"
  }
}
