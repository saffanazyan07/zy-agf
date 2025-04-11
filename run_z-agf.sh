#!/bin/bash

# Interface PPPoE akan jalan di enp0s9
INTERFACE="enp0s10"

# Generate a unique tunnel ID
TUNNEL_ID="tunnel_$(date +%s)"

# Cleanup function
cleanup() {
    echo -e "\n[Z-AGF] Terminating PPPoE server and log monitoring..."
    sudo pkill pppoe-server
    kill "$TAIL_PID" 2>/dev/null
    echo "[Z-AGF] Processes terminated. Exiting."
    exit 0
}
trap cleanup SIGINT SIGTERM

# Masuk ke build folder
cd ../../../cmake_targets/ran_build/build || exit 1

# Start gNB
echo "[Z-AGF] Starting nr-softmodem..."
sudo ./nr-softmodem --rfsim -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-du.sa.band78.106prb.rfsim.pci0.conf \
  2>&1 | sudo tee nr-du.log >/dev/null &
SOFTMODEM_PID=$!

# Delay
sleep 5

# Start UE
echo "[Z-AGF] Starting nr-uesoftmodem..."
sudo ./nr-uesoftmodem -C 3450720000 -r 106 --numerology 1 --ssb 516 -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf --rfsim \
  2>&1 | sudo tee nr-ue.log >/dev/null &
UESOFTMODEM_PID=$!

# Wait for interface oaitun_ue1 to appear
echo "[Z-AGF] Waiting for interface oaitun_ue1..."
sleep 5
for i in {1..30}; do
    IP_ADDR=$(ip -4 addr show oaitun_ue1 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$IP_ADDR" ]; then
        break
    fi
    sleep 1
done

# Jika IP tidak ditemukan, keluar
if [ -z "$IP_ADDR" ]; then
    echo "Error: Unable to find IP for oaitun_ue1 after waiting."
    cleanup
fi

# Log informasi tunnel
echo "[INFO] Tunnel ID: $TUNNEL_ID, Interface: $INTERFACE, IP: $IP_ADDR" | sudo tee -a tunnel_log.txt >/dev/null

# Jalankan PPPoE Server pada interface enp0s9, tapi pakai IP dari oaitun_ue1
echo "[Z-AGF] Starting PPPoE server on $INTERFACE using IP from oaitun_ue1 ($IP_ADDR)..."
sudo pppoe-server -I "$INTERFACE" -L "$IP_ADDR" -N 2 2>&1 | sudo tee pppoe_server.log >/dev/null &
PPPOE_PID=$!

# Monitor log
sudo tail -f /var/log/pppoe.log | awk '{ print "[Z-AGF] " $0 }' &
TAIL_PID=$!

sudo tail -f pppoe_server.log | awk '{ print "[Z-AGF] " $0 }' &

# Wait
wait $PPPOE_PID
wait $TAIL_PID
wait $SOFTMODEM_PID
wait $UESOFTMODEM_PID
