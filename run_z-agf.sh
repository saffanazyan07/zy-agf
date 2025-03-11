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

# Run the pppoe-server with the retrieved IP
sudo pppoe-server -I "$INTERFACE" -L "$IP_ADDR" -N 2

echo "PPPoE server is running on $INTERFACE with IP $IP_ADDR."
