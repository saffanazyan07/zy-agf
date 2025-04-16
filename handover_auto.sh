#!/bin/bash

# Fungsi untuk ambil IP dari interface
get_ip() {
  ip -4 addr show "$1" | grep -oP '(?<=inet\s)\d+(\.\d+){3}'
}

IF1="enp0s9"
IF2="enp0s10"

IP1=$(get_ip "$IF1")
IP2=$(get_ip "$IF2")

echo "[INFO] IP $IF1: $IP1"
echo "[INFO] IP $IF2: $IP2"

if [[ -n "$IP1" && -z "$IP2" ]]; then
  echo "[Handover] $IF1 ($IP1) aktif, switch ke $IF2"
  sudo dhclient -v $IF2

  echo "[Route] Adding route: 10.51.0.0/24 via 10.61.0.100"
  sudo ip route add 10.50.0.0/24 via 10.71.0.100

  echo "[Handover] Connecting L2TP tunnel (n5gc0)..."
  sudo xl2tpd-control connect-lac n5gc0

  echo "[Handover] disonnecting L2TP tunnel (n5gc0)..."
  sudo dhclient -r $IF1
  sudo xl2tpd-control disconnect-lac n5gc

elif [[ -z "$IP1" && -n "$IP2" ]]; then
  echo "[Handover] $IF2 ($IP2) aktif, switch ke $IF1"
  sudo dhclient -v $IF1

  echo "[Route] Adding route: 10.51.0.0/24 via 10.61.0.100"
  sudo ip route add 10.51.0.0/24 via 10.61.0.100

  echo "[Handover] Connecting L2TP tunnel (n5gc)..."
  sudo xl2tpd-control connect-lac n5gc

  echo "[Handover] disconnecting L2TP tunnel (n5gc0)..."
  sudo dhclient -r $IF2
  sudo xl2tpd-control disconnect-lac n5gc0

else
  echo "[ERROR] Tidak bisa menentukan interface aktif. Pastikan hanya satu aktif!"
  exit 1
fi

echo "[Handover] Waiting 10 seconds..."
sleep 30

echo "[Handover] Pinging 10.46.0.1..."
ping -c 1 10.46.0.1
