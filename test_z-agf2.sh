#!/usr/bin/env bash
set -e

#####################################
# Z-AGF : Access Gateway Function
#####################################

### === CONFIG FILE ===
CONFIG_FILE="${1:-conf/z-agf.yaml}"

### === CHECK DEPENDENCIES ===
for cmd in yq ip iptables pppoe-server; do
    command -v $cmd >/dev/null 2>&1 || {
        echo "[ERROR] $cmd not found"
        exit 1
    }
done

### === LOAD CONFIG FROM YAML ===
INTERFACE=$(yq e '.pppoe.interface' "$CONFIG_FILE")
PPPOE_SESSIONS=$(yq e '.pppoe.sessions' "$CONFIG_FILE")
SUBNET=$(yq e '.pppoe.subnet' "$CONFIG_FILE")

UE_IF=$(yq e '.oai.ue_interface' "$CONFIG_FILE")
GNB_CONF=$(yq e '.oai.gnb_conf' "$CONFIG_FILE")
UE_CONF=$(yq e '.oai.ue_conf' "$CONFIG_FILE")

### === VALIDATION ===
for var in INTERFACE PPPOE_SESSIONS SUBNET UE_IF GNB_CONF UE_CONF; do
    [ -z "${!var}" ] && echo "[ERROR] $var missing in YAML" && exit 1
done

### === PATH SETUP ===
BASE_DIR=$(pwd)
LOG_DIR="$BASE_DIR/logs"
RUN_DIR="$BASE_DIR/run"

mkdir -p "$LOG_DIR" "$RUN_DIR"

TUNNEL_ID="z-agf-$(date +%s)"

#####################################
# CLEANUP
#####################################
cleanup() {
    echo -e "\n[Z-AGF] Cleaning up..."

    for pidfile in "$RUN_DIR"/*.pid; do
        if [ -f "$pidfile" ]; then
            kill "$(cat "$pidfile")" 2>/dev/null || true
        fi
    done

    sudo iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$UE_IF" -j MASQUERADE 2>/dev/null || true
    sudo ip route del "$SUBNET" dev "$UE_IF" 2>/dev/null || true

    echo "[Z-AGF] Cleanup complete."
    exit 0
}
trap cleanup SIGINT SIGTERM

#####################################
# START OAI gNB
#####################################
echo "[Z-AGF] Starting gNB..."
cd ../../../cmake_targets/ran_build/build || {
    echo "[ERROR] Cannot find OAI build dir"
    exit 1
}

sudo ./nr-softmodem --rfsim -O "$GNB_CONF" \
    > "$LOG_DIR/nr-du.log" 2>&1 &
echo $! > "$RUN_DIR/gnb.pid"

sleep 5

#####################################
# START OAI UE
#####################################
echo "[Z-AGF] Starting UE..."
sudo ./nr-uesoftmodem --rfsim -O "$UE_CONF" \
    > "$LOG_DIR/nr-ue.log" 2>&1 &
echo $! > "$RUN_DIR/ue.pid"

#####################################
# WAIT FOR UE INTERFACE
#####################################
echo "[Z-AGF] Waiting for UE interface: $UE_IF"

for i in {1..30}; do
    UE_IP=$(ip -4 addr show "$UE_IF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -n "$UE_IP" ] && break
    sleep 1
done

[ -z "$UE_IP" ] && echo "[ERROR] UE interface not ready" && cleanup

echo "[Z-AGF] UE IP acquired: $UE_IP"

#####################################
# NETWORK SETUP
#####################################
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
sudo iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$UE_IF" -j MASQUERADE
sudo ip route add "$SUBNET" dev "$UE_IF"

#####################################
# START PPPoE SERVER
#####################################
echo "[Z-AGF] Starting PPPoE server on $INTERFACE"
sudo pppoe-server \
    -I "$INTERFACE" \
    -L "$UE_IP" \
    -N "$PPPOE_SESSIONS" \
    > "$LOG_DIR/pppoe.log" 2>&1 &
echo $! > "$RUN_DIR/pppoe.pid"

#####################################
# STATUS
#####################################
echo "======================================="
echo "[Z-AGF] ACTIVE"
echo " Tunnel ID : $TUNNEL_ID"
echo " Interface : $INTERFACE"
echo " UE IP     : $UE_IP"
echo " Sessions  : $PPPOE_SESSIONS"
echo "======================================="

wait
