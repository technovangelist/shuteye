#!/bin/bash

# Process Monitor and Auto-Shutdown Service
# Monitors specified processes and shuts down the system after inactivity

# Load configuration
CONFIG_FILE="/etc/shuteye/shuteye.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found at $CONFIG_FILE" >&2
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
        if ! mkdir -p "$log_dir" 2>/dev/null; then
            echo "Error: Cannot create log directory $log_dir" >&2
            return 1
        fi
    fi
    
    # Attempt to write to log file
    if ! echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE" 2>/dev/null; then
        echo "Error: Cannot write to log file $LOG_FILE" >&2
        return 1
    fi
    
    return 0
}

# Function to notify users
notify_users() {
    local message="$1"
    
    case "$NOTIFICATION_METHOD" in
        wall)
            if ! wall "$message" 2>/dev/null; then
                log_message "Warning: Failed to send wall notification"
            fi
            ;;
        notify-send)
            for user in $(who | cut -d' ' -f1 | sort | uniq); do
                sudo -u "$user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$user")/bus notify-send "Shuteye" "$message" 2>/dev/null || true
            done
            ;;
        *)
            # Default to wall if notification method is not recognized
            log_message "Warning: Unknown notification method '$NOTIFICATION_METHOD', defaulting to wall"
            if ! wall "$message" 2>/dev/null; then
                log_message "Warning: Failed to send notification"
            fi
            ;;
    esac
}

# Create log directory if it doesn't exist
if ! mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null; then
    echo "Error: Cannot create log directory $(dirname "$LOG_FILE")" >&2
    exit 1
fi

# Ensure log file is writable
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Error: Cannot create log file $LOG_FILE" >&2
    exit 1
fi

log_message "Shuteye service started"
log_message "Monitoring processes: $PROCESSES_TO_MONITOR"
log_message "Inactivity timeout: $INACTIVITY_TIMEOUT minutes"
log_message "Notification method: $NOTIFICATION_METHOD"
log_message "Shutdown delay: $SHUTDOWN_DELAY minute(s)"

# Function to check if a process is active
is_process_running() {
    local process="$1"
    # Trim whitespace
    process=$(echo "$process" | xargs)
    
    # Use pgrep with -f to match against the full command line
    pgrep -f "$process" >/dev/null 2>&1
    return $?
}

# Main monitoring loop
while true; do
    # Flag to track if any monitored process is running
    PROCESS_FOUND=false
    
    # Convert comma-separated list to array
    IFS=',' read -ra PROCESS_LIST <<< "$PROCESSES_TO_MONITOR"
    
    for PROCESS in "${PROCESS_LIST[@]}"; do
        # Trim whitespace
        PROCESS=$(echo "$PROCESS" | xargs)
        
        if is_process_running "$PROCESS"; then
            log_message "Process '$PROCESS' is currently running"
            PROCESS_FOUND=true
            break
        else
            log_message "Process '$PROCESS' is not currently running"
        fi
    done
    
    if [ "$PROCESS_FOUND" = false ]; then
        log_message "WARNING: No monitored processes have been active for $INACTIVITY_TIMEOUT minutes"
        log_message "Initiating system shutdown in $SHUTDOWN_DELAY minute(s)"
        
        # Notify all users about the shutdown
        notify_users "System will shut down in $SHUTDOWN_DELAY minute(s) due to inactivity of monitored processes"
        
        # Log the shutdown event
        log_message "Executing shutdown command"
        
        # Initiate shutdown - try different commands based on what's available
        if command -v shutdown >/dev/null 2>&1; then
            if ! shutdown -h +$SHUTDOWN_DELAY "Automatic shutdown due to process inactivity" 2>/dev/null; then
                if ! shutdown +$SHUTDOWN_DELAY "Automatic shutdown due to process inactivity" 2>/dev/null; then
                    log_message "ERROR: Failed to execute shutdown command"
                    notify_users "ERROR: Failed to execute shutdown command"
                    sleep 300
                    continue
                fi
            fi
        elif command -v poweroff >/dev/null 2>&1; then
            # Some systems might not have shutdown but have poweroff
            # Schedule it with at if available, otherwise just log and continue
            if command -v at >/dev/null 2>&1; then
                if ! echo "poweroff" | at now + $SHUTDOWN_DELAY minutes 2>/dev/null; then
                    log_message "ERROR: Failed to schedule poweroff command"
                    notify_users "ERROR: Failed to schedule poweroff command"
                    sleep 300
                    continue
                fi
            else
                log_message "WARNING: No suitable shutdown command found, continuing monitoring"
                notify_users "WARNING: System would have shut down, but no suitable shutdown command was found"
                sleep 300
                continue
            fi
        else
            log_message "ERROR: No shutdown or poweroff command available"
            notify_users "ERROR: Cannot shut down system - no shutdown command available"
            sleep 300
            continue
        fi
        
        # Exit the script
        exit 0
    fi
    
    # Wait before checking again (60 seconds)
    sleep 60
done
