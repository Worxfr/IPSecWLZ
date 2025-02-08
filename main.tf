# Configure the AWS provider - sets up AWS as the cloud provider with specified region
provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {}
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


module "ipsec_instance" {
  source = "./modules/ipsec-instance"

  vpc_id              = aws_vpc.wavelength_vpc.id
  subnet_id           = aws_subnet.wavelength_subnet.id
  key_pair_name       = var.key_pair_name
  peer_ip            = var.peer_ip
  ipsec_psk          = var.ipsec_psk
  bgp_asn_local      = var.bgp_asn_local
  bgp_asn_remote     = var.bgp_asn_remote
  remote_subnet      = var.remote_subnet
  network_border_group = var.network_border_group
}

