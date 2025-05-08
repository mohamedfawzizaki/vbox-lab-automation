VirtualBox Lab Automation Suite (VirtualBox - Bash Script - YAML)

Automated provisioning of complex virtual environments with multi-network support

📜 Table of Contents

- [Features](-features)
- [Project Structure](-project-structure)
- [Prerequisites](-prerequisites)
- [Installation](-installation)
- [Usage](-usage)
- [Configuration](-configuration)
- [Script Reference](-script-reference)
- [Troubleshooting](-troubleshooting)
- [Examples](-examples)
- [Contributing](-contributing)
- [License](-license)

✨ Features

- Multi-Network Topologies
  - Host-only, NAT, Internal & Bridged networks
  - YAML-defined network configurations
- Infrastructure as Code
  - CSV-based VM specifications
  - Declarative provisioning
- Automation Framework
  - End-to-end provisioning pipeline
  - Validation & health checks
  - Comprehensive logging
- Modular Design
  - Reusable utility scripts
  - Customizable workflows

📂 Project Structure

```
my-project/
├── configs/
│   ├── network_config.yaml        Network definitions
│   ├── vm_configs.csv             VM hardware specs
│   └── vm_provisioning.csv        Software roles
├── iso/                           OS images
├── logs/                          Operation logs
├── scripts/
│   ├── 00_config.sh               Config loader
│   ├── 01_create_vms.sh           VM creation
│   ├── 02_install_os.sh           OS installation
│   ├── 03_setup_networks.sh       Network config
│   ├── 04_provision_vms.sh        Software setup
│   ├── 05_validate.sh             Health checks
│   └── utils/                     Helper scripts
│       ├── checks.sh              Dependency validation
│       ├── logging.sh             Logging system
│       └── yaml.sh                YAML parser
├── vms/                           Vms folder
├── main.sh                        Main controller
└── README.md                      This document
└── USAGE.md                       Advanced usage
```

🛠️ Prerequisites

- VirtualBox 7.0+
- Bash 4.4+
- `yq` (YAML processor)
- SSH client
- 10GB+ free disk space

```bash
 Ubuntu/Debian setup
sudo apt update && sudo apt install -y \
    virtualbox \
    yq \
    ssh-askpass \
    git
```

📥 Installation

1. Clone repository:

```bash
git clone https://github.com/yourusername/virtualbox-automation.git
cd virtualbox-automation
```

2. Install dependencies:

```bash
sudo scripts/utils/install_dependenies.sh
```

3. Configure environment:

```bash
cp configs/network_config.example.yaml configs/network_config.yaml
cp configs/vm_configs.example.csv configs/vm_configs.csv
```

🚀 Usage

Full Provisioning

```bash
./main.sh --all
```

Individual Components

```bash
 Create VMs only
./main.sh --create-vms

 Install OS on existing VMs
./main.sh --install-os

 Configure networks
./main.sh --networks

 Validate setup
./scripts/05_validate.sh
```

🔧 Configuration

Network Setup (`network_config.yaml`)

```yaml
networks:
  host_only:
    name: lab-network
    base_ip: 192.168.99.0
    netmask: 255.255.255.0
    dhcp: false
    vms:
      - web-server
      - db-server

  nat:
    name: public-access
    base_ip: 10.0.99.0/24
    dhcp: true
    vms:
      - web-server
```

VM Specifications (`vm_configs.csv`)

```csv
 Format: name,ostype,memory(MB),cpus,storage(MB)
web-server,Ubuntu_64,4096,4,25600
db-server,Ubuntu_64,2048,2,20480
```

Provisioning Roles (`vm_provisioning.csv`)

```csv
 Format: vm_name,ip,role
web-server,192.168.99.10,nginx
db-server,192.168.99.20,mysql
```

📜 Script Reference

Workflow Scripts

`00_config.sh`  
 `01_create_vms.sh`  
 `02_install_os.sh`  
 `03_setup_networks.sh`
`04_provision_vms.sh`
`05_validate.sh`

Utility Modules

- checks.sh: Verifies dependencies and system state
- logging.sh: Unified logging system with color output
- yaml.sh: Advanced YAML parser with nesting support

🚨 Troubleshooting

Common Issues
VM Creation Fails

```bash
 Check VirtualBox permissions
sudo usermod -aG vboxusers $USER

 Verify available resources
VBoxManage list systemproperties | grep "Memory"
```

Network Connectivity Issues

```bash
 Reset network configurations
./scripts/03_setup_networks.sh teardown
./scripts/03_setup_networks.sh setup

 Validate NAT rules
VBoxManage list natnets
```

YAML Parsing Errors

```bash
 Validate configuration file
yq eval configs/network_config.yaml

 Check for tabs (must use spaces)
grep -P '\t' configs/network_config.yaml
```

🧩 Examples

Web Application Stack

```bash
 network_config.yaml
networks:
  host_only:
    name: lab-network
    base_ip: 192.168.99.0
    netmask: 255.255.255.0
    dhcp: false
    vms:
      - web-server
      - db-server

  nat:
    name: public-access
    base_ip: 10.0.99.0/24
    dhcp: true
    vms:
      - web-server

 vm_provisioning.csv
web-server,192.168.99.10,nginx
db-server,192.168.99.20,mysql
```

Development Environment

```bash
 Single VM setup
./main.sh --create-vms --networks

 Connect via SSH
ssh developer@192.168.99.10 -p 2222
```

🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -am 'Add new feature'`)
4. Push to branch (`git push origin feature/improvement`)
5. Open Pull Request

Maintained by: [Mohamed Fawzi zaki]
