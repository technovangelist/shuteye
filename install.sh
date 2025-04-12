#!/bin/bash

# Process Monitor and Auto-Shutdown Service Installer
# This script installs a service that monitors specified processes
# and shuts down the system after a period of inactivity

set -e

echo "=== Shuteye Process Monitor and Auto-Shutdown Service Installer ==="
echo ""

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try using sudo."
    exit 1
fi

# Create directories
echo "Creating directories..."
mkdir -p /etc/shuteye
mkdir -p /usr/local/bin

# Download files from GitHub
REPO_URL="https://raw.githubusercontent.com/technovangelist/shuteye/main"

echo "Downloading service files..."
curl -s "$REPO_URL/shuteye.sh" -o /usr/local/bin/shuteye.sh
curl -s "$REPO_URL/shuteye.service" -o /etc/systemd/system/shuteye.service

# Check if config file already exists to avoid overwriting user settings
if [ ! -f "/etc/shuteye/shuteye.conf" ]; then
    echo "Downloading default configuration..."
    curl -s "$REPO_URL/shuteye.conf" -o /etc/shuteye/shuteye.conf
    echo "Default configuration installed at /etc/shuteye/shuteye.conf"
    echo "You may want to edit this file to customize process list and timeout settings."
else
    echo "Configuration file already exists. Keeping existing configuration."
fi

# Set permissions
echo "Setting permissions..."
chmod +x /usr/local/bin/shuteye.sh
chmod 644 /etc/systemd/system/shuteye.service
chmod 644 /etc/shuteye/shuteye.conf

# Reload systemd and enable service
echo "Enabling service..."
systemctl daemon-reload
systemctl enable shuteye.service

# Start the service
echo "Starting service..."
systemctl start shuteye.service

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Service status:"
systemctl status shuteye.service --no-pager
echo ""
echo "Configuration file: /etc/shuteye/shuteye.conf"
echo "Log file: /var/log/shuteye.log"
echo ""
echo "Commands:"
echo "  View logs: sudo tail -f /var/log/shuteye.log"
echo "  Check status: sudo systemctl status shuteye.service"
echo "  Restart service: sudo systemctl restart shuteye.service"
echo "  Stop service: sudo systemctl stop shuteye.service"
echo ""
echo "Thank you for installing Shuteye!"
