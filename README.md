# 🛰️ High-Speed WiFi Access Point with ASUS PCE-AC88 on Ubuntu
![Ubuntu](https://img.shields.io/badge/ubuntu-18.04%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Shell](https://img.shields.io/badge/shell-bash-lightgrey)
![hostapd](https://img.shields.io/badge/hostapd-built--from--source-orange)

Turn your Ubuntu machine (physical or virtualized in Proxmox) into a blazing fast wireless router using the ASUS PCE-AC88 WiFi adapter.

## 📚 Documentation Index
- [🚀 Features](#features)
- [🛠️ Hardware Requirements](#hardware-requirements)
- [🗒️ Logging System](docs/logging.md)
- [🧱 Project Architecture](docs/architecture.md)
- [📦 Installation Guide](docs/installation.md)
- [📡 Starting the WiFi Access Point](docs/start.md)
- [📶 WiFi Configuration](docs/wifi-config.md)
- [🔐 Domain/IP Allowlist System](docs/allowlist.md)
- [🧪 Script Breakdown](docs/scripts.md)
- [🧼 Cleaning Up Logs](docs/cleanup.md)
- [🤝 Contributing](docs/contributing.md)

## 🚀 Features
- Full Access Point setup using `hostapd`
- NAT, DHCP, and DNS caching with `dnsmasq`
- **Domain-based firewall using `ipset` allowlist**
- Custom firmware support for Broadcom chips (dhd.ko)
- Modular setup via shell scripts
- Compatible with Proxmox + PCI passthrough
- Clean logs and systemd integration

## 🛠️ Hardware Requirements
- ASUS PCE-AC88 WiFi card (4x4 MU-MIMO)
- Ethernet connection to your main router/modem
- Ubuntu 20.04+ (or any Debian-based distro)
- VM or bare-metal setup

## 📖 Continue reading:
➡️ [Installation Guide](docs/installation.md)  
➡️ [WiFi Config & Allowlist](docs/wifi-config.md)  
➡️ [Start & Debug](docs/start.md)

## 🔖 Keywords
`ubuntu`, `linux`, `wifi`, `access-point`, `hostapd`, `asus`, `pce-ac88`, `proxmox`, `router`, `networking`, `dhcp`, `dnsmasq`, `iptables`, `ipset`, `systemd`, `brcm`, `firewall`, `allowlist`
