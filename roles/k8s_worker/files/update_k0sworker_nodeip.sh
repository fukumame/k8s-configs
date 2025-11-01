#!/bin/bash
#
# Update k0sworker.service --node-ip parameter if IP address has changed
#

SERVICE_FILE="/etc/systemd/system/k0sworker.service"
LOG_FILE="/var/log/k0sworker-nodeip-update.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get current IP address
CURRENT_IP=$(ip route get 1.1.1.1 2>/dev/null | sed -nE 's/.*src ([0-9.]+).*/\1/p' || echo "")

if [ -z "$CURRENT_IP" ]; then
    log "ERROR: Failed to get current IP address"
    exit 1
fi

log "Current IP address: $CURRENT_IP"

# Get current node-ip from service file
if [ ! -f "$SERVICE_FILE" ]; then
    log "ERROR: Service file $SERVICE_FILE not found"
    exit 1
fi

CURRENT_NODE_IP=$(grep -- '--node-ip=' "$SERVICE_FILE" | sed -nE 's/.*--node-ip=([0-9.]+).*/\1/p' | head -n1 || echo "")

if [ -z "$CURRENT_NODE_IP" ]; then
    log "WARNING: Could not find --node-ip in service file. Service file may need manual configuration."
    exit 1
fi

log "Current node-ip in service file: $CURRENT_NODE_IP"

# Compare IP addresses
if [ "$CURRENT_IP" = "$CURRENT_NODE_IP" ]; then
    log "IP address matches. No update needed."
    exit 0
fi

log "IP address mismatch detected. Updating service file..."

# Update service file
sed -i.bak -E "s/--node-ip=[0-9.]+/--node-ip=$CURRENT_IP/" "$SERVICE_FILE"

if [ $? -ne 0 ]; then
    log "ERROR: Failed to update service file"
    exit 1
fi

log "Service file updated successfully."

# Reload systemd daemon
systemctl daemon-reload

if [ $? -ne 0 ]; then
    log "ERROR: Failed to reload systemd daemon"
    exit 1
fi

log "Systemd daemon reloaded."

# Restart k0sworker service
systemctl restart k0sworker

if [ $? -ne 0 ]; then
    log "ERROR: Failed to restart k0sworker service"
    exit 1
fi

log "k0sworker service restarted successfully. IP address updated from $CURRENT_NODE_IP to $CURRENT_IP"
exit 0

