# Cisco C8000V Customer Gateway Variant

This is a second lab option. It does not replace the Linux/strongSwan Customer Gateway.

Use this variant when you want the AWS side to look the same, but the customer
gateway appliance to be Cisco IOS XE:

```text
Cisco C8000V EC2
  GigabitEthernet1: DHCP private IP in public subnet, mapped to Elastic IP
  Loopback10: 172.16.20.1/24 simulated branch LAN
        |
        | IKEv2 / IPsec, two AWS tunnels
        |
AWS Site-to-Site VPN
        |
Transit Gateway VPN attachment
        |
Transit Gateway route table
        |
VPC attachment
        |
App VPC 10.42.0.0/16
```

## Important Notes

- This option is disabled by default.
- You must subscribe to a Cisco Marketplace AMI before AWS can launch it.
- Cisco costs are much higher than the Linux strongSwan option.
- Use a local tfvars file for the AMI ID, SSH source CIDR, key pair, and admin
  password.
- The generated IOS XE Day 0 configuration is also stored as an SSM SecureString
  so you can inspect what Terraform rendered without exposing it as a normal
  Terraform output.

## Files

- `terraform/cisco_cgw.tf`
- `terraform/templates/cisco_cgw_day0_config.tftpl`
- `terraform/cisco-cgw.tfvars.example`

## Run Shape

Copy the example values into your own local file:

```powershell
Copy-Item .\cisco-cgw.tfvars.example .\cisco-cgw.tfvars
```

Edit:

```text
cisco_customer_gateway_ami_id
cisco_customer_gateway_key_name
cisco_customer_gateway_ssh_cidrs
cisco_customer_gateway_admin_password
```

Then plan:

```powershell
terraform plan -var-file .\cisco-cgw.tfvars
```

Apply only when you are ready for Cisco Marketplace, EC2, TGW, VPN, and public
IPv4 hourly charges.

```powershell
terraform apply -var-file .\cisco-cgw.tfvars
```

## What This Demonstrates

- Customer Gateway as a Cisco public Elastic IP.
- Site-to-Site VPN attached to Transit Gateway.
- Two AWS-managed IPsec tunnels.
- BGP over the two tunnel interfaces.
- TGW route propagation from the VPN attachment.
- VPC route to branch CIDR through TGW.
- Cisco Day 0 bootstrap with IOS XE configuration.

## Useful Cisco Checks

```cisco
show ip interface brief
show crypto ikev2 sa
show crypto ipsec sa
show ip bgp summary
show ip route bgp
show run interface Tunnel1
show run interface Tunnel2
```
