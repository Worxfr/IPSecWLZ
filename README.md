# AWS Wavelength IPSec BGP Infrastructure

### Temporary README

## [!CAUTION] Important Disclaimer

**This project is for testing and demonstration purposes only.**

Please be aware of the following:

- The infrastructure deployed by this project is not intended for production use.
- Security measures may not be comprehensive or up to date.
- Performance and reliability have not been thoroughly tested at scale.
- The project may not comply with all best practices or organizational standards.

Before using any part of this project in a production environment:

1. Thoroughly review and understand all code and configurations.
2. Conduct a comprehensive security audit.
3. Test extensively in a safe, isolated environment.
4. Adapt and modify the code to meet your specific requirements and security standards.
5. Ensure compliance with your organization's policies and any relevant regulations.

The maintainers of this project are not responsible for any issues that may arise from the use of this code in production environments.

---

## Overview
# AWS Wavelength IPSec BGP Infrastructure

## Overview
This Terraform project deploys a VPN infrastructure in AWS Wavelength Zones that enables direct VPN termination at the edge of the 5G network, eliminating the need for traffic to traverse back to the parent AWS Region. This architecture significantly reduces latency for edge computing applications by:

1. Terminating VPN connections directly within the Wavelength Zone
2. Enabling direct connectivity between on-premises networks and edge applications
3. Supporting BGP routing for dynamic network path optimization

The solution addresses common challenges in edge computing scenarios where:
- Traditional VPN connections to the AWS Region would introduce unnecessary latency
- Applications require ultra-low latency connectivity from on-premises networks
- Direct connection to mobile network operator (MNO) infrastructure is needed
- Local breakout for edge traffic is essential for performance

Key architectural benefits:
- Direct VPN termination in Wavelength Zone
- Local traffic processing without regional backhaul
- Reduced network latency for edge applications
- Optimized data path for 5G and edge computing use cases
- Support for both static and dynamic routing using BGP

The infrastructure includes:
- A VPC with Wavelength Zone extension
- Carrier gateway for mobile network connectivity
- EC2-based VPN endpoint in the Wavelength Zone
- IPSec tunneling with BGP routing capabilities
- Automated deployment using Terraform

This architecture is particularly suitable for:
- Industrial IoT applications
- Real-time video processing
- Mobile gaming infrastructure
- Edge AI/ML workloads
- Connected vehicle applications

The solution deploys all necessary components including VPC, carrier gateway, subnet configurations, and an EC2 instance pre-configured with IPSec and BGP for secure, high-performance edge connectivity.

## Prerequisites
- AWS Account with Wavelength Zone access
- Terraform installed (version 0.12 or later)
- AWS CLI configured with appropriate credentials
- EC2 key pair for SSH access
- Access to AWS Wavelength Zones

## Features
- AWS Wavelength Zone VPC deployment
- Carrier Gateway configuration
- IPSec VPN tunnel setup
- BGP routing configuration
- Automated EC2 instance provisioning with Ubuntu 22.04
- Systems Manager Session Manager integration
- Security group configuration for IPSec traffic

## Infrastructure Components
- VPC with DNS support
- Carrier Gateway
- Wavelength Zone subnet
- Route tables and associations
- EC2 instance with IPSec/BGP configuration
- IAM roles and policies for Systems Manager
- Security groups for network traffic control
- Elastic IP association

## Variables
| Name | Description | Type | Default |
|------|-------------|------|---------|
| aws_region | AWS region for deployment | string | us-east-1 |
| availabilityzone_wavelength | Wavelength Zone ID | string | required |
| key_pair_name | EC2 key pair name | string | EC2-key-pair |
| bgp_asn | BGP Autonomous System Number | number | 65000 |
| peer_ip | IPSec peer IP address | string | 1.1.1.1 |
| peer_asn | Peer BGP ASN | number | 65000 |

## Usage
1. Clone the repository
2. Initialize Terraform:
```bash
terraform init
```
3. Configure your variables in a terraform.tfvars file:
```
aws_region = "us-east-1"
availabilityzone_wavelength = "us-east-1-wl1-bos-wlz-1"
key_pair_name = "your-key-pair"
bgp_asn = 65000
peer_ip = "your-peer-ip"
peer_asn = 65000
```
4. Review the execution plan:
```
terraform plan
```
5. Apply the configuration :
```
terraform apply
```

## Network Configuration
- VPC CIDR: 10.0.0.0/16
- Subnet CIDR: 10.0.1.0/24
- IPSec VTI Interface: 169.254.0.1/30

## Security
- EC2 instance accessible via Systems Manager Session Manager
- Security group configured for IPSec traffic (UDP 500)
- IAM roles with least privilege principle
- Encrypted VPN tunnel for secure communication

## Monitoring and Management
- Systems Manager Session Manager for secure instance access
- CloudWatch integration for logging
- FRRouting for BGP management

## Clean Up
To destroy the infrastructure:
```
terraform destroy
```

## Notes
- Ensure proper AWS credentials and permissions before deployment
- Review and adjust security group rules based on requirements
- Backup Terraform state files
- Monitor costs associated with Wavelength Zone usage

## Contributing
1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file included in this repository.