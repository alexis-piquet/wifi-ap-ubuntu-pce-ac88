## 🧼 Cleaning Up Logs
Logs are saved per day in `logs/`:

```sh
find logs/ -type f -mtime +7 -delete
```

Automate cleanup using cron or a systemd timer.