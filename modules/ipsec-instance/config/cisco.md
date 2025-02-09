# Cisco configuration example

> [!CAUTION]

Not tested

> [!WARNING]  
> ## ⚠️ Important Disclaimer
>
> **This project is for testing and demonstration purposes only.**
>


---

```cisco
! Basic configuration
conf t
no ip domain-lookup

! Interface configuration for outside interface (adjust interface name as needed)
interface GigabitEthernet0/0
 ip address YOUR_PUBLIC_IP 255.255.255.252
 no shutdown

! Create ISAKMP policy (IKEv2)
crypto ikev2 proposal AWS-PROPOSAL
 encryption aes-256
 integrity sha256
 group 14

crypto ikev2 policy AWS-POLICY
 proposal AWS-PROPOSAL

! Configure keyring
crypto ikev2 keyring AWS-KEYRING
 peer AWS-PEER
  address STRONGSWAN_PUBLIC_IP
  pre-shared-key YOUR_PRESHARED_KEY

! Configure IKEv2 profile
crypto ikev2 profile AWS-PROFILE
 match identity remote address STRONGSWAN_PUBLIC_IP 255.255.255.255
 identity local address YOUR_PUBLIC_IP
 authentication remote pre-share
 authentication local pre-share
 keyring local AWS-KEYRING

! Configure IPsec transform set
crypto ipsec transform-set AWS-TRANSFORM esp-aes 256 esp-sha256-hmac
 mode tunnel

! Configure IPsec profile
crypto ipsec profile AWS-IPSEC-PROFILE
 set transform-set AWS-TRANSFORM
 set ikev2-profile AWS-PROFILE

! Configure tunnel interface
interface Tunnel100
 ip address YOUR_VTI_IP 255.255.255.252
 tunnel source YOUR_PUBLIC_IP
 tunnel destination STRONGSWAN_PUBLIC_IP
 tunnel mode ipsec ipv4
 tunnel protection ipsec profile AWS-IPSEC-PROFILE
 no shutdown

! Configure BGP
router bgp YOUR_ASN
 bgp log-neighbor-changes
 neighbor STRONGSWAN_VTI_IP remote-as STRONGSWAN_ASN
 !
 address-family ipv4
  network YOUR_INTERNAL_NETWORK mask YOUR_INTERNAL_NETMASK
  neighbor STRONGSWAN_VTI_IP activate
  neighbor STRONGSWAN_VTI_IP soft-reconfiguration inbound
 exit-address-family

! NAT configuration if needed
ip nat inside source list NAT-ACL interface GigabitEthernet0/0 overload

! Route configuration
ip route 0.0.0.0 0.0.0.0 YOUR_NEXT_HOP

! Access list for interesting traffic (adjust as needed)
ip access-list extended NAT-ACL
 permit ip YOUR_INTERNAL_NETWORK YOUR_INTERNAL_WILDCARD any

! Enable NAT-T
crypto ikev2 nat keepalive 60
```

You'll need to replace these values:

- YOUR_PUBLIC_IP: Your Cisco router's public IP address

- STRONGSWAN_PUBLIC_IP: The public IP of your StrongSwan instance

- YOUR_PRESHARED_KEY: The same PSK configured in StrongSwan

- YOUR_VTI_IP: Your side of the VTI interface IP (from the /30 subnet)

- STRONGSWAN_VTI_IP: StrongSwan's side of the VTI interface IP

- YOUR_ASN: Your BGP ASN number

- STRONGSWAN_ASN: StrongSwan's BGP ASN number

- YOUR_INTERNAL_NETWORK: Your internal network address

- YOUR_INTERNAL_NETMASK: Your internal network mask

- YOUR_INTERNAL_WILDCARD: Wildcard mask for your internal network

- YOUR_NEXT_HOP: Your internet gateway IP

To verify the configuration:

```
! Check IKE status
show crypto ikev2 sa

! Check IPsec status
show crypto ipsec sa

! Check BGP status
show ip bgp summary
show ip bgp neighbors

! Check tunnel interface
show interface tunnel100

! Debug commands if needed
debug crypto ikev2
debug crypto ipsec
debug ip bgp
```

### Important notes:

1. This configuration uses IKEv2 with AES-256 and SHA-256

2. NAT-Traversal is enabled by default

3. The configuration includes BGP routing as per your StrongSwan setup

4. The transform set matches your StrongSwan configuration

5. MTU/MSS clamping might be needed depending on your network

### For production deployment:

1. Consider adding backup tunnels

2. Implement route filtering with BGP

3. Add access-lists for security

4. Configure QoS if needed

5. Monitor tunnel state with IP SLA