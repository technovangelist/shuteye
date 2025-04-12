#!/bin/bash

# Process Monitor and Auto-Shutdown Service
# Monitors specified processes and shuts down the system after inactivity

# Load configuration
CONFIG_FILE="/etc/shuteye/shuteye.conf"
if [ -f "$CONFIG_FILE" ]; then
    # Source the configuration file
    . "$CONFIG_FILE"
else
    echo "Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

# Set defaults if not specified in config
# Remove quotes if present
PROCESSES_TO_MONITOR=$(echo "${PROCESSES_TO_MONITOR:-ollama,invoke}" | tr -d '"')
INACTIVITY_TIMEOUT=$(echo "${INACTIVITY_TIMEOUT:-60}" | tr -d '"')
LOG_FILE=$(echo "${LOG_FILE:-/var/log/shuteye.log}" | tr -d '"')
NOTIFICATION_METHOD=$(echo "${NOTIFICATION_METHOD:-wall}" | tr -d '"')
SHUTDOWN_DELAY=$(echo "${SHUTDOWN_DELAY:-1}" | tr -d '"')
CHECK_INTERVAL=$(echo "${CHECK_INTERVAL:-60}" | tr -d '"')

# Create a state file to track last activity time
STATE_DIR="/var/lib/shuteye"
STATE_FILE="$STATE_DIR/last_activity.state"

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

# Create state directory if it doesn't exist
if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
    echo "Error: Cannot create state directory $STATE_DIR" >&2
    exit 1
fi

log_message "Shuteye service started"
log_message "Monitoring processes: $PROCESSES_TO_MONITOR"
log_message "Inactivity timeout: $INACTIVITY_TIMEOUT minutes"
log_message "Notification method: $NOTIFICATION_METHOD"
log_message "Shutdown delay: $SHUTDOWN_DELAY minute(s)"
log_message "Check interval: $CHECK_INTERVAL seconds"

# Function to check if a specific process is active
is_process_running() {
    local process_pattern="$1"
    # Trim whitespace
    process_pattern=$(echo "$process_pattern" | xargs)
    
    # Split the pattern into words to check for multi-word patterns
    read -ra PATTERN_WORDS <<< "$process_pattern"
    
    if [ ${#PATTERN_WORDS[@]} -gt 1 ]; then
        # For multi-word patterns, we need to be more precise
        # Example: "ollama runner" should match processes containing both words in order
        if ps aux | grep -v "grep" | grep -E "$process_pattern" > /dev/null 2>&1; then
            log_message "Found match for multi-word process: '$process_pattern'"
            return 0  # Process is running
        fi
    else
        # For single-word patterns, we check if it's the command or part of the command line
        # Example: "runner" should match "/usr/local/bin/ollama runner ..."
        if ps aux | grep -v "grep" | grep -E "(^| )$process_pattern( |$)" > /dev/null 2>&1; then
            log_message "Found match for process: '$process_pattern'"
            return 0  # Process is running
        fi
    fi
    
    return 1  # Process is not running
}

# Function to check all monitored processes
check_monitored_processes() {
    # Convert comma-separated list to array
    IFS=',' read -ra PROCESS_LIST <<< "$PROCESSES_TO_MONITOR"
    
    for PROCESS in "${PROCESS_LIST[@]}"; do
        # Trim whitespace
        PROCESS=$(echo "$PROCESS" | xargs)
        
        if is_process_running "$PROCESS"; then
            log_message "Process '$PROCESS' is currently running"
            return 0  # At least one monitored process is running
        else
            log_message "Process '$PROCESS' is not currently running"
        fi
    done
    
    return 1  # No monitored processes are running
}

# Function to update the last activity timestamp
update_last_activity() {
    # Get current timestamp
    local current_time=$(date +%s)
    echo "$current_time" > "$STATE_FILE"
    log_message "Updated last activity timestamp: $(date -d @$current_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $current_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$current_time")"
}

# Function to get the last activity timestamp
get_last_activity() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        # If no state file exists, create one with current time
        local current_time=$(date +%s)
        echo "$current_time" > "$STATE_FILE"
        echo "$current_time"
    fi
}

# Function to check if inactivity timeout has been reached
is_timeout_reached() {
    local last_activity=$(get_last_activity)
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - last_activity))
    local timeout_seconds=$((INACTIVITY_TIMEOUT * 60))
    
    if [ "$elapsed_time" -ge "$timeout_seconds" ]; then
        return 0  # True, timeout reached
    else
        return 1  # False, timeout not reached
    fi
}

# Main monitoring loop
while true; do
    # Check if any monitored process is running
    if check_monitored_processes; then
        # Update the last activity time
        update_last_activity
    else
        log_message "No monitored processes are currently running"
        
        # Check if inactivity timeout has been reached
        if is_timeout_reached; then
            local last_activity=$(get_last_activity)
            local last_activity_human=$(date -d @$last_activity '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $last_activity '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$last_activity")
            
            log_message "WARNING: No monitored processes have been active since $last_activity_human ($INACTIVITY_TIMEOUT minutes timeout reached)"
            log_message "Initiating system shutdown in $SHUTDOWN_DELAY minute(s)"
            
            # Notify all users about the shutdown
            notify_users "System will shut down in $SHUTDOWN_DELAY minute(s) due to process inactivity for $INACTIVITY_TIMEOUT minutes"
            
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
        else
            local last_activity=$(get_last_activity)
            local current_time=$(date +%s)
            local elapsed_time=$((current_time - last_activity))
            local elapsed_minutes=$((elapsed_time / 60))
            local remaining_minutes=$((INACTIVITY_TIMEOUT - elapsed_minutes))
            
            log_message "Inactivity period: $elapsed_minutes minutes (shutdown in $remaining_minutes more minutes of inactivity)"
        fi
    fi
    
    # Wait before checking again
    sleep $CHECK_INTERVAL
done
