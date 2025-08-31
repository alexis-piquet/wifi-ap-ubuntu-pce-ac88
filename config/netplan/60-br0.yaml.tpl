network:
  version: 2
  renderer: networkd
  ethernets:
    ${ETHERNET_IF}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BRIDGE_IF}:
      interfaces: [${ETHERNET_IF}]
      dhcp4: true
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
