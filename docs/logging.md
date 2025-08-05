## 🗒️ Logging System (`lib/log.sh`)
This file provides a consistent logging interface across all scripts.

### ✅ Features
* Daily log files (`logs/DD-MM-YYYY.log`)
* Color-coded output (INFO, WARN, ERROR, STEP, OK)
* Automatic redirection of all `stdout` and `stderr` to the log file
* Global error trapping via `trap on_error ERR`

### 🔧 Usage in scripts
```bash
. lib/log.sh
step "Starting..."
info "Doing something important"
warn "This might be risky"
ok "Success!"
```

### ✨ Levels available
* `debug`, `info`, `warn`, `error`, `ok`, `step`, `section`

### 📂 Customization
* Set `LOG_FILE`, `LOG_LEVEL`, and `TIMESTAMP_FMT` as env vars

### 🧩 Dependencies
* Relies on `lib/colors.sh` for styling
