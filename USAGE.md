# VirtualBox Lab Automation - Usage Guide

## Table of Contents

- [Workflow Overview](#-workflow-overview)
- [Main Controller Script](#-main-controller-script)
- [Individual Script Usage](#-individual-script-usage)
- [Configuration Files](#-configuration-files)
- [Advanced Operations](#-advanced-operations)
- [Troubleshooting](#-troubleshooting)
- [FAQs](#-faqs)

## 🔄 Workflow Overview

The typical provisioning workflow follows these stages:

1. **Configuration**  
   `00_config.sh` → Load settings from YAML/CSV files

2. **Infrastructure Creation**  
   `01_create_vms.sh` → VM resource allocation  
   `02_install_os.sh` → Operating system installation

3. **Network Setup**  
   `03_setup_networks.sh` → Network configuration

4. **Provisioning**  
   `04_provision_vms.sh` → Software installation

5. **Validation**  
   `05_validate.sh` → System health checks

## 🎛️ Main Controller Script

### `main.sh` Options

```bash
./main.sh [OPTIONS]
```

`-a`, `--all` -
`-c`, `--create`
`-i`, `--install`
`-n`, `--network`
`-p`, `--provision`
`-v`, `--validate`
`-h`, `--help`

### Common Use Cases

**1. Full Environment Setup**

```bash
./main.sh --all
```

**2. Create VMs and Configure Networks**

```bash
./main.sh --create --network
```

**3. Re-provision Existing Environment**

```bash
./main.sh --install --provision --validate
```

## 📜 Individual Script Usage

### 1. `00_config.sh` - Configuration Loader

```bash
# Source the configuration
source ./scripts/00_config.sh

# Access configuration values
echo "Host-only network IP: ${HOST_ONLY_NET_IP}"
```

### 2. `01_create_vms.sh` - VM Creation

```bash
# Create specific VM
./scripts/01_create_vms.sh web-server

# Create all VMs from config
./scripts/01_create_vms.sh --all
```

### 3. `02_install_os.sh` - OS Installation

```bash
# Install OS on specific VM
./scripts/02_install_os.sh web-server ubuntu-22.04.iso

# Batch install using default ISO
./scripts/02_install_os.sh --all
```

### 4. `03_setup_networks.sh` - Network Management

```bash
# Network operations
./scripts/03_setup_networks.sh [command]

# Commands:
#   setup       - Configure networks
#   teardown    - Remove network configs
#   status      - Show current state
#   validate    - Check network health

# Example: Full network reset
./scripts/03_setup_networks.sh teardown
./scripts/03_setup_networks.sh setup
```

### 5. `04_provision_vms.sh` - Software Provisioning

```bash
# Provision specific VM
./scripts/04_provision_vms.sh web-server

# Provision all VMs
./scripts/04_provision_vms.sh --all
```

### 6. `05_validate.sh` - System Validation

```bash
# Run full validation suite
./scripts/05_validate.sh

# Check specific aspect
./scripts/05_validate.sh --network
./scripts/05_validate.sh --storage
```

## ⚙️ Configuration Files

### `network_config.yaml` Structure

```yaml
networks:
  host_only:
    name: lab-net
    base_ip: 192.168.99.0
    netmask: 255.255.255.0
    dhcp: false
    vms: [web, db]

  nat:
    name: public-net
    base_ip: 10.0.99.0/24
    dhcp: true
    vms: [web]
```

### `vm_configs.csv` Format

```csv
# Columns:
# Name, OS Type, Memory (MB), CPUs, Storage (MB)
web-server,Ubuntu_64,4096,4,25600
db-server,Ubuntu_64,2048,2,20480
```

## 🔧 Advanced Operations

### Parallel Execution

```bash
# Create VMs in parallel (GNU Parallel required)
parallel -j 2 ./scripts/01_create_vms.sh ::: web-server db-server
```

### Custom ISO Handling

```bash
# Use alternative ISO for installation
./scripts/02_install_os.sh web-server custom-ubuntu.iso

# Set default ISO for all installations
export DEFAULT_ISO="debian-12.iso"
./main.sh --install
```

### Network Debugging

```bash
# Capture network traffic
VBoxManage modifyvm web-server --nictrace1 on --nictracefile1 web-server.pcap

# Analyze DHCP requests
tcpdump -nn -r web-server.pcap port 67 or port 68
```

## 🚨 Troubleshooting

### Common Issues

**1. Dependency Errors**

```bash
# Verify installed packages
./scripts/utils/checks.sh --verify

# Install missing dependencies
sudo ./scripts/utils/checks.sh --install-deps
```

**2. Network Conflicts**

```bash
# Check for conflicting networks
VBoxManage list hostonlyifs
VBoxManage list natnets

# Reset network configurations
./scripts/03_setup_networks.sh teardown
./scripts/03_setup_networks.sh setup
```

**3. VM Creation Failures**

```bash
# Check VirtualBox logs
tail -n 100 ~/.config/VirtualBox/VBoxSVC.log

# Verify available resources
VBoxManage list systemproperties | grep -E 'Memory|CPUs'
```

**4. Provisioning Errors**

```bash
# Check provisioning logs
tail -f logs/lab_setup.log

# Rerun provisioning for failed VM
./scripts/04_provision_vms.sh web-server --retry
```

## ❓ FAQs

**Q: How do I add a new VM to an existing environment?**

1. Add entry to `vm_configs.csv`
2. Update `network_config.yaml`
3. Run:

```bash
./main.sh --create --network --provision
```

**Q: Can I use this with VMware or other hypervisors?**  
A: Currently only supports VirtualBox, but contributions for other platforms are welcome!

**Q: How to change the default network ID?**  
A: Modify `NET_ID` in `network_config.yaml` under `variables` section.

**Q: Where are the VM files stored?**  
A: All VM data is stored in the `vms/` directory at the project root.

**Q: How to upgrade an existing VM's resources?**

```bash
# 1. Update vm_configs.csv
# 2. Destroy and recreate VM
./scripts/01_create_vms.sh web-server --force-recreate
```

---

**📝 Note:** Always check the logs in `logs/` directory for detailed operation records.

```

```
