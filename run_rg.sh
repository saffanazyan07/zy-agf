#!/bin/bash

# Function to handle termination
cleanup() {
    echo -e "\n[FNRG] Terminating PPPoE connection..."
    sudo pkill pppd
    echo "[FNRG] PPPoE connection terminated."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM to trigger cleanup
trap cleanup SIGINT SIGTERM

# Start PPPoE connection in the background
sudo pppd call rg | awk '{ print "[FNRG] " $0 }' &
PPPD_PID=$!

# Wait for PPP interface to come up
while ! ip addr show ppp0 > /dev/null 2>&1; do
    sleep 3
done

# Retrieve PPPoE destination IP (peer IP)
DEST_IP=$(ip route show dev ppp0 | awk '/proto kernel/ {print $3}')

# Wait until the destination IP is reachable
while ! ping -c1 "$DEST_IP" > /dev/null 2>&1; do
    echo "[FNRG] Waiting for PPPoE peer $DEST_IP to become reachable..."
    sleep 2
done

if [ -n "$DEST_IP" ]; then
    # Add route automatically
    sudo ip route add 10.45.0.0/24 via "$DEST_IP"
    echo "[FNRG] Route to 10.45.0.0/24 via $DEST_IP added successfully."
else
    echo "[FNRG] Failed to retrieve PPPoE destination IP. Route not added."
fi

# Wait to keep the script alive for signal trapping
wait $PPPD_PID
