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

# Start PPPoE connection and log
sudo pppd call rg | tee "$LOG_FILE" | awk '{ print "[FNRG] " $0 }' &
PPPD_PID=$!

# Wait for PPP interface
echo "[FNRG] Waiting for PPP interface ppp0 to come up..."
for i in {1..20}; do
    if ip addr show ppp0 > /dev/null 2>&1; then
        echo "[FNRG] PPP interface ppp0 is up."
        break
    fi
    sleep 2
done

if ! ip addr show ppp0 > /dev/null 2>&1; then
    echo "[FNRG] Timeout: PPP interface ppp0 did not come up."
    cleanup
fi

# Enable forwarding
echo "[FNRG] Enabling IPv4 forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Restart DHCP server
echo "[FNRG] Restarting ISC DHCP server..."
sudo systemctl restart isc-dhcp-server

# Setup NAT (only if not already set)
if ! sudo iptables -t nat -C POSTROUTING -o ppp0 -j MASQUERADE 2>/dev/null; then
    echo "[FNRG] Setting up NAT (MASQUERADE)..."
    sudo iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE
else
    echo "[FNRG] NAT already configured. Skipping."
fi

# Get peer IP from log
echo "[FNRG] Waiting for PPPoE peer IP to be detected..."
for i in {1..10}; do
    DEST_IP=$(grep -oP 'remote IP address \K[\d.]+' "$LOG_FILE")
    if [ -n "$DEST_IP" ]; then break; fi
    sleep 1
done

if [ -z "$DEST_IP" ]; then
    echo "[FNRG] Error: Failed to detect peer IP from PPP log."
    cleanup
fi

echo "[FNRG] Detected PPPoE peer IP: $DEST_IP"

# Add route to 10.45.0.0/24
if ! ip route | grep -q "10.45.0.0/24"; then
    sudo ip route add 10.45.0.0/24 via "$DEST_IP"
    echo "[FNRG] Route to 10.45.0.0/24 via $DEST_IP added."
else
    echo "[FNRG] Route to 10.45.0.0/24 already exists."
fi

# Ping UPF
echo "[FNRG] Pinging 10.45.0.1 to verify connection..."
if ping -c 1 10.45.0.1 > /dev/null 2>&1; then
    echo "[FNRG] PDU session to UPF successfully established!"
else
    echo "[FNRG] Failed to reach UPF at 10.45.0.1."
fi

# Add route to 10.51.0.0/24
if ! ip route | grep -q "10.51.0.0/24"; then
    sudo ip route add 10.51.0.0/24 dev ppp0
    echo "[FNRG] Route to 10.51.0.0/24 via ppp0 added."
else
    echo "[FNRG] Route to 10.51.0.0/24 already exists."
fi

# Ping CU
echo "[FNRG] Pinging 10.51.0.88 to verify connection..."
if ping -c 1 10.51.0.88 > /dev/null 2>&1; then
    echo "[FNRG] PDU session to CU successfully established!"
else
    echo "[FNRG] Failed to reach CU at 10.51.0.88."
fi

# Keep script alive
wait $PPPD_PID

