# 🛰️ High-Speed WiFi Access Point with ASUS PCE-AC88 on Ubuntu

Turn your Ubuntu machine (physical or virtualized in Proxmox) into a blazing fast wireless router using the ASUS PCE-AC88 WiFi adapter.

---

## 🚀 Features

- Full Access Point setup using `hostapd`
- NAT, DHCP, and DNS caching with `dnsmasq`
- Custom firmware support for the PCE-AC88 (Broadcom)
- Automatic setup via modular Bash scripts
- Clean logs (1 log file per day in `./logs`)
- Perfect for Proxmox VMs, desktops, or mini-PCs

---

## 🛠️ Hardware Requirements

- ASUS PCE-AC88 WiFi card (4x4 MU-MIMO)
- Ethernet connection to your main router/modem
- Ubuntu 20.04+ or newer (or Debian-based distro)
- VM support (e.g. Proxmox with PCI passthrough)

---

## 📦 Full Setup (Automated)

To install everything in one go:

```bash
cd server
chmod +x install.sh
./install.sh
````

This will sequentially run all scripts located in `server/scripts/`, with real-time logs, colors, and traps for errors.

🗂️ Logs are stored in `server/logs/` with one file per day (e.g. `05-08-2025.log`).

---

## 🧪 Manual Script Execution

Each setup step is also available as a separate shell script:

```bash
server/scripts/00-check-env.sh         # Detects ethernet and WiFi interface
server/scripts/01-install-firmware.sh  # Installs missing firmware for Broadcom chipsets
server/scripts/02-compile-hostapd.sh   # Builds hostapd from source with required flags
server/scripts/03-configure-network.sh # Assigns static IP to the WiFi interface
server/scripts/04-configure-dnsmasq.sh # Sets up DHCP and local DNS
server/scripts/05-enable-nat.sh        # Enables IPv4 forwarding and NAT
server/scripts/06-enable-services.sh   # Starts hostapd as a systemd service
server/scripts/99-test-and-debug.sh    # Debugs connectivity and displays connected clients
```

---

## 📡 Starting the WiFi Access Point

Once installation is complete, use the `start.sh` script to boot up your custom access point:

```bash
cd server
./start.sh
```

This will:

* Reapply NAT rules
* Restart `hostapd`, `NetworkManager`, and related services
* Show connected clients
* Confirm that the AP is running

✅ The WiFi network will now be visible on your devices with the SSID and password defined in `config/hostapd.conf`.

---

## 📶 Default WiFi Configuration

You can customize your access point settings in this file:

```ini
# server/config/hostapd.conf

interface=wlp2s0
ssid=MyAwesomeAsusPCEAC88-AccessPoint
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wpa=2
wpa_passphrase=VeryStrongPassword
...
```

⚠️ Only 5GHz is supported at a time (the card does not support dual-band mode).

---

## 🧼 Cleaning Up Logs

Logs are stored daily in `server/logs/`. To clean up old logs manually:

```bash
find server/logs/ -type f -mtime +7 -delete
```

You can also automate that with a cronjob or systemd timer.

---

## 🤝 Contributing

PRs welcome to improve compatibility, automate more steps, or support more cards!

---

## 🔖 Keywords

`ubuntu`, `linux`, `wifi`, `access-point`, `hostapd`, `asus`, `pce-ac88`, `proxmox`, `router`, `networking`, `dhcp`, `dnsmasq`, `iptables`, `systemd`, `brcm`
