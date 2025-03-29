#!/bin/bash

# File log sementara
LOG_FILE="/tmp/pppoe.log"
L2TP_LOG_FILE="/tmp/l2tp.log"

# Function to handle termination
cleanup() {
    echo -e "\n[N5GC] Terminating L2TP connection..."
    sudo xl2tpd-control disconnect-lac n5gc
    sudo systemctl stop xl2tpd
    echo "[N5GC] L2TP connection terminated."

    echo -e "\n[N5GC] Terminating PPPoE connection..."
    sudo pkill pppd
    echo "[N5GC] PPPoE connection terminated."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM to trigger cleanup
trap cleanup SIGINT SIGTERM

# Start PPPoE connection in the background and redirect output to log
sudo pppd call n5gc | tee "$LOG_FILE" | awk '{ print "[N5GC] " $0 }' &

# Wait for PPP interface to come up
echo "[N5GC] Waiting for PPP interface ppp0 to come up..."
while ! ip addr show ppp0 > /dev/null 2>&1; do
    sleep 2
done
echo "[N5GC] PPP interface ppp0 is up."

# Retrieve PPPoE destination IP (peer IP) from log
DEST_IP=""
echo "[N5GC] Waiting for PPPoE peer IP to be detected..."
while [ -z "$DEST_IP" ]; do
    DEST_IP=$(grep -oP 'remote IP address \K[\d.]+' "$LOG_FILE")
    sleep 1
done
echo "[N5GC] Detected PPPoE peer IP: $DEST_IP"

# Add routes directly
if [ -n "$DEST_IP" ]; then
    sudo ip route add 10.45.0.0/24 via "$DEST_IP"
    echo "[N5GC] Route to 10.45.0.0/24 via $DEST_IP added successfully."
    sudo ip route add 10.50.0.0/24 dev ppp0
    echo "[N5GC] Route to 10.50.0.0/24 via ppp0 added successfully."
    sudo ip route add 10.51.0.0/24 dev ppp0
    echo "[N5GC] Route to 10.51.0.0/24 via ppp0 added successfully."
else
    echo "[N5GC] Failed to retrieve PPPoE destination IP. Route not added."
fi

# Ping 10.45.0.1 and verify success
echo "[N5GC] Pinging 10.45.0.1 to verify connection..."
if ping -c 1 10.45.0.1 > /dev/null 2>&1; then
    echo "[N5GC] PDU session to UPF successfully established!"
else
    echo "[N5GC] Failed to reach UPF at 10.45.0.1."
fi

# Start L2TP connection
echo "[N5GC] Restarting xl2tpd service..."
sudo systemctl restart xl2tpd
sleep 3  # Wait for xl2tpd to be ready

# Initiate L2TP connection
sudo xl2tpd-control connect-lac n5gc
sleep 2

# Add route for 10.46.0.0/24
sudo ip route add 10.46.0.0/24 dev ppp0
echo "[N5GC] Route to 10.46.0.0/24 via ppp0 added successfully."

# Test connectivity to 10.46.0.1
echo "[N5GC] Pinging 10.46.0.1 to verify connection..."
if ping -c 1 10.46.0.1 > /dev/null 2>&1; then
    echo "[N5GC] Connection to 10.46.0.1 is successful!"
else
    echo "[N5GC] Failed to reach 10.46.0.1."
fi

# Display L2TP logs
echo "[N5GC] Monitoring L2TP logs..."
sudo journalctl -u xl2tpd -f | tee "$L2TP_LOG_FILE" &

# Wait to keep the script alive for signal trapping
wait

