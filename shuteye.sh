#!/bin/bash

# Process Monitor and Auto-Shutdown Service
# Monitors specified processes and shuts down the system after inactivity

# Exit on error
set -e

# Load configuration
CONFIG_FILE="/etc/shuteye/shuteye.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Set defaults if not specified in config
PROCESSES_TO_MONITOR="${PROCESSES_TO_MONITOR:-ollama,invoke}"
INACTIVITY_TIMEOUT="${INACTIVITY_TIMEOUT:-60}"
LOG_FILE="${LOG_FILE:-/var/log/shuteye.log}"
NOTIFICATION_METHOD="${NOTIFICATION_METHOD:-wall}"
SHUTDOWN_DELAY="${SHUTDOWN_DELAY:-1}"

# Function to log messages
log_message() {
    local log_dir=$(dirname "$LOG_FILE")
    
    # Ensure log directory exists
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            echo "Error: Cannot create log directory $log_dir"
            return 1
        }
    }
    
    # Attempt to write to log file
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE" 2>/dev/null || {
        echo "Error: Cannot write to log file $LOG_FILE"
        return 1
    }
    
    return 0
}

# Function to notify users
notify_users() {
    local message="$1"
    
    case "$NOTIFICATION_METHOD" in
        wall)
            wall "$message" 2>/dev/null || log_message "Warning: Failed to send wall notification"
            ;;
        notify-send)
            for user in $(who | cut -d' ' -f1 | sort | uniq); do
                sudo -u "$user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$user")/bus notify-send "Shuteye" "$message" 2>/dev/null || true
            done
            ;;
        *)
            wall "$message" 2>/dev/null || log_message "Warning: Failed to send notification"
            ;;
    esac
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || {
    echo "Error: Cannot create log directory $(dirname "$LOG_FILE")"
    exit 1
}

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "Error: Cannot create log file $LOG_FILE"
    exit 1
}

log_message "Shuteye service started"
log_message "Monitoring processes: $PROCESSES_TO_MONITOR"
log_message "Inactivity timeout: $INACTIVITY_TIMEOUT minutes"
log_message "Notification method: $NOTIFICATION_METHOD"
log_message "Shutdown delay: $SHUTDOWN_DELAY minute(s)"

# Function to check if a process is active
check_process_activity() {
    local process="$1"
    local timeout="$2"
    
    # Trim whitespace
    process=$(echo "$process" | xargs)
    
    # Method 1: Check if process is currently running
    if pgrep -f "$process" > /dev/null; then
        log_message "Process '$process' is currently running"
        return 0
    fi
    
    # Method 2: Check process start time from ps history
    if ps -eo lstart,cmd | grep -v grep | grep -i "$process" | awk '{print $1,$2,$3,$4,$5}' | while read -r datetime; do
        start_time=$(date -d "$datetime" +%s 2>/dev/null) || start_time=$(date -j -f "%a %b %d %T %Y" "$datetime" +%s 2>/dev/null)
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        max_elapsed_time=$((timeout * 60))
        
        if [ "$elapsed_time" -le "$max_elapsed_time" ]; then
            return 0
        fi
    done; then
        log_message "Process '$process' ran within the last $timeout minutes (ps history)"
        return 0
    fi
    
    # Method 3: Check systemd journal
    local since_time="$timeout minutes ago"
    if journalctl -t "$process" --since "$since_time" 2>/dev/null | grep -q .; then
        log_message "Process '$process' ran within the last $timeout minutes (journal)"
        return 0
    fi
    
    # Method 4: Check system process accounting (if available)
    if command -v lastcomm >/dev/null 2>&1; then
        if lastcomm "$process" 2>/dev/null | head -n 1 | grep -q .; then
            # Note: lastcomm doesn't easily allow filtering by time, so this is approximate
            log_message "Process '$process' has run recently (process accounting)"
            return 0
        fi
    fi
    
    return 1
}

# Main monitoring loop
while true; do
    # Flag to track if any monitored process is running
    PROCESS_FOUND=false
    
    # Convert comma-separated list to array
    IFS=',' read -ra PROCESS_LIST <<< "$PROCESSES_TO_MONITOR"
    
    for PROCESS in "${PROCESS_LIST[@]}"; do
        if check_process_activity "$PROCESS" "$INACTIVITY_TIMEOUT"; then
            PROCESS_FOUND=true
            break
        fi
    done
    
    if [ "$PROCESS_FOUND" = false ]; then
        log_message "WARNING: No monitored processes have been active for $INACTIVITY_TIMEOUT minutes"
        log_message "Initiating system shutdown in $SHUTDOWN_DELAY minute(s)"
        
        # Notify all users about the shutdown
        notify_users "System will shut down in $SHUTDOWN_DELAY minute(s) due to inactivity of monitored processes"
        
        # Log the shutdown event
        log_message "Executing shutdown command"
        
        # Initiate shutdown
        shutdown -h +$SHUTDOWN_DELAY "Automatic shutdown due to process inactivity" || {
            log_message "ERROR: Failed to execute shutdown command"
            notify_users "ERROR: Failed to execute shutdown command"
            
            # Wait before trying again
            sleep 300
            continue
        }
        
        # Exit the script
        exit 0
    fi
    
    # Wait before checking again (60 seconds)
    sleep 60
done
