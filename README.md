# Shuteye

A Linux service that monitors specified processes and automatically shuts down the system after a period of inactivity.

## Features

- Monitor a configurable list of processes
- Automatically shut down the system when no monitored processes have been active
- Configurable inactivity timeout
- Detailed logging
- Easy installation

## Quick Install

Install with a single command:

```bash
curl -s https://raw.githubusercontent.com/technovangelist/shuteye/main/install.sh | sudo sh
```

 ## Configuration

After installation, edit the configuration file:
```bash
sudo nano /etc/shuteye/shuteye.conf
```

### Configuration Options
  - ⁠PROCESSES_TO_MONITOR: Comma-separated list of process names to monitor
  - ⁠INACTIVITY_TIMEOUT: Number of minutes of inactivity before shutdown
  - ⁠LOG_FILE: Path to the log file
  - ⁠NOTIFICATION_METHOD: Method used to notify users (wall, notify-send)
  - ⁠SHUTDOWN_DELAY: Number of minutes between notification and actual shutdown
  - ⁠CHECK_INTERVAL: How often to check for process activity (in seconds)

## Usage

### Service Management

```bash
# Check service status
sudo systemctl status shuteye.service

# View logs
sudo tail -f /var/log/shuteye.log

# Restart the service
sudo systemctl restart shuteye.service

# Stop the service
sudo systemctl stop shuteye.service
```

## Uninstallation
 
```bash
sudo systemctl stop shuteye.service
sudo systemctl disable shuteye.service
sudo rm /etc/systemd/system/shuteye.service
sudo rm /usr/local/bin/shuteye.sh
sudo rm -r /etc/shuteye
sudo systemctl daemon-reload
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## One-Line Installation Command

With this repository structure, users can install your service with a single command:
```bash
curl -s https://raw.githubusercontent.com/technovangelist/shuteye/main/install.sh | sudo sh
```
