# Configure the AWS provider - sets up AWS as the cloud provider with specified region
provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Variable for Wavelength Zone
variable "availabilityzone_wavelength" {
  description = "Availability Zone ID for Wavelength Zone"
  type        = string
}

# Key pair name variable - for EC2 instance SSH access
variable "key_pair_name" {
  description = "The name of the EC2 key pair to use"
  type        = string
  default     = "EC2-key-pair"
}

# BGP ASN variable - for BGP routing configuration
variable "bgp_asn" {
  description = "BGP Autonomous System Number"
  type        = number
  default     = 65000
}

# Peer IP variable - for IPSec tunnel configuration
variable "peer_ip" {
  description = "Peer IP"
  type        = string
  default     = "1.1.1.1"
}

# Peer ASN variable - for BGP routing with peer
variable "peer_asn" {
  description = "Peer  BGP Autonomous System Number"
  type        = number
  default     = 65000
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

# Data source to get latest Ubuntu 22.04 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security group for EC2 instance - controls inbound/outbound traffic
resource "aws_security_group" "ipsec_bgp_sg" {
  name        = "ipsec-bgp-sg"
  description = "Security group for IPSec tunnel and BGP EC2 instance"
  vpc_id      = aws_vpc.wavelength_vpc.id

  # Allow inbound IPSec traffic on UDP 500
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role for AWS Systems Manager Session Manager access
resource "aws_iam_role" "session_manager_role" {
  name = "SessionManagerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach SSM policy to IAM role
resource "aws_iam_role_policy_attachment" "session_manager_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.session_manager_role.name
}

# Create instance profile for EC2 to assume IAM role
resource "aws_iam_instance_profile" "session_manager_profile" {
  name = "SessionManagerProfile"
  role = aws_iam_role.session_manager_role.name
}

# EC2 instance for IPSec tunnel and BGP routing
resource "aws_instance" "ipsec_bgp_instance" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.medium"  # Adjust instance type as needed
  subnet_id     = data.aws_subnet.wavelength_subnet.id
  vpc_security_group_ids = [aws_security_group.ipsec_bgp_sg.id]

  key_name = var.key_pair_name

  iam_instance_profile = aws_iam_instance_profile.session_manager_profile.name

  tags = {
    Name = "IPSec-BGP-Instance"
  }

  # User data script to configure IPSec and BGP
  user_data = <<-EOF
              #!/bin/bash

              # Update package lists and install necessary packages
              apt-get update
              apt-get install -y strongswan libcharon-extra-plugins frr

              # Configure IPsec (StrongSwan)
              cat <<EOT > /etc/ipsec.conf
              config setup
                  charondebug="all"
                  uniqueids=yes

              conn ipsec-tunnel
                  auto=start
                  left=%defaultroute
                  leftsubnet=0.0.0.0/0
                  right=REMOTEIP
                  rightsubnet=0.0.0.0/0
                  ike=aes256-sha256-modp1024!
                  esp=aes256-sha256-modp1024!
                  keyingtries=0
                  ikelifetime=1h
                  lifetime=8h
                  dpddelay=30
                  dpdtimeout=120
                  dpdaction=restart
                  mark=100
                  vti-interface=vti0
                  vti-routing=no
                  leftvti=169.254.0.1/30
                  rightvti=169.254.0.2/30
              EOT

              sed -i s/REMOTEIP/$REMOTEIP/g /etc/ipsec.conf

              # Configure VTI interface
              cat <<EOT > /etc/systemd/network/vti0.netdev
              [NetDev]
              Name=vti0
              Kind=vti
              EOT

              cat <<EOT > /etc/systemd/network/vti0.network
              [Match]
              Name=vti0

              [Network]
              Address=169.254.0.1/30
              IPMasquerade=yes
              EOT

              # Enable and start IPsec service
              systemctl enable strongswan
              systemctl start strongswan

              # Configure FRRouting (BGP)
              cat <<EOT > /etc/frr/daemons
              bgpd=yes
              EOT

              cat <<EOT > /etc/frr/frr.conf
              frr version 8.1
              frr defaults traditional
              hostname ipsec-bgp-router
              log syslog informational
              service integrated-vtysh-config
              !
              router bgp ${var.bgp_asn}
              neighbor 169.254.0.2 remote-as ${var.peer_asn}
              !
              address-family ipv4 unicast
                network 10.0.0.0/8
                neighbor 169.254.0.2 activate
              exit-address-family
              !
              line vty
              !
              EOT

              # Enable and start FRRouting service
              systemctl enable frr
              systemctl start frr

              # Reboot the instance to apply changes
              reboot

              EOF

              
  depends_on = [  ]
}

# Create Elastic IP for Wavelength EC2 instance
resource "aws_eip" "wavelength_ip" {
  network_border_group = var.availabilityzone_wavelength
  instance             = aws_instance.ipsec_bgp_instance.id
  tags = {
    Name = "Wavelength EC2 EIP"
  }
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ipsec_bgp_instance.id
  allocation_id = aws_eip.wavelength_ip.allocation_id
}






