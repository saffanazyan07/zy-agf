
# Z-AGF

## Overview

Z-AGF (Wireline Access Gateway Function) is a module designed to integrate wireline access into a 5G system. It serves as an intermediary component enabling seamless connectivity between wireline networks and 5G core components. the source code is for simple test ORAN based Z-AGF and 5GC based W-AGF

## Build pppoe and L2TP in AGF, FNRG, N5GC
   
# Z-AGF

## Overview
Z-AGF (Wireline Access Gateway Function) is a module designed to integrate wireline access into a 5G system. It serves as an intermediary component enabling seamless connectivity between wireline networks and 5G core components.

## Features
- Supports F1AP for communication with CU (Central Unit)
- Implements IPsec tunnels for secure data transmission
- Handles DHCP and authentication mechanisms for UE identification
- Designed for local breakout support
- Compatible with Open RAN systems

## Directory Structure
```
├── src               # Source code
│   ├── asn           # ASN.1 encoding/decoding
│   ├── f1ap          # F1AP protocol implementation
│   ├── ipsec         # IPsec tunnel configuration
│   ├── transport     # Transport layer functions
│   ├── dhcp          # DHCP server and client handlers
│   ├── authentication # Authentication mechanisms
│   └── utils         # Utility functions
├── config            # Configuration files
├── docs              # Documentation
├── scripts           # Helper scripts for setup and debugging
└── README.md         # Project documentation
```

## Installation
### Prerequisites
Ensure you have the following dependencies installed:
- **GCC** (for compilation)
- **CMake** (for build system)
- **OpenSSL** (for encryption and secure communications)
- **libgtp5gnl** (for GTP-U handling)
- **StrongSwan** (for IPsec support)

### Build Instructions
```bash
git clone https://github.com/saffanazyan07/zy-agf.git
cd z-agf
```

## Configuration
Modify the `config.yaml` file to set up interfaces, IP ranges, and authentication mechanisms. Example:
```yaml
network:
  interface: "eth0"
  ip_range: "192.168.60.0/24"
authentication:
  method: "EAP"
ipsec:
  enable: true
  psk: "your-secret-key"
```

## Usage
To start the Z-AGF module, run:
```bash
./z-agf --config=config/config.yaml
```
To enable debugging:
```bash
./z-agf --config=config/config.yaml --debug
```

## Troubleshooting
### 1. Compilation Issues
Ensure all dependencies are installed and run:
```bash
cmake ..
make clean && make -j$(nproc)
```

### 2. IPsec Tunnel Not Establishing
Check logs using:
```bash
dmesg | grep ipsec
journalctl -u strongswan
```

### 3. F1AP Connection Failing
Verify that the CU is reachable and that F1AP messages are being exchanged correctly:
```bash
sudo chmod +x <file.sh>
```

## Contributing
1. Fork the repository.
2. Create a feature branch (`git checkout -b feature-name`).
3. Commit your changes (`git commit -m "Add feature"`).
4. Push to the branch (`git push origin feature-name`).
5. Submit a pull request.

## License
This project is licensed under the MIT License. See the LICENSE file for details.

## Contact
For support or inquiries, reach out via email at `support@example.com` or open an issue on GitHub.

