# MOP - Add SD-WAN Branch To AWS Hybrid Network

Tenant: healthcare-co

## Change

Add a new SD-WAN branch and advertise prefixes into AWS through TGW VPN.
Customer gateway IP is <IP_TO_REPLACE>.

## Steps

1. Create VPN attachment.
2. Add route table entry 0.0.0.0/0 toward Internet Gateway.
3. Update BGP neighbor.
4. Push SD-WAN template.
5. Confirm user traffic.

## Notes

- IPsec tunnel will be created.
- Terraform code will be updated.
- No CloudWatch requirement has been documented yet.
