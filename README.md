# Installation Guide
Create Tun in CU
```
sudo ip tuntap add mode tun gtp-tun0
sudo ip addr add 10.45.0.88/24 dev gtp-tun0
sudo ip link set gtp-tun0 up
```
Create Tun in AGF
```
sudo ip tuntap add mode tun gtp-tun0
sudo ip addr add 10.45.0.99/24 dev gtp-tun0
sudo ip link set gtp-tun0 up
```
