## 📶 Default WiFi Configuration
Edit `config/hostapd.conf`:

```ini
interface=wlp2s0
ssid=MyAwesomeAsusPCEAC88-AccessPoint
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wpa=2
wpa_passphrase=VeryStrongPassword
```

⚠️ The ASUS PCE-AC88 does **not** support dual-band AP mode.