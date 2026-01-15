#!/bin/bash

INTERFACE="enp0s9"
TEMP_PPP_IP="10.99.99.1"

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
sudo ./z-agf --rfsim -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/gnb-du.sa.band78.106prb.rfsim.pci1.conf \
  2>&1 | sudo tee nr-du.log >/dev/null &
SOFTMODEM_PID=$!

# --- 2. Start PPPoE server with dummy IP
echo "[Z-AGF] Starting PPPoE server with temp IP $TEMP_PPP_IP..."
sudo pppoe-server -I "$INTERFACE" -L "$TEMP_PPP_IP" -N 10 2>&1 | tee pppoe_server.log &
PPPOE_PID=$!

# --- 3. Wait for IMSI from PPPoE log
echo "[Z-AGF] Waiting for IMSI from PPPoE log..."

# Cari IMSI dari log dalam 30 detik
for i in {1..30}; do
    imsi=$(strings /var/log/pppoe.log | grep -oP 'EAP: unauthenticated peer name "\K[0-9]+' | tail -n 1)
    if [[ -n "$imsi" ]]; then
        echo "[Z-AGF] Got IMSI from PPPoE log: $imsi"
        break
    fi
    sleep 1
done

if [[ -z "$imsi" ]]; then
    echo "[Z-AGF] ERROR: No IMSI received."
    kill $PPPOE_PID $SOFTMODEM_PID
    exit 1
fi

# Delay
sleep 5

# Start UE
echo "[Z-AGF] Starting nr-uesoftmodem..."
sudo ./nr-uesoftmodem -C 3649440000 -r 106 --numerology 1 --ssb 516 -O ../../../targets/PROJECTS/GENERIC-NR-5GC/CONF/ue.conf --uicc0.imsi "$imsi" --rfsim \
  2>&1 | sudo tee nr-ue.log >/dev/null &
UESOFTMODEM_PID=$!

# Wait for interface proxy-ue1 to appear
echo "[Z-AGF] Waiting for interface proxy-ue1..."
sleep 5
for i in {1..30}; do
    IP_ADDR=$(ip -4 addr show proxy-ue1 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [ -n "$IP_ADDR" ]; then
        break
    fi
    sleep 1
done

# Jika IP tidak ditemukan, keluar
if [ -z "$IP_ADDR" ]; then
    echo "Error: Unable to find IP for proxy-ue1 after waiting."
    cleanup
fi
# Tambahan konfigurasi setelah interface proxy-ue1 aktif
echo "[Z-AGF] Enabling IPv4 forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1

echo "[Z-AGF] Setting up NAT (MASQUERADE) for proxy-ue1..."
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/24 -o proxy-ue1 -j MASQUERADE

echo "[Z-AGF] Adding route to 10.45.0.0/24 via proxy-ue1..."
sudo ip route add 10.45.0.0/24 dev proxy-ue1

# Log informasi tunnel
echo "[INFO] Tunnel ID: $TUNNEL_ID, Interface: $INTERFACE, IP: $IP_ADDR" | sudo tee -a tunnel_log.txt >/dev/null

# Jalankan PPPoE Server pada interface enp0s9, tapi pakai IP dari proxy-ue1
# --- 6. Restart PPPoE server with real tunnel IP
echo "[Z-AGF] Restarting PPPoE server with IP $IP_ADDR..."
sudo pkill pppoe-server
echo "$imsi → $IP_ADDR" >> connected_sessions.log
sleep 1
echo "[Z-AGF] Starting PPPoE server on $INTERFACE using IP from proxy-ue1 ($IP_ADDR)..."
sudo pppoe-server -I "$INTERFACE" -L "$IP_ADDR" -N 10 2>&1 | sudo tee pppoe_server.log >/dev/null &
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
