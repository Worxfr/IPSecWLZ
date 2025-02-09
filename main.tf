# Configure the AWS provider - sets up AWS as the cloud provider with specified region
provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {}
}

# VPC for Wavelength Zone deployment
resource "aws_vpc" "region_vpc" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "region-vpc"
  }
}

# Internet Gateway for region VPC
resource "aws_internet_gateway" "region_igw" {
  vpc_id = aws_vpc.region_vpc.id

  tags = {
    Name = "region-internet-gateway"
  }
}


# Region subnet
resource "aws_subnet" "region_subnet" {
  vpc_id            = aws_vpc.region_vpc.id
  cidr_block        = "10.100.1.0/24"
  availability_zone = "${var.aws_region}a"  
  tags = {
    Name = "region-subnet"
  }
}

# Route table for region VPC
resource "aws_route_table" "region_rt" {
  vpc_id = aws_vpc.region_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.region_igw.id
  }

  tags = {
    Name = "region-route-table"
  }
}

# Associate route table with region subnet
resource "aws_route_table_association" "region_rt_assoc" {
  subnet_id      = aws_subnet.region_subnet.id
  route_table_id = aws_route_table.region_rt.id
}

# Create Elastic IP for the region instance
resource "aws_eip" "region_ip" {
  domain = "vpc"
  tags = {
    Name = "Region-Instance-EIP"
  }
}


# VPC for Wavelength Zone deployment
resource "aws_vpc" "wavelength_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wavelength-vpc"
  }
}

# Carrier Gateway for Wavelength Zone
resource "aws_ec2_carrier_gateway" "wavelength_cgw" {
  vpc_id = aws_vpc.wavelength_vpc.id

  tags = {
    Name = "wavelength-carrier-gateway"
  }
}

# Route table for Wavelength subnet
resource "aws_route_table" "wavelength_rt" {
  vpc_id = aws_vpc.wavelength_vpc.id

  route {
    cidr_block         = "0.0.0.0/0"
    carrier_gateway_id = aws_ec2_carrier_gateway.wavelength_cgw.id
  }

  tags = {
    Name = "wavelength-route-table"
  }
}

# Wavelength subnet
resource "aws_subnet" "wavelength_subnet" {
  vpc_id            = aws_vpc.wavelength_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = var.availabilityzone_wavelength

  tags = {
    Name = "wavelength-subnet"
  }
}

# Associate route table with Wavelength subnet
resource "aws_route_table_association" "wavelength_rt_assoc" {
  subnet_id      = aws_subnet.wavelength_subnet.id
  route_table_id = aws_route_table.wavelength_rt.id
}

# Create Elastic IP for the instance
resource "aws_eip" "wavelength_ip" {
  network_border_group = var.network_border_group
  tags = {
    Name = "IPSec-BGP-Instance-EIP"
  }
}




### TEST Multi VPC

# VPC-2 for Wavelength Zone deployment
resource "aws_vpc" "wavelength_vpc_2" {
  cidr_block           = "192.168.0.0/23"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "wavelength-vpc-2"
  }
}

# Wavelength subnet
resource "aws_subnet" "wavelength_subnet_vpc_2" {
  vpc_id            = aws_vpc.wavelength_vpc_2.id
  cidr_block        = "192.168.0.0/24"
  availability_zone = var.availabilityzone_wavelength

  tags = {
    Name = "wavelength-subnet-vpc-2"
  }
}


module "ipsec-wlz"  {
  source = "./modules/ipsec-instance"

  vpc_id              = aws_vpc.wavelength_vpc.id
  subnet_id           = aws_subnet.wavelength_subnet.id
  key_pair_name       = var.key_pair_name
  remote_public_ip   = aws_eip.region_ip.public_ip
  elastic_ip         = aws_eip.wavelength_ip.id
  remote_private_ip  = var.private_ip_2
  local_private_ip   = var.private_ip_1
  ipsec_psk          = var.ipsec_psk
  bgp_asn_local      = var.bgp_asn_local
  bgp_asn_remote     = var.bgp_asn_remote
  is_wlz             = true

  # Multiple secondary VPCs configuration
  secondary_vpcs = [
    {
      vpc_id      = aws_vpc.wavelength_vpc_2.id
      subnet_id   = aws_subnet.wavelength_subnet_vpc_2.id
      description = "Cross-VPC ENI for VPC 1"
      security_group_rules = [
        {
          from_port   = 443
          to_port     = 443
          protocol    = "tcp"
          cidr_blocks = ["10.0.0.0/8"]
        }
      ]
    }
  ]

  depends_on = [ aws_eip.wavelength_ip, aws_eip.region_ip ]
}

module "ipsec-region"  {
  source = "./modules/ipsec-instance"

  vpc_id              = aws_vpc.region_vpc.id
  subnet_id           = aws_subnet.region_subnet.id
  key_pair_name       = var.key_pair_name
  remote_public_ip    = aws_eip.wavelength_ip.carrier_ip 
  elastic_ip         = aws_eip.region_ip.id
  remote_private_ip  = var.private_ip_1
  local_private_ip   = var.private_ip_2
  ipsec_psk          = var.ipsec_psk
  bgp_asn_local      = var.bgp_asn_remote
  bgp_asn_remote     = var.bgp_asn_local

  depends_on = [ aws_eip.region_ip, aws_eip.wavelength_ip ]

}

