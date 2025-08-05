## 🔐 Domain/IP Allowlist System
This system combines `dnsmasq` + `ipset` + `iptables`:

* All clients are limited to domains listed in `config/whitelist.txt`
* Specific IPs listed in `allow_all_ips.txt` can bypass this restriction

### Example: `whitelist.txt`

```sh
example.com
github.com
debian.org
```

### Example: `allow_all_ips.txt`

```sh
192.168.10.42
192.168.10.50
```

The script `08-setup-allowlist.sh` sets up rules and saves them for boot using `ipset-restore.service`.