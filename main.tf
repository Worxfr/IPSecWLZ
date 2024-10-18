# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
  default     = "eu-west-1"
}

variable "wavelength_subnet_id" {
  description = "The ID of the existing Wavelength Zone subnet"
  type        = string
}


variable "availabilityzone_wavelength" {
  description = "The Availability Zone for the Wavelength Zone subnet"
  type        = string
}

variable "key_pair_name" {
  description = "The name of the EC2 key pair to use"
  type        = string
  default     = "EC2-key-pair"
}

variable "bgp_asn" {
  description = "BGP Autonomous System Number"
  type        = number
  default     = 65000
}

variable "peer_ip" {
  description = "Peer IP"
  type        = string
  default     = "1.1.1.1"
}

variable "peer_asn" {
  description = "Peer  BGP Autonomous System Number"
  type        = number
  default     = 65000
}

# Data source for the existing Wavelength Zone subnet
data "aws_subnet" "wavelength_subnet" {
  id = var.wavelength_subnet_id
}

# Data source to get the latest Amazon Linux 2 AMI
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

data "aws_eip" "existing_eip" {
  id = var.existing_eip_allocation_id
}

# Create a security group for the EC2 instance
resource "aws_security_group" "ipsec_bgp_sg" {
  name        = "ipsec-bgp-sg"
  description = "Security group for IPSec tunnel and BGP EC2 instance"
  vpc_id      = data.aws_subnet.wavelength_subnet.vpc_id

  # Allow inbound IPSec traffic (UDP 500 and 4500)
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

# Create IAM role for Session Manager
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

# Attach the AmazonSSMManagedInstanceCore policy to the role
resource "aws_iam_role_policy_attachment" "session_manager_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.session_manager_role.name
}

# Create an instance profile
resource "aws_iam_instance_profile" "session_manager_profile" {
  name = "SessionManagerProfile"
  role = aws_iam_role.session_manager_role.name
}


# Create an EC2 instance for the IPSec tunnel and BGP
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

#Creation of Elastic IP for Wavelength EC2
resource "aws_eip" "wavelength_ip" {
  network_border_group = var.availabilityzone_wavelength
  instance             = aws_instance.ipsec_bgp_instance.id
  tags = {
    Name = "Wavelength EC2 EIP"
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ipsec_bgp_instance.id
  allocation_id = aws_eip.wavelength_ip.allocation_id
}






