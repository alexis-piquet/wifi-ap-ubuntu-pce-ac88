## 📥 CLI Installation

### 1️⃣ Make the CLI Executable
Run the following command to make the script executable:
```sh
chmod +x -R .
```

### 2️⃣ Global Installation
To use the CLI globally, move the `.` directory to a directory in your `PATH`, such as `/usr/local/bin`:
```sh
sudo cp -r . /usr/local/bin/wifi_ap
```

Alternatively, create an alias for the script:
- **For Bash:**
  Add the following alias to your `~/.bashrc` file:
  ```sh
  echo "alias wifi_ap='/usr/local/bin/wifi_ap/cli.sh'" >> ~/.bashrc
  source ~/.bashrc
  ```
- **For Zsh:**
  Add the following alias to your `~/.zshrc` file:
  ```sh
  echo "alias wifi_ap='/usr/local/bin/wifi_ap/cli.sh'" >> ~/.zshrc
  source ~/.zshrc
  ```