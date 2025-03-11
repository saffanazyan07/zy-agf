#!/bin/bash

# File log sementara
LOG_FILE="/tmp/pppoe.log"

# Function to handle termination
cleanup() {
    echo -e "\n[FNRG] Terminating PPPoE connection..."
    sudo pkill pppd
    echo "[FNRG] PPPoE connection terminated."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM to trigger cleanup
trap cleanup SIGINT SIGTERM

# Start PPPoE connection in the background and redirect output to log
sudo pppd call rg | tee "$LOG_FILE" | awk '{ print "[FNRG] " $0 }' &

# Wait for PPP interface to come up
echo "[FNRG] Waiting for PPP interface ppp0 to come up..."
while ! ip addr show ppp0 > /dev/null 2>&1; do
    sleep 2
done
echo "[FNRG] PPP interface ppp0 is up."

# Retrieve PPPoE destination IP (peer IP) from log
DEST_IP=""
echo "[FNRG] Waiting for PPPoE peer IP to be detected..."
while [ -z "$DEST_IP" ]; do
    DEST_IP=$(grep -oP 'remote IP address \K[\d.]+' "$LOG_FILE")
    sleep 1
done
echo "[FNRG] Detected PPPoE peer IP: $DEST_IP"

# Add route directly
if [ -n "$DEST_IP" ]; then
    sudo ip route add 10.45.0.0/24 via "$DEST_IP"
    echo "[FNRG] Route to 10.45.0.0/24 via $DEST_IP added successfully."
else
    echo "[FNRG] Failed to retrieve PPPoE destination IP. Route not added."
fi

# Ping 10.45.0.1 and verify success
echo "[FNRG] Pinging 10.45.0.1 to verify connection..."
if ping -c 1 10.45.0.1 > /dev/null 2>&1; then
    echo "[FNRG] PDU session to UPF successfully established!"
else
    echo "[FNRG] Failed to reach UPF at 10.45.0.1."
fi

# Wait to keep the script alive for signal trapping
wait
