## 📡 Starting the WiFi Access Point
After installation:

```sh
cd src
./start.sh
```

This script:
* Reapplies NAT and ipset rules
* Restarts `hostapd`, `dnsmasq`, `NetworkManager`
* Shows connected clients
* Confirms interface and routing