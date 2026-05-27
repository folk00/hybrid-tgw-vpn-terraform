# TGW Site-to-Site VPN Lab

This project can create a real Transit Gateway and real Site-to-Site VPN
connections.

By default it creates no TGW/VPN resources. Add `vpn_sites` to your Terraform
variables to enable the full hybrid connectivity path.

For a safe preview, run the included demo variables file:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
terraform plan -var-file .\vpn.demo.tfvars -out hybrid-demo.tfplan
```

`vpn.demo.tfvars` uses a documentation IP address. It is useful for showing the
resources in a plan, but it should not be applied until the customer gateway
details are replaced with real values.

## Resources Created Per VPN Site

- `aws_customer_gateway`
- `aws_vpn_connection`
- TGW route table association for the VPN attachment
- TGW route table propagation for dynamic BGP VPNs
- TGW static routes for static-route VPNs
- Private VPC route table routes to remote branch CIDRs through the TGW

## Resources Created Once

- `aws_ec2_transit_gateway`
- `aws_ec2_transit_gateway_route_table`
- `aws_ec2_transit_gateway_vpc_attachment`
- TGW route table association and propagation for the app VPC attachment

## Example

Copy the example file:

```powershell
cd "C:\Users\davidgo2\Downloads\New`Project\terraform"
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
vpn_sites = {
  branch01 = {
    customer_gateway_ip = "203.0.113.10"
    bgp_asn             = 65010
    remote_cidrs        = ["10.10.0.0/16"]
    static_routes_only  = false
  }
}
```

Then run:

```powershell
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## Dynamic BGP VPN

Use:

```hcl
static_routes_only = false
```

Terraform will create TGW propagation for the VPN attachment. The customer
gateway must establish BGP over both IPsec tunnels.

## Static Route VPN

Use:

```hcl
static_routes_only = true
remote_cidrs       = ["10.10.0.0/16", "10.20.0.0/16"]
```

Terraform creates TGW static routes toward the VPN attachment. For TGW-attached
VPNs, static routes belong in the Transit Gateway route table, not in the
legacy VPN connection route API.

## Useful Outputs

```powershell
terraform output vpn_tunnels
terraform output -raw api_endpoint
terraform output vpn_customer_gateway_configuration_xml
```

The customer gateway XML output is marked sensitive because it can include
tunnel details.
