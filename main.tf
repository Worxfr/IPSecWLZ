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

  ingress {
    from_port   = 4500
    to_port     = 4500
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
  subnet_id     = aws_subnet.wavelength_subnet.id
  vpc_security_group_ids = [aws_security_group.ipsec_bgp_sg.id]

  key_name = var.key_pair_name
  user_data_replace_on_change = true

  source_dest_check = false

  iam_instance_profile = aws_iam_instance_profile.session_manager_profile.name

  tags = {
    Name = "IPSec-BGP-Instance"
  }

  # User data script to configure IPSec and BGPtopq
user_data = <<EOF
#!/bin/bash
set -e

# Update and install required packages
sleep 10
while pgrep -f "apt|dpkg" > /dev/null; do
    echo "Waiting for other package manager processes to finish..."
    sleep 10
done
apt-get update -y
while pgrep -f "apt|dpkg" > /dev/null; do
    echo "Waiting for other package manager processes to finish..."
    sleep 10
done
apt-get install -y strongswan libcharon-extra-plugins frr iproute2
touch /tmp/ETAPE1

# StrongSwan Configuration
cat <<EOT > /etc/ipsec.conf
config setup
  charondebug="ike 1, knl 1, cfg 0"
conn ikev2-vti
  auto=start
  compress=no
  type=tunnel
  keyexchange=ikev2
  fragmentation=yes
  forceencaps=yes
  ike=aes256-sha256-modp2048
  esp=aes256-sha256-modp2048
  left=%defaultroute
  leftid=@PUBLICLOCAL  # Fix: Use self.public_ip instead of empty leftid
  leftsubnet=0.0.0.0/0
  right=${var.peer_ip}
  rightid=%any
  rightsubnet=0.0.0.0/0
  authby=secret
  mark=42
  vti-interface=vti100
  vti-routing=no
  leftvti=172.16.0.1/30
  rightvti=172.16.0.2/30
  leftupdown=/etc/strongswan.d/ipsec-vti.sh
EOT

touch /tmp/ETAPE2

# Shared key configuration
echo ": PSK \"${var.ipsec_psk}\"" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets  # Add: Secure the secrets file

touch /tmp/ETAPE3

# VTI interface configuration
cat <<EOT > /etc/strongswan.d/ipsec-vti.sh
#!/bin/bash
sudo ip link add vti100 type vti local PRIVATELOCAL remote ${var.peer_ip} key 42
sudo ip addr add 172.16.0.1/30 remote 172.16.0.2/30 dev vti100
sudo ip link set vti100 up mtu 1419
sudo iptables -t mangle -A FORWARD -o vti100 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
sudo iptables -t mangle -A INPUT -p esp -s PRIVATELOCAL -d ${var.peer_ip} -j MARK --set-xmark 42
sudo ip route flush table 220
EOT

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ipsecconfig.conf  # Fix: Use sysctl.d instead of direct file
echo "net.ipv4.conf.vti100.disable_policy=1" >> /etc/sysctl.d/99-ipsecconfig.conf  # Fix: Use sysctl.d instead of direct file
echo "net.ipv4.conf.vti100.rp_filter=2" >> /etc/sysctl.d/99-ipsecconfig.conf  # Fix: Use sysctl.d instead of direct file
echo "net.ipv4.conf.ens5.disable_xfrm=1" >> /etc/sysctl.d/99-ipsecconfig.conf  # Fix: Use sysctl.d instead of direct file
echo "net.ipv4.conf.ens5.disable_policy=1" >> /etc/sysctl.d/99-ipsecconfig.conf  # Fix: Use sysctl.d instead of direct file
sysctl --system  # Fix: Use --system to load all configurations

# FRR Configuration for BGP
sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

cat << EOT > /etc/frr/frr.conf
frr version 8.1
frr defaults traditional
hostname vpn-router
log syslog informational
service integrated-vtysh-config
!
router bgp ${var.bgp_asn_local}
bgp router-id 172.16.0.1
neighbor 172.16.0.2 remote-as ${var.bgp_asn_remote}
neighbor 172.16.0.2 timers 10 30  # Add: BGP timers for better reliability
!
address-family ipv4 unicast
  neighbor 172.16.0.2 activate
  neighbor 172.16.0.2 soft-reconfiguration inbound  # Add: Soft reconfiguration for easier troubleshooting
  redistribute static
  redistribute connect
  neighbor 172.16.0.2 route-map ALLOW_RFC1918 in
    neighbor 172.16.0.2 route-map ALLOW_RFC1918 out
exit-address-family
exit
!
ip prefix-list RFC1918_RANGES seq 5 permit 10.0.0.0/8 ge 8 le 32
ip prefix-list RFC1918_RANGES seq 10 permit 172.16.0.0/12 ge 12 le 32
ip prefix-list RFC1918_RANGES seq 15 permit 192.168.0.0/16 ge 16 le 32
!
route-map ALLOW_RFC1918 permit 10
 match ip address prefix-list RFC1918_RANGES
exit
!
line vty
!
end
EOT

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
PRIVATELOCAL=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4`
PUBLICLOCAL=`curl http://v4.ipadd.re`
sed -i "s/PUBLICLOCAL/$PUBLICLOCAL/g" /etc/ipsec.conf
sed -i "s/PRIVATELOCAL/$PRIVATELOCAL/g" /etc/strongswan.d/ipsec-vti.sh

# Set proper permissions for FRR configuration
chown frr:frr /etc/frr/frr.conf
chmod 640 /etc/frr/frr.conf
chmod 700 /etc/strongswan.d/ipsec-vti.sh

# Service management
systemctl daemon-reload  # Add: Reload systemd after creating new unit files
systemctl enable --now systemd-networkd
systemctl enable strongswan-starter
systemctl restart strongswan-starter
systemctl enable frr
systemctl restart frr

# Add route for remote subnet
ip route add ${var.remote_subnet} via 172.16.0.2 dev vti100  # Uncomment if needed

EOF


              
  depends_on = [  ]
}

# Create Elastic IP for Wavelength EC2 instance
resource "aws_eip" "wavelength_ip" {
  network_border_group = var.network_border_group
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

