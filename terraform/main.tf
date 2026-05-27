locals {
  name_prefix = "${var.project_name}-${var.environment}"

  emulated_cgw_vpn_site = var.enable_emulated_customer_gateway ? {
    (var.emulated_customer_gateway_site_name) = {
      customer_gateway_ip = aws_eip.emulated_cgw[0].public_ip
      bgp_asn             = var.emulated_customer_gateway_bgp_asn
      remote_cidrs        = [var.emulated_customer_gateway_remote_cidr]
      static_routes_only  = true
      tunnel1_inside_cidr = null
      tunnel2_inside_cidr = null
    }
  } : {}

  cisco_cgw_vpn_site = var.enable_cisco_customer_gateway ? {
    (var.cisco_customer_gateway_site_name) = {
      customer_gateway_ip = aws_eip.cisco_cgw[0].public_ip
      bgp_asn             = var.cisco_customer_gateway_bgp_asn
      remote_cidrs        = [var.cisco_customer_gateway_remote_cidr]
      static_routes_only  = false
      tunnel1_inside_cidr = null
      tunnel2_inside_cidr = null
    }
  } : {}

  all_vpn_sites = merge(var.vpn_sites, local.emulated_cgw_vpn_site, local.cisco_cgw_vpn_site)
  enable_tgw    = var.enable_tgw_lab || length(local.all_vpn_sites) > 0

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = "david-gonzalez"
    Purpose     = "ans-c01-hybrid-networking-lab"
  }

  vpn_route_entries = flatten([
    for site_key, site in local.all_vpn_sites : [
      for cidr in site.remote_cidrs : {
        key      = "${site_key}-${replace(replace(cidr, "/", "-"), ".", "-")}"
        site_key = site_key
        cidr     = cidr
      }
    ]
  ])

  vpn_route_map = {
    for route in local.vpn_route_entries : route.key => route
  }

  vpn_static_route_map = {
    for route in local.vpn_route_entries : route.key => route
    if try(local.all_vpn_sites[route.site_key].static_routes_only, false)
  }

  vpn_dynamic_sites = {
    for site_key, site in local.all_vpn_sites : site_key => site
    if !try(site.static_routes_only, false)
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------
# VPC - private networking lab
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Lambda egress for private AWS service access"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "HTTPS egress for AWS service endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-lambda-sg"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-s3-gateway-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${local.name_prefix}-dynamodb-gateway-endpoint"
  }
}

# -----------------------------
# Storage and audit
# -----------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-artifacts-${random_id.suffix.hex}"

  tags = {
    Name = "${local.name_prefix}-artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-demo-artifacts"
    status = "Enabled"

    filter {
      prefix = "tenants/"
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_dynamodb_table" "audit" {
  name         = "${local.name_prefix}-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"
  range_key    = "created_at"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  tags = {
    Name = "${local.name_prefix}-audit"
  }
}

# -----------------------------
# Lambda app package
# -----------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../app/lambda_function.py"
  output_path = "${path.module}/lambda_package.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_app" {
  name = "${local.name_prefix}-lambda-app-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.artifacts.arn}/tenants/*"
      },
      {
        Sid    = "AuditTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.audit.arn
      }
    ]
  })
}

resource "aws_lambda_function" "analyzer" {
  function_name    = "${local.name_prefix}-analyzer"
  role             = aws_iam_role.lambda.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      PROJECT_NAME = var.project_name
      S3_BUCKET    = aws_s3_bucket.artifacts.bucket
      AUDIT_TABLE  = aws_dynamodb_table.audit.name
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.dynamodb,
  ]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.analyzer.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_metric_filter" "risk_score" {
  name           = "${local.name_prefix}-risk-score"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.event = \"analysis_completed\" }"

  metric_transformation {
    name      = "RiskScore"
    namespace = "HybridNetChangeIQ"
    value     = "$.risk_score"
  }
}

# -----------------------------
# API Gateway HTTP API
# -----------------------------
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.analyzer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyzer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# -----------------------------
# Optional observability and TGW scaffolding
# -----------------------------
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/${local.name_prefix}-flow-logs"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${local.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "${local.name_prefix}-vpc-flow-logs-policy"
  role  = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count = var.enable_vpc_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.vpc_flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}

resource "aws_ec2_transit_gateway" "lab" {
  count = local.enable_tgw ? 1 : 0

  description                     = "${local.name_prefix} optional TGW scaffold"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = {
    Name = "${local.name_prefix}-tgw"
  }
}

resource "aws_ec2_transit_gateway_route_table" "core" {
  count = local.enable_tgw ? 1 : 0

  transit_gateway_id = aws_ec2_transit_gateway.lab[0].id

  tags = {
    Name = "${local.name_prefix}-tgw-core-rt"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "app" {
  count = local.enable_tgw ? 1 : 0

  subnet_ids         = aws_subnet.private[*].id
  transit_gateway_id = aws_ec2_transit_gateway.lab[0].id
  vpc_id             = aws_vpc.main.id

  dns_support                                     = "enable"
  ipv6_support                                    = "disable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.name_prefix}-app-vpc-attachment"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "app" {
  count = local.enable_tgw ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.core[0].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "app" {
  count = local.enable_tgw ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.app[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.core[0].id
}

resource "aws_customer_gateway" "site" {
  for_each = local.all_vpn_sites

  bgp_asn    = each.value.bgp_asn
  ip_address = each.value.customer_gateway_ip
  type       = "ipsec.1"

  tags = {
    Name = "${local.name_prefix}-${each.key}-cgw"
  }

  depends_on = [
    aws_eip_association.emulated_cgw
  ]
}

resource "aws_vpn_connection" "site" {
  for_each = local.all_vpn_sites

  transit_gateway_id  = aws_ec2_transit_gateway.lab[0].id
  customer_gateway_id = aws_customer_gateway.site[each.key].id
  type                = "ipsec.1"
  static_routes_only  = try(each.value.static_routes_only, false)
  tunnel1_inside_cidr = try(each.value.tunnel1_inside_cidr, null)
  tunnel2_inside_cidr = try(each.value.tunnel2_inside_cidr, null)

  tags = {
    Name = "${local.name_prefix}-${each.key}-vpn"
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "vpn" {
  for_each = local.all_vpn_sites

  transit_gateway_attachment_id  = aws_vpn_connection.site[each.key].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.core[0].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "vpn_dynamic" {
  for_each = local.vpn_dynamic_sites

  transit_gateway_attachment_id  = aws_vpn_connection.site[each.key].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.core[0].id
}

resource "aws_ec2_transit_gateway_route" "static_vpn" {
  for_each = local.vpn_static_route_map

  destination_cidr_block         = each.value.cidr
  transit_gateway_attachment_id  = aws_vpn_connection.site[each.value.site_key].transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.core[0].id
}

resource "aws_route" "private_to_remote_vpn" {
  for_each = local.vpn_route_map

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = aws_ec2_transit_gateway.lab[0].id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.app
  ]
}
