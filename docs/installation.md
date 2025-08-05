## 📦 Full Setup (Automated)
Run this to install everything in one go:

```sh
chmod +x server/**/*.sh
./install.sh
```

## Optionally, move to a system path:
```sh
sudo cp -r server /usr/local/bin/wifi
```

## Shell convenience:
```sh
echo "export WIFI=\"$(pwd)\"" >> ~/.bashrc
echo "alias wifi='/usr/local/bin/wifi/start.sh'" >> ~/.bashrc
source ~/.bashrc
```

Logs are stored daily in `server/logs/`.