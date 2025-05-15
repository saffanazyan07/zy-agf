#!/bin/bash

echo "[INFO] Starting gNB with config: open5gs-gnb.yaml..."
build/nr-gnb -c config/open5gs-gnb.yaml &
GNB_PID=$!

sleep 2

echo "[INFO] Starting UE with config: open5gs-ue1.yaml..."
sudo build/nr-ue -c config/open5gs-ue1.yaml &
UE_PID=$!

sleep 2

INTERFACE="enp0s9"
IP_ADDR=$(ip -4 addr show uesimtun0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if [ -z "$IP_ADDR" ]; then
    echo "[ERROR] Failed to detect IP address on uesimtun0. Please check UE connectivity."
    exit 1
fi

TUNNEL_ID="tunnel_$(date +%s)"

# Cleanup ONLY when terminated (SIGINT or SIGTERM)
cleanup() {
    echo -e "\n[Z-AGF-INFO] Cleaning up all processes (manual termination)..."
    echo "[Z-AGF-INFO] Stopping PPPoE server..."
    sudo pkill pppoe-server
    echo "[Z-AGF-INFO] Stopping UE and gNB..."
    kill $GNB_PID 2>/dev/null
    kill $UE_PID 2>/dev/null
    kill $TAIL_PID1 2>/dev/null
    kill $TAIL_PID2 2>/dev/null
    echo "[Z-AGF-INFO] All processes have been terminated. Exiting."
    exit 0
}

# Trap only termination signals
trap cleanup SIGINT SIGTERM

echo "[INFO] Tunnel ID: $TUNNEL_ID | Interface: $INTERFACE | UE IP: $IP_ADDR" | tee -a tunnel_log.txt

echo "[INFO] Launching PPPoE server on $INTERFACE with IP $IP_ADDR..."
sudo pppoe-server -I "$INTERFACE" -L "$IP_ADDR" -N 2 > pppoe_server.log 2>&1 &
PPPOE_PID=$!

# Monitor main PPPoE log
( sudo tail -F /var/log/pppoe.log | awk '{ print "[Z-AGF-LOG] " $0 }' ) &
TAIL_PID1=$!

# Monitor custom PPPoE server log
( tail -F pppoe_server.log | awk '{ print "[Z-AGF-SERVER] " $0 }' ) &
TAIL_PID2=$!

# Wait for all child processes to finish naturally
wait $GNB_PID
wait $UE_PID
wait $PPPOE_PID
wait $TAIL_PID1
wait $TAIL_PID2

echo "[INFO] W-AGF procedure for FNRG1 completed successfully."
