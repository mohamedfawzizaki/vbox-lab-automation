#!/bin/bash

# Global Configuration
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/configs"
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/iso"
VMS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/vms"


# VirtualBox Settings
VBOX_MANAGE="VBoxManage"
VBOX_USER="vbox"

# VM Defaults   
DEFAULT_VM_MEMORY=2048
DEFAULT_VM_CPUS=2
DEFAULT_VM_DISK=20480  # 20GB in MB
DEFAULT_OS_TYPE="Ubuntu_64"

# Network Configuration Functions
configure_networks() {
    # Load and parse YAML configuration
    if [ -f "${CONFIG_DIR}/network_config.yaml" ]; then
        log_info "Loading network configuration"
        
        # Clean any existing NET_ variables
        unset $(set | grep '^NET_' | cut -d= -f1)
        
        # Parse YAML
        eval "$(parse_yaml "${CONFIG_DIR}/network_config.yaml" "NET_")"
        
        # Set NET_ID from YAML or default
        NET_ID="${NET_variables_NET_ID:-99}"
        export NET_ID

        # Process host-only network
        if [ "${NET_networks_host_only_enabled}" = "true" ]; then
            NET_NETWORK_HOST_ONLY_ENABLED="${NET_networks_host_only_enabled}"
            HOST_ONLY_NET_NAME=$(expand_var "${NET_networks_host_only_name}")
            HOST_ONLY_NET_IP=$(expand_var "${NET_networks_host_only_base_ip}")
            HOST_ONLY_NET_MASK="${NET_networks_host_only_netmask}"
            HOST_ONLY_NET_DHCP="${NET_networks_host_only_dhcp}"
            
            # Process VM assignments
            HOST_ONLY_VMS=()
            local i=1
            while true; do
                local var_name="NET_networks_host_only_vms_${i}"
                local vm_name="${!var_name}"
                [ -z "$vm_name" ] && break
                
                # Clean VM name (remove special characters and whitespace)
                vm_name=$(clean_vm_name "$vm_name")
                HOST_ONLY_VMS+=("$vm_name")
                ((i++))
            done
            log_info "Host-only VMs: ${HOST_ONLY_VMS[*]}"
        fi

        # Process NAT network
        if [ "${NET_nat_enabled}" = "true" ]; then
            NAT_NET_ENABLED="${NET_nat_enabled}"
            NAT_NET_NAME=$(expand_var "${NET_nat_name}")
            NAT_NET_IP=$(expand_var "${NET_nat_base_ip}")
            NAT_NET_DHCP="${NET_nat_dhcp}"

            # Process VM assignments
            Nat_VMS=()
            local i=1
            while true; do
                local var_name="NET_nat_vms_${i}"
                local vm_name="${!var_name}"
                [ -z "$vm_name" ] && break
                
                # Clean VM name (remove special characters and whitespace)
                vm_name=$(clean_vm_name "$vm_name")
                Nat_VMS+=("$vm_name")
                ((i++))
            done
            log_info "Nat VMs: ${Nat_VMS[*]}"
        fi

        # Process Internal network
        if [ "${NET_internal_enabled}" = "true" ]; then
            NAT_INTERNAL_ENABLED="${NET_internal_enabled}"
            NAT_INTERNAL_NAME=$(expand_var "${NET_internal_name}")
            NAT_INTERNAL_IP=$(expand_var "${NET_internal_base_ip}")
            NAT_INTERNAL_DHCP="${NET_internal_dhcp}"

            # Process VM assignments
            Internal_VMS=()
            local i=1
            while true; do
                local var_name="NET_internal_vms_${i}"
                local vm_name="${!var_name}"
                [ -z "$vm_name" ] && break
                
                # Clean VM name (remove special characters and whitespace)
                vm_name=$(clean_vm_name "$vm_name")
                Internal_VMS+=("$vm_name")
                ((i++))
            done
            log_info "Internal VMs: ${Internal_VMS[*]}"
        fi

        # Process Bridged network
        if [ "${NET_bridged_enabled}" = "true" ]; then
            NAT_BRIDGED_ENABLED="${NET_bridged_enabled}"
            NAT_BRIDGED_NAME=$(expand_var "${NET_bridged_name}")
            NAT_BRIDGED_IP=$(expand_var "${NET_bridged_base_ip}")
            NAT_BRIDGED_DHCP="${NET_bridged_dhcp}"
            NAT_BRIDGED_INTERFACE="${NET_bridged_interface_dhcp}"

            # Process VM assignments
            Bridged_VMS=()
            local i=1
            while true; do
                local var_name="NET_Bridged_vms_${i}"
                local vm_name="${!var_name}"
                [ -z "$vm_name" ] && break
                
                # Clean VM name (remove special characters and whitespace)
                vm_name=$(clean_vm_name "$vm_name")
                Bridged_VMS+=("$vm_name")
                ((i++))
            done
            log_info "Bridged VMs: ${Bridged_VMS[*]}"
        fi
    else
        log_warning "Using default network configuration"
        NET_ID=99
        HOST_ONLY_NET_NAME="vboxnet${NET_ID}"
        HOST_ONLY_NET_IP="192.168.${NET_ID}.1"
        HOST_ONLY_NET_MASK="255.255.255.0"
        HOST_ONLY_NET_DHCP="false"
        NAT_NET_NAME="natnet${NET_ID}"
        NAT_NET_IP="10.0.${NET_ID}.0/24"
        NAT_NET_DHCP="true"
    fi
}

expand_var() {
    local input="$1"
    # Replace ${NET_ID} or $NET_ID with actual value
    echo "${input}" | sed \
        -e "s/\${NET_ID}/${NET_ID}/g" \
        -e "s/\$NET_ID/${NET_ID}/g"
}

clean_vm_name() {
    local vm_name="$1"
    # Remove leading/trailing whitespace and special characters
    echo "$vm_name" | sed -e 's/^[[:space:]-]*//' -e 's/[[:space:]-]*$//'
}

# Load utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils/checks.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils/yaml.sh"

# Load network configuration
configure_networks

# Convert to Unix-style line endings
sed -i 's/\r$//' "${CONFIG_DIR}/vm_configs.csv"

# Load VM configurations
if [ -f "${CONFIG_DIR}/vm_configs.csv" ]; then
    declare -A VM_CONFIGS

    while IFS=',' read -r vm_name os_type memory cpus disk_size networks || [ -n "$vm_name" ]; do
        # Trim leading/trailing whitespace from each field
        vm_name="$(echo "$vm_name" | xargs)"
        [[ "$vm_name" =~ ^#.*$ || -z "$vm_name" ]] && continue

        os_type="$(echo "$os_type" | xargs)"
        memory="$(echo "$memory" | xargs)"
        cpus="$(echo "$cpus" | xargs)"
        disk_size="$(echo "$disk_size" | xargs)"
        networks="$(echo "$networks" | xargs)"

        VM_CONFIGS["$vm_name"]="${os_type},${memory},${cpus},${disk_size},${networks}"
    done < <(grep -v '^\s*#' "${CONFIG_DIR}/vm_configs.csv")
fi
