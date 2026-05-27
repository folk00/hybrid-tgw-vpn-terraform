variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "hybridnet-ansc01-lab"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the isolated application VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Two private subnet CIDRs."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.20.0/24"]
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "enable_tgw_lab" {
  description = "Create optional Transit Gateway scaffold. Also enabled automatically when vpn_sites is non-empty."
  type        = bool
  default     = false
}

variable "vpn_sites" {
  description = "Real Site-to-Site VPN sites to attach to the Transit Gateway. Leave empty to avoid VPN/TGW cost."
  type = map(object({
    customer_gateway_ip = string
    bgp_asn             = number
    remote_cidrs        = list(string)
    static_routes_only  = optional(bool, false)
    tunnel1_inside_cidr = optional(string)
    tunnel2_inside_cidr = optional(string)
  }))
  default = {}
}

variable "enable_emulated_customer_gateway" {
  description = "Create an AWS-hosted virtual branch router and use its Elastic IP as a Customer Gateway. This creates EC2/EIP/TGW/VPN resources."
  type        = bool
  default     = false
}

variable "emulated_customer_gateway_site_name" {
  description = "Site key used for the optional emulated Customer Gateway."
  type        = string
  default     = "emulated_branch"
}

variable "emulated_customer_gateway_bgp_asn" {
  description = "ASN assigned to the optional emulated Customer Gateway. Static VPN mode is used initially, but AWS still requires a CGW ASN."
  type        = number
  default     = 65010
}

variable "emulated_customer_gateway_remote_cidr" {
  description = "Dummy branch LAN CIDR announced behind the optional emulated Customer Gateway."
  type        = string
  default     = "172.16.10.0/24"
}

variable "emulated_customer_gateway_management_cidr" {
  description = "Management VPC CIDR for the optional emulated Customer Gateway appliance."
  type        = string
  default     = "10.250.0.0/24"
}

variable "emulated_customer_gateway_public_subnet_cidr" {
  description = "Public subnet CIDR for the optional emulated Customer Gateway appliance."
  type        = string
  default     = "10.250.0.0/28"
}

variable "emulated_customer_gateway_instance_type" {
  description = "EC2 instance type for the optional emulated Customer Gateway appliance."
  type        = string
  default     = "t3.micro"
}

variable "emulated_customer_gateway_key_name" {
  description = "Optional EC2 key pair name for SSH. Leave null and use SSM Session Manager."
  type        = string
  default     = null
}

variable "emulated_customer_gateway_ssh_cidrs" {
  description = "Optional CIDRs allowed to SSH to the emulated Customer Gateway. Empty by default; use SSM instead."
  type        = list(string)
  default     = []
}

variable "enable_cisco_customer_gateway" {
  description = "Create an optional Cisco C8000V Customer Gateway variant. Disabled by default to avoid Cisco Marketplace and EC2 cost."
  type        = bool
  default     = false
}

variable "cisco_customer_gateway_site_name" {
  description = "Site key used for the optional Cisco C8000V Customer Gateway."
  type        = string
  default     = "cisco_branch"
}

variable "cisco_customer_gateway_ami_id" {
  description = "Cisco C8000V/CSR1000V AMI ID from AWS Marketplace. Required when enable_cisco_customer_gateway is true."
  type        = string
  default     = null
}

variable "cisco_customer_gateway_bgp_asn" {
  description = "Private ASN used by the Cisco Customer Gateway for BGP over the AWS VPN tunnels."
  type        = number
  default     = 65020
}

variable "cisco_customer_gateway_remote_cidr" {
  description = "Branch LAN CIDR advertised by the optional Cisco Customer Gateway."
  type        = string
  default     = "172.16.20.0/24"
}

variable "cisco_customer_gateway_management_cidr" {
  description = "Management VPC CIDR for the optional Cisco Customer Gateway."
  type        = string
  default     = "10.251.0.0/24"
}

variable "cisco_customer_gateway_public_subnet_cidr" {
  description = "Public subnet CIDR for the optional Cisco Customer Gateway outside interface."
  type        = string
  default     = "10.251.0.0/28"
}

variable "cisco_customer_gateway_instance_type" {
  description = "EC2 instance type for the optional Cisco Customer Gateway."
  type        = string
  default     = "c5.large"
}

variable "cisco_customer_gateway_key_name" {
  description = "Optional EC2 key pair name for SSH to the Cisco instance."
  type        = string
  default     = null
}

variable "cisco_customer_gateway_ssh_cidrs" {
  description = "CIDRs allowed to SSH to the Cisco Customer Gateway."
  type        = list(string)
  default     = []
}

variable "cisco_customer_gateway_admin_username" {
  description = "Local IOS XE admin username created by the Cisco Day 0 configuration."
  type        = string
  default     = "labadmin"
}

variable "cisco_customer_gateway_admin_password" {
  description = "Local IOS XE admin password created by the Cisco Day 0 configuration. Set this in a local tfvars file."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_vpc_flow_logs" {
  description = "Create VPC Flow Logs to CloudWatch. Disabled by default to avoid extra cost."
  type        = bool
  default     = false
}
