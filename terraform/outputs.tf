output "api_endpoint" {
  description = "HTTP API endpoint."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "artifacts_bucket" {
  description = "S3 bucket where uploaded artifacts are stored."
  value       = aws_s3_bucket.artifacts.bucket
}

output "audit_table" {
  description = "DynamoDB table used for tenant-scoped audit events."
  value       = aws_dynamodb_table.audit.name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for the analyzer Lambda."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by Lambda."
  value       = aws_subnet.private[*].id
}

output "s3_gateway_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID."
  value       = aws_vpc_endpoint.s3.id
}

output "dynamodb_gateway_endpoint_id" {
  description = "DynamoDB Gateway VPC Endpoint ID."
  value       = aws_vpc_endpoint.dynamodb.id
}

output "transit_gateway_id" {
  description = "Optional TGW ID when enable_tgw_lab is true or vpn_sites is non-empty."
  value       = local.enable_tgw ? aws_ec2_transit_gateway.lab[0].id : null
}

output "tgw_route_table_id" {
  description = "Transit Gateway core route table ID."
  value       = local.enable_tgw ? aws_ec2_transit_gateway_route_table.core[0].id : null
}

output "tgw_vpc_attachment_id" {
  description = "Transit Gateway VPC attachment for the app VPC."
  value       = local.enable_tgw ? aws_ec2_transit_gateway_vpc_attachment.app[0].id : null
}

output "vpn_tunnels" {
  description = "VPN tunnel endpoints and attachment IDs. Preshared keys are intentionally not exposed here."
  value = {
    for site_key, vpn in aws_vpn_connection.site : site_key => {
      vpn_connection_id             = vpn.id
      transit_gateway_attachment_id = vpn.transit_gateway_attachment_id
      customer_gateway_id           = vpn.customer_gateway_id
      tunnel1_address               = vpn.tunnel1_address
      tunnel1_cgw_inside_address    = vpn.tunnel1_cgw_inside_address
      tunnel1_vgw_inside_address    = vpn.tunnel1_vgw_inside_address
      tunnel2_address               = vpn.tunnel2_address
      tunnel2_cgw_inside_address    = vpn.tunnel2_cgw_inside_address
      tunnel2_vgw_inside_address    = vpn.tunnel2_vgw_inside_address
      tunnel1_bgp_asn               = vpn.tunnel1_bgp_asn
      tunnel2_bgp_asn               = vpn.tunnel2_bgp_asn
    }
  }
}

output "vpn_customer_gateway_configuration_xml" {
  description = "Sensitive AWS-generated XML config for customer gateway devices."
  value = {
    for site_key, vpn in aws_vpn_connection.site : site_key => vpn.customer_gateway_configuration
  }
  sensitive = true
}

output "emulated_customer_gateway" {
  description = "Details for the optional AWS-hosted emulated Customer Gateway appliance."
  value = var.enable_emulated_customer_gateway ? {
    instance_id        = aws_instance.emulated_cgw[0].id
    public_ip          = aws_eip.emulated_cgw[0].public_ip
    branch_cidr        = var.emulated_customer_gateway_remote_cidr
    branch_interface   = local.emulated_cgw_branch_ip_cidr
    ssm_parameter_name = local.emulated_cgw_parameter_name
  } : null
}

output "cisco_customer_gateway" {
  description = "Details for the optional Cisco C8000V Customer Gateway appliance."
  value = var.enable_cisco_customer_gateway ? {
    instance_id      = aws_instance.cisco_cgw[0].id
    public_ip        = aws_eip.cisco_cgw[0].public_ip
    branch_cidr      = var.cisco_customer_gateway_remote_cidr
    branch_interface = "${local.cisco_cgw_branch_ip}/${split("/", var.cisco_customer_gateway_remote_cidr)[1]}"
    bgp_asn          = var.cisco_customer_gateway_bgp_asn
    day0_parameter   = aws_ssm_parameter.cisco_cgw_day0_config[0].name
    ssh_hint         = "ssh -i <key.pem> ec2-user@${aws_eip.cisco_cgw[0].public_ip}"
  } : null
}

output "lab_concepts" {
  description = "Concepts demonstrated by this lab."
  value = [
    "VPC private subnets",
    "S3 Gateway Endpoint",
    "DynamoDB Gateway Endpoint",
    "API Gateway to Lambda",
    "Lambda VPC networking",
    "IAM least privilege",
    "CloudWatch logs and metric filters",
    "Optional VPC Flow Logs",
    "Optional Transit Gateway",
    "Optional Site-to-Site VPN with Customer Gateway",
    "TGW VPC attachment, association, propagation, and static route examples",
    "Optional Cisco C8000V Customer Gateway variant with BGP",
  ]
}
