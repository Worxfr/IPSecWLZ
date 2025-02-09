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

resource "random_string" "rand" {
  length = 8
  lower  = true
  upper = false
  special = false 
  numeric = true
}

# Security group for EC2 instance
resource "aws_security_group" "ipsec_bgp_sg" {
  name        = "ipsec-bgp-sg"
  description = "Security group for IPSec tunnel and BGP EC2 instance"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["${var.remote_public_ip}/32"]
  }

  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["${var.remote_public_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role for AWS Systems Manager Session Manager access
resource "aws_iam_role" "session_manager_role" {
  name = "SessionManagerRole-${random_string.rand.result}"
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

resource "aws_iam_role_policy_attachment" "session_manager_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.session_manager_role.name
}

resource "aws_iam_instance_profile" "session_manager_profile" {
  name = "SessionManagerProfile-${random_string.rand.result}"
  role = aws_iam_role.session_manager_role.name
}


# EC2 instance for IPSec tunnel and BGP
resource "aws_instance" "ipsec_bgp_instance" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.medium"
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ipsec_bgp_sg.id]

  key_name = var.key_pair_name
  user_data_replace_on_change = true

  source_dest_check = false

  iam_instance_profile = aws_iam_instance_profile.session_manager_profile.name

  tags = {
    Name = "IPSec-BGP-Instance-${random_string.rand.result}"
  }

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
  left=PRIVATELOCAL
  leftid=@PUBLICLOCAL
  leftsubnet=0.0.0.0/0
  right=${var.remote_public_ip}
  rightid=%any
  rightsubnet=0.0.0.0/0
  authby=secret
  mark=42
  vti-interface=vti100
  vti-routing=no
  leftvti=${var.local_private_ip}/30
  rightvti=${var.remote_private_ip}/30
  leftupdown=/etc/strongswan.d/ipsec-vti.sh
EOT

touch /tmp/ETAPE2

echo ": PSK \"${var.ipsec_psk}\"" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets

touch /tmp/ETAPE3

cat <<EOT > /etc/strongswan.d/ipsec-vti.sh
#!/bin/bash
sudo ip link add vti100 type vti local PRIVATELOCAL remote ${var.remote_public_ip} key 42
sudo ip addr add ${var.local_private_ip}/30 remote ${var.remote_private_ip}/30 dev vti100
sudo ip link set vti100 up mtu 1419
sudo iptables -t mangle -A FORWARD -o vti100 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
sudo iptables -t mangle -A INPUT -p esp -s PRIVATELOCAL -d ${var.remote_public_ip} -j MARK --set-xmark 42
sudo ip route flush table 220
EOT

echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ipsecconfig.conf
echo "net.ipv4.conf.vti100.disable_policy=1" >> /etc/sysctl.d/99-ipsecconfig.conf
echo "net.ipv4.conf.vti100.rp_filter=2" >> /etc/sysctl.d/99-ipsecconfig.conf
echo "net.ipv4.conf.ens5.disable_xfrm=1" >> /etc/sysctl.d/99-ipsecconfig.conf
echo "net.ipv4.conf.ens5.disable_policy=1" >> /etc/sysctl.d/99-ipsecconfig.conf
sysctl --system

sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

cat << EOT > /etc/frr/frr.conf
frr version 8.1
frr defaults traditional
hostname vpn-router
log syslog informational
service integrated-vtysh-config
!
router bgp ${var.bgp_asn_local}
bgp router-id ${var.local_private_ip}
neighbor ${var.remote_private_ip} remote-as ${var.bgp_asn_remote}
neighbor ${var.remote_private_ip} timers 10 30
!
address-family ipv4 unicast
  neighbor ${var.remote_private_ip} activate
  neighbor ${var.remote_private_ip} soft-reconfiguration inbound
  redistribute static
  redistribute connect
  neighbor ${var.remote_private_ip} route-map ALLOW_RFC1918 in
    neighbor ${var.remote_private_ip} route-map ALLOW_RFC1918 out
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
sed -i "s/PRIVATELOCAL/$PRIVATELOCAL/g" /etc/ipsec.conf

chown frr:frr /etc/frr/frr.conf
chmod 640 /etc/frr/frr.conf
chmod 700 /etc/strongswan.d/ipsec-vti.sh

systemctl daemon-reload
systemctl enable --now systemd-networkd
systemctl enable strongswan-starter
systemctl restart strongswan-starter
systemctl enable frr
systemctl restart frr


EOF
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.ipsec_bgp_instance.id
  allocation_id = var.elastic_ip
}

# Security groups for secondary ENIs
resource "aws_security_group" "secondary_eni_sg" {
  for_each = { for idx, vpc in var.secondary_vpcs : idx => vpc }
  
  name        = "secondary-eni-sg-${each.key}"
  description = "Security group for secondary ENI ${each.key}"
  vpc_id      = each.value.vpc_id

  # Default rules if no custom rules provided
  dynamic "ingress" {
    for_each = length(each.value.security_group_rules) > 0 ? each.value.security_group_rules : [{
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }]
    
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secondary-eni-sg-${each.key}"
  }
}

# Create secondary ENIs
resource "aws_network_interface" "secondary_eni" {
  for_each = { for idx, vpc in var.secondary_vpcs : idx => vpc }

  subnet_id       = each.value.subnet_id
  security_groups = [aws_security_group.secondary_eni_sg[each.key].id]
  description     = each.value.description

  tags = {
    Name = "CrossVPC-Secondary-ENI-${each.key}"
  }
}

# Attach secondary ENIs to the instance
resource "aws_network_interface_attachment" "secondary_eni_attachment" {
  for_each = { for idx, vpc in var.secondary_vpcs : idx => vpc }

  instance_id          = aws_instance.ipsec_bgp_instance.id
  network_interface_id = aws_network_interface.secondary_eni[each.key].id
  device_index         = each.key + 1  # Start from index 1 as 0 is primary ENI
}

