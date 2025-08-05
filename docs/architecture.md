## 🧱 Project Architecture
This project follows a modular and reproducible layout:

```sh
./server
├── bin/                       # Custom firmware binaries
│   ├── dhd.ko                 # Kernel module for Broadcom
│   └── *.bin / *.zip          # Optional firmware blobs
├── config/                    # Persistent configuration files
│   ├── hostapd.conf           # WiFi configuration
│   ├── dnsmasq.conf           # DHCP/DNS config
│   ├── interfaces             # Static IP config
│   ├── whitelist.txt          # Domains allowed for all clients
│   ├── allow_all_ips.txt      # IPs allowed to access all domains
│   ├── dnsmasq.d/             # Auto-generated: domain → ipset mapping
│   └── ipset-restore.service  # Systemd unit to restore IP sets on boot
├── lib/                       # Shared Bash utilities
│   ├── log.sh                 # Logging system
│   └── colors.sh              # Color helpers
├── logs/                      # Daily logs
├── scripts/                   # Modular install steps
│   └── 00-... to 99-...       # Executed by install.sh
├── install.sh                 # Runs the full setup pipeline
└── start.sh                   # Starts the AP and restores runtime config
```