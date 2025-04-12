#!/bin/bash

LOG_FILE="/tmp/pppoe.log"

cleanup() {
    echo -e "\n[FNRG] Terminating PPPoE connection..."
    sudo pkill pppd
    echo "[FNRG] PPPoE connection terminated."
    echo "[RELAY] Stopping PPPoE relay..."
    sudo pkill pppoe-relay
    echo "[RELAY] PPPoE relay terminated."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Start PPPoE relay
sudo pppoe-relay -B enp0s8 -B enp0s10 -n 1 &
RELAY_PID=$!
echo "[RELAY] PPPoE relay started with PID $RELAY_PID."

# Start PPPoE connection (using 'call rg') and log it
sudo pppd call rg | tee "$LOG_FILE" | awk '{ print "[FNRG] " $0 }' &

# Wait until interface ppp0 appears
echo "[FNRG] Waiting for PPP interface ppp0 to come up..."
while ! ip addr show ppp0 > /dev/null 2>&1; do
    sleep 2
done
echo "[FNRG] PPP interface ppp0 is up."

# Enable IP forwarding
echo "[FNRG] Enabling IPv4 forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Restart ISC DHCP server
echo "[FNRG] Restarting ISC DHCP server..."
sudo systemctl restart isc-dhcp-server

# Setup NAT via ppp0
echo "[FNRG] Setting up NAT (MASQUERADE)..."
sudo iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE

# Extract peer IP from log
echo "[FNRG] Waiting for PPPoE peer IP to be detected..."
while true; do
    DEST_IP=$(grep -oP 'remote IP address \K[\d.]+' "$LOG_FILE")
    if [ -n "$DEST_IP" ]; then
        break
    fi
    sleep 1
done
echo "[FNRG] Detected PPPoE peer IP: $DEST_IP"

# Add route
sudo ip route add 10.45.0.0/24 via "$DEST_IP"
echo "[FNRG] Route to 10.45.0.0/24 via $DEST_IP added successfully."

# Ping verification
echo "[FNRG] Pinging 10.45.0.1 to verify connection..."
if ping -c 1 10.45.0.1 > /dev/null 2>&1; then
    echo "[FNRG] PDU session to UPF successfully established!"
else
    echo "[FNRG] Failed to reach UPF at 10.45.0.1."
fi
# Add route
sudo ip route add 10.51.0.0/24 dev ppp0
echo "[FNRG] Route to 10.51.0.0/24 dev ppp0  added successfully."

# Ping verification
echo "[FNRG] Pinging 10.51.0.88 to verify connection..."
if ping -c 1 10.51.0.88 > /dev/null 2>&1; then
    echo "[FNRG] PDU session to CU successfully established!"
else
    echo "[FNRG] Failed to reach CU at 10.51.0.88."
fi

# Wait to keep script running for cleanup
wait
