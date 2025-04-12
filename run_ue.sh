
#!/bin/bash

LOG_FILE="/tmp/dhcp.log"
L2TP_LOG_FILE="/tmp/l2tp.log"
INTERFACE="enp0s9"
FNRG_IP="10.61.0.100"

cleanup() {
    echo -e "\n[N5GC] Terminating DHCP client..."
    sudo dhclient -r $INTERFACE
    echo "[N5GC] DHCP client released."

    echo -e "\n[N5GC] Terminating L2TP connection..."
    sudo xl2tpd-control disconnect-lac n5gc
    sudo systemctl stop xl2tpd
    echo "[N5GC] L2TP connection terminated."

    exit 0
}

trap cleanup SIGINT SIGTERM

# Start DHCP client and log
echo "[N5GC] Requesting IP address via DHCP on $INTERFACE..."
sudo dhclient -v $INTERFACE 2>&1 | tee "$LOG_FILE" | awk '{ print "[N5GC] " $0 }' &

# Wait until IP assigned
echo "[N5GC] Waiting for IP assignment on $INTERFACE..."
for i in {1..10}; do
    IP_ADDR=$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$IP_ADDR" ]; then
        break
    fi
    sleep 2
done

if [ -z "$IP_ADDR" ]; then
    echo "[N5GC] Failed to get IP address from DHCP."
    cleanup
fi

echo "[N5GC] Got IP address $IP_ADDR on $INTERFACE."

# Add static routes
sudo ip route add 10.45.0.0/24 via "$IP_ADDR"
sudo ip route add 10.50.0.0/24 via $FNRG_IP
sudo ip route add 10.51.0.0/24 via $FNRG_IP
echo "[N5GC] Static routes added."

# Test UPF
echo "[N5GC] Pinging 10.45.0.1 to verify connection..."
if ping -c 1 10.45.0.1 > /dev/null 2>&1; then
    echo "[N5GC] PDU session to UPF successfully established!"
else
    echo "[N5GC] Failed to reach UPF at 10.45.0.1."
fi

# Start L2TP connection
echo "[N5GC] Restarting xl2tpd service..."
sudo systemctl restart xl2tpd
sleep 3

echo "[N5GC] Initiating L2TP connection..."
sudo xl2tpd-control connect-lac n5gc
sleep 2

# Add route for L2TP subnet
sudo ip route add 10.46.0.0/24 dev $INTERFACE
echo "[N5GC] Route to 10.46.0.0/24 via $INTERFACE added successfully."

# Test L2TP tunnel
echo "[N5GC] Pinging 10.46.0.1 to verify connection..."
if ping -c 1 10.46.0.1 > /dev/null 2>&1; then
    echo "[N5GC] Connection to 10.46.0.1 is successful!"
else
    echo "[N5GC] Failed to reach 10.46.0.1."
fi

# Monitor L2TP log
echo "[N5GC] Monitoring L2TP logs..."
sudo journalctl -u xl2tpd -f | tee "$L2TP_LOG_FILE" &

# Wait to keep script alive
wait
