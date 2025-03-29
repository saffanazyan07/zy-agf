#!/bin/bash

# Interface to be used
INTERFACE="enp0s9"

# Get the IP address from the oaitun_ue1 interface
IP_ADDR=$(ip -4 addr show oaitun_ue1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Check if the IP address was found
if [ -z "$IP_ADDR" ]; then
    echo "Error: Unable to find IP for oaitun_ue1."
    exit 1
fi

# Generate a unique tunnel ID
TUNNEL_ID="tunnel_$(date +%s)"

# Function to handle termination
cleanup() {
    echo -e "\n[Z-AGF] Terminating PPPoE server and log monitoring..."
    sudo pkill pppoe-server
    kill "$TAIL_PID" 2>/dev/null
    echo "[Z-AGF] Processes terminated. Exiting."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM to trigger cleanup
trap cleanup SIGINT SIGTERM

# Change directory to the build folder
cd ran_build/build

# Run the nr-softmodem command
echo "[Z-AGF] Starting nr-softmodem..."
sudo ./nr-softmodem --rfsim -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-du.sa.band78.106prb.rfsim.pci0.conf &
SOFTMODEM_PID=$!

# Run the nr-uesoftmodem command
echo "[Z-AGF] Starting nr-uesoftmodem..."
sudo ./nr-uesoftmodem -C 3450720000 -r 106 --numerology 1 --ssb 516 -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf &
UESOFTMODEM_PID=$!

# Log the tunnel ID and IP
echo "[INFO] Tunnel ID: $TUNNEL_ID, Interface: $INTERFACE, IP: $IP_ADDR" | tee -a tunnel_log.txt

# Start PPPoE server and redirect logs
sudo pppoe-server -I "$INTERFACE" -L "$IP_ADDR" -N 2 >pppoe_server.log 2>&1 &
PPPOE_PID=$!

echo "[INFO] PPPoE server is running with PID $PPPOE_PID on $INTERFACE with IP $IP_ADDR and Tunnel ID $TUNNEL_ID."

# Monitor the PPPoE server log with cleaner prefixes
sudo tail -f /var/log/pppoe.log | awk '{ print "[Z-AGF] " $0 }' &
TAIL_PID=$!

# Monitor the custom PPPoE server logs
tail -f pppoe_server.log | awk '{ print "[Z-AGF] " $0 }' &

# Wait for processes to finish
wait $PPPOE_PID
wait $TAIL_PID
wait $SOFTMODEM_PID
wait $UESOFTMODEM_PID
