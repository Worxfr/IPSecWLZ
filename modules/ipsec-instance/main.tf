# Data source to get latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu22" {
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

ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["172.16.0.0/12"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.0.0/16"]
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
  ami           = data.aws_ami.ubuntu22.id
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

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/vpn-setup.log
}

log "Starting VPN configuration"

# Update and install packages
apt_update_install() {
    log "Updating system and installing packages"
    apt-get update -y && apt-get install -y strongswan-swanctl charon-systemd libcharon-extra-plugins frr iproute2
    if [ $? -ne 0 ]; then
        log "Error during package installation"
        exit 1
    fi
}

# Wait for apt/dpkg processes to finish
wait_for_apt() {
    while pgrep -f "apt|dpkg" > /dev/null; do
        log "Waiting for apt/dpkg processes to finish..."
        sleep 10
    done
}

wait_for_apt
apt_update_install

log "Configuring strongSwan"
cat <<EOT > /etc/swanctl/swanctl.conf
connections {
    ikev2-xfrm {
        local_addrs = PRIVATE_LOCAL
        remote_addrs = ${var.remote_public_ip}
        
        local {
            auth = psk
            id = ${var.local_private_ip}
        }
        remote {
            auth = psk
            id = ${var.remote_private_ip}
        }
        
        children {
            net {
                local_ts = 0.0.0.0/0
                remote_ts = 0.0.0.0/0
                esp_proposals = aes256-sha256-modp2048
                updown = /etc/swanctl/xfrm-updown.sh
                if_id_in = ${var.mark}
                if_id_out = ${var.mark}
                mode = tunnel
                start_action = start
            }
        }
        
        version = 2
        proposals = aes256-sha256-modp2048
    }
}

secrets {
    ike-psk {
        id-1 = ${var.local_private_ip}
        id-2 = ${var.remote_private_ip}
        secret = "${var.ipsec_psk}"
    }
}
EOT

log "Configuring XFRM updown script"
cat <<EOT > /etc/swanctl/xfrm-updown.sh
#!/bin/bash

case "\$PLUTO_VERB" in
    up-client)
        ip link add xfrm${var.mark} type xfrm if_id ${var.mark} dev ens5
        ip addr add ${var.local_private_ip}/30 dev xfrm${var.mark}
        ip link set xfrm${var.mark} up mtu 1420
        iptables -t mangle -A FORWARD -o xfrm${var.mark} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        #ip route add ${var.remote_private_ip}/32 dev xfrm${var.mark}
        ;;
    down-client)
        ip link del xfrm${var.mark}
        iptables -t mangle -D FORWARD -o xfrm${var.mark} -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        ip route delete ${var.remote_private_ip}/32 dev xfrm${var.mark}
        ;;
esac
EOT

chmod +x /etc/swanctl/xfrm-updown.sh

log "Configuring network parameters"
cat <<EOT > /etc/sysctl.d/99-ipsecconfig.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.all.log_martians=1
EOT

sysctl -p /etc/sysctl.d/99-ipsecconfig.conf

log "Configuring FRRouting"
sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons

cat <<EOT > /etc/frr/frr.conf
frr version 8.1
frr defaults traditional
hostname vpn-router-xfrm
log syslog informational
service integrated-vtysh-config

router bgp ${var.bgp_asn_local}
 bgp router-id ${var.local_private_ip}
 neighbor ${var.remote_private_ip} remote-as ${var.bgp_asn_remote}
 neighbor ${var.remote_private_ip} timers 10 30
 neighbor ${var.remote_private_ip} password ${var.bgp_password}

 address-family ipv4 unicast
  neighbor ${var.remote_private_ip} activate
  neighbor ${var.remote_private_ip} soft-reconfiguration inbound
  redistribute static
  redistribute connected
 exit-address-family

ip prefix-list RFC1918_RANGES seq 5 permit 10.0.0.0/8 ge 8 le 32
ip prefix-list RFC1918_RANGES seq 10 permit 172.16.0.0/12 ge 12 le 32
ip prefix-list RFC1918_RANGES seq 15 permit 192.168.0.0/16 ge 16 le 32

route-map ALLOW_RFC1918 permit 10
 match ip address prefix-list RFC1918_RANGES

line vty
!
end
EOT

log "Retrieving EC2 metadata"
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_LOCAL=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_LOCAL=$(curl -s http://checkip.amazonaws.com)

sed -i "s/PUBLIC_LOCAL/$PUBLIC_LOCAL/g" /etc/swanctl/swanctl.conf
sed -i "s/PRIVATE_LOCAL/$PRIVATE_LOCAL/g" /etc/swanctl/swanctl.conf

log "Setting permissions and starting services"
chown frr:frr /etc/frr/frr.conf 
chmod 640 /etc/frr/frr.conf 

# AppArmor fix
log "Applying AppArmor fix for swanctl"
cat <<EOT >> /etc/apparmor.d/local/usr.sbin.swanctl
/dev/pts/* rw,
/dev/pts/[0-9]* rw,
EOT

apparmor_parser -r /etc/apparmor.d/usr.sbin.swanctl

systemctl enable --now strongswan.service
systemctl restart strongswan.service
systemctl enable --now frr.service
systemctl restart frr.service

log "VPN configuration completed"

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
  source_dest_check = false

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

