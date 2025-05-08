#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

# Main network setup function
setup_networks() {
    log_info "Starting network configuration"
    
    # Create networks
    setup_hostonly_network
    setup_nat_network
    setup_bridge_network
    # Configure VMs
    configure_vm_networks
    
    # Validate setup
    validate_networks
    
    log_success "Network setup completed successfully"
}

# Host-only network configuration
setup_hostonly_network() {
    log_info "Configuring host-only network: ${HOST_ONLY_NET_NAME}"
    
    # Check if interface exists, create if not
    if ! ${VBOX_MANAGE} list hostonlyifs | grep -q "${HOST_ONLY_NET_NAME}"; then
        log_info "Creating host-only interface"
        local if_output=$(${VBOX_MANAGE} hostonlyif create 2>&1)
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create host-only interface: $if_output"
            exit 1
        fi
        
        # Extract and validate interface name
        HOST_ONLY_NET_NAME=$(echo "${if_output}" | grep -oP 'vboxnet\d+')
        if [[ -z "${HOST_ONLY_NET_NAME}" ]]; then
            log_error "Could not determine created interface name"
            exit 1
        fi
        log_info "Created interface: ${HOST_ONLY_NET_NAME}"
    fi
    
    # Configure IP settings with validation
    log_info "Configuring IP ${HOST_ONLY_NET_IP}/${HOST_ONLY_NET_MASK}"
    if ! "${VBOX_MANAGE}" hostonlyif ipconfig "${HOST_ONLY_NET_NAME}" \
        --ip "${HOST_ONLY_NET_IP}" \
        --netmask "${HOST_ONLY_NET_MASK}" 2>/dev/null; then
        log_error "Failed to configure host-only interface IP"
        exit 1
    fi
    
    # DHCP configuration
    if [[ "${HOST_ONLY_NET_DHCP}" == "true" ]]; then
        configure_hostonly_dhcp
    else
        # Ensure DHCP server is removed if disabled
        if "${VBOX_MANAGE}" list dhcpservers | grep -q "${HOST_ONLY_NET_NAME}"; then
            "${VBOX_MANAGE}" dhcpserver remove --ifname "${HOST_ONLY_NET_NAME}" || \
                log_warning "Failed to remove existing DHCP server"
        fi
    fi
}

configure_hostonly_dhcp() {
    log_info "Setting up DHCP server for ${HOST_ONLY_NET_NAME}"
    
    # Remove existing DHCP server if present
    if "${VBOX_MANAGE}" list dhcpservers | grep -q "${HOST_ONLY_NET_NAME}"; then
        "${VBOX_MANAGE}" dhcpserver remove --ifname "${HOST_ONLY_NET_NAME}" || \
            log_warning "Failed to remove existing DHCP server"
    fi
    
    # Calculate DHCP range (last octet 100-200)
    local dhcp_lower="${HOST_ONLY_NET_IP%.*}.100"
    local dhcp_upper="${HOST_ONLY_NET_IP%.*}.200"
    
    # Create new DHCP server
    if ! "${VBOX_MANAGE}" dhcpserver add --ifname "${HOST_ONLY_NET_NAME}" \
        --ip "${HOST_ONLY_NET_IP}" \
        --netmask "${HOST_ONLY_NET_MASK}" \
        --lowerip "${dhcp_lower}" \
        --upperip "${dhcp_upper}" \
        --enable; then
        log_error "Failed to configure DHCP server"
        exit 1
    fi
    
    log_info "DHCP server configured (${dhcp_lower}-${dhcp_upper})"
}

# NAT network configuration
setup_nat_network() {
    if [ "${NAT_NET_ENABLED}" != "true" ]; then
        log_info "Skipping NAT network (disabled in config)"
        return
    fi

    log_info "Configuring NAT network: ${NAT_NET_NAME}"
    
    # Remove existing network if present
    if "${VBOX_MANAGE}" list natnets | grep -q "${NAT_NET_NAME}"; then
        log_info "Removing existing NAT network..."
        if ! "${VBOX_MANAGE}" natnetwork remove --netname "${NAT_NET_NAME}"; then
            log_warning "Failed to remove existing NAT network"
        fi
    fi
    
    # Create new NAT network with CIDR notation support
    log_info "Creating NAT network ${NAT_NET_IP} (DHCP: ${NAT_NET_DHCP})"
    if ! "${VBOX_MANAGE}" natnetwork add \
        --netname "${NAT_NET_NAME}" \
        --network "${NAT_NET_IP}" \
        --dhcp "${NAT_NET_DHCP}" \
        --ipv6 off; then
        log_error "Failed to create NAT network"
        exit 1
    fi
    
    # Configure port forwarding if specified
    [[ "${NAT_NET_DHCP}" == "true" ]] && configure_port_forwarding
}

# Configure port forwarding rules
configure_port_forwarding() {
    log_info "Configuring comprehensive port forwarding rules for ${NAT_NET_NAME}"
    
    # Remove all existing rules first
    "${VBOX_MANAGE}" natnetwork modify --netname "${NAT_NET_NAME}" --port-forward-4 delete-all
    
    # Standard SSH forwarding (host:2222 → guest:22)
    "${VBOX_MANAGE}" natnetwork modify --netname "${NAT_NET_NAME}" \
        --port-forward-4 "ssh:tcp:[]:2222:[${HOST_ONLY_NET_IP%.*}.2]:22" || \
        log_warning "Failed to configure SSH port forwarding"
        
    # HTTP forwarding
    "${VBOX_MANAGE}" natnetwork modify --netname "${NAT_NET_NAME}" \
        --port-forward-4 "http:tcp:[]:8080:[${HOST_ONLY_NET_IP%.*}.2]:80"
}

# ----------------------------------
# Bridge Network Configuration
# ----------------------------------
setup_bridge_network() {
    [[ "${BRIDGE_NET_ENABLED}" != "true" ]] && return

    log_info "Configuring bridge network for host interface: ${BRIDGE_INTERFACE}"

    # List available host network interfaces
    local available_ifaces=($("${VBOX_MANAGE}" list bridgedifs | grep -E '^Name:' | awk '{print $2}'))
    
    # Verify the specified interface exists
    if ! printf '%s\n' "${available_ifaces[@]}" | grep -q "^${BRIDGE_INTERFACE}$"; then
        log_error "Bridge interface '${BRIDGE_INTERFACE}' not found. Available interfaces:"
        printf '  - %s\n' "${available_ifaces[@]}"
        exit 1
    fi

    # Configure bridge for each VM that needs it
    for vm_name in "${BRIDGE_VMS[@]}"; do
        # Verify VM exists
        if ! "${VBOX_MANAGE}" showvminfo "${vm_name}" &>/dev/null; then
            log_warning "VM '${vm_name}' not found - skipping bridge configuration"
            continue
        fi

        log_info "Configuring bridge for VM: ${vm_name}"

        # Determine which NIC to use (default to nic1 if not specified)
        local nic_number=1
        if [[ -n "${BRIDGE_VM_NIC_MAP[$vm_name]}" ]]; then
            nic_number="${BRIDGE_VM_NIC_MAP[$vm_name]}"
        fi

        # Configure bridged adapter
        "${VBOX_MANAGE}" modifyvm "${vm_name}" \
            --nic${nic_number} bridged \
            --bridgeadapter${nic_number} "${BRIDGE_INTERFACE}" \
            --nictype${nic_number} 82545EM \
            --cableconnected${nic_number} on \
            --macaddress${nic_number} auto || log_error "Failed to configure bridge for ${vm_name}"

        log_info "  -> Bridge configured on nic${nic_number} using ${BRIDGE_INTERFACE}"
    done
}

# Configure VM network interfaces
configure_vm_networks() {
    local vm_id=0
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        ((vm_id++))
        
        log_info "Configuring networks for VM: ${vm_name}"
        
        # Validate VM existence
        if ! "$VBOX_MANAGE" showvminfo "$vm_name" &>/dev/null; then
            log_error "VM $vm_name does not exist!"
            continue 
        fi

        IFS=',' read -r os_type memory cpus disk_size <<< "${VM_CONFIGS[$vm_name]}"
        
        # Reset all network interfaces
        for nic in {1..4}; do
            ${VBOX_MANAGE} modifyvm "${vm_name}" --nic${nic} none || log_error "Failed to reset nic${nic} on $vm_name"
        done
        
        # NIC1: NAT (for internet access)
        # echo ${Nat_VMS[@]};
        if [[ " ${Nat_VMS[@]} " =~ " ${vm_name} " && "${NAT_NET_ENABLED}" == "true" ]]; then
            "$VBOX_MANAGE" modifyvm "${vm_name}" \
                --nic1 nat \
                --nat-network1 "${NAT_NET_NAME}" \
                --nictype1 82545EM \
                --cableconnected1 on || log_error "Failed to configure NAT on $vm_name"
            log_info "  -> NAT network '$NAT_NET_NAME' attached to nic1 (Intel PRO/1000)"

            # Add default port forwarding for SSH if not exists
            if ! "$VBOX_MANAGE" showvminfo "$vm_name" | grep -q "guest ssh"; then
                "$VBOX_MANAGE" modifyvm "${vm_name}" \
                    --natpf1 "guest ssh,tcp,,222${vm_id},,22" || \
                    log_warning "Failed to add SSH port forwarding"
            fi
        fi

        # NIC2: Host-only (for internal communication)
        if [[ " ${HOST_ONLY_VMS[@]} " =~ " ${vm_name} " && "${NET_NETWORK_HOST_ONLY_ENABLED}" == "true" ]]; then
            ${VBOX_MANAGE} modifyvm "${vm_name}" \
                --nic2 hostonly \
                --hostonlyadapter2 "${HOST_ONLY_NET_NAME}" \
                --nictype2 82545EM \
                --cableconnected2 on || log_error "Failed to configure host-only on $vm_name"
            log_info "  -> Host-only adapter '$HOST_ONLY_NET_NAME' attached to nic2"
        fi
            
        # NIC3: Additional networks
        for vm in "${Internal_VMS[@]}"; do
            if [ "${vm}" = "${vm_name}" ]; then
                if [ "${NAT_INTERNAL_ENABLED}" = "true" ]; then
                    ${VBOX_MANAGE} modifyvm "${vm_name}" \
                        --nic3 intnet \
                        --intnet3 "${INTERNAL_NET_NAME}" \
                        --nictype3 82545EM \
                        --cableconnected3 on || log_error "Failed to configure internal net on $vm_name"
                    log_info "  -> Internal network '$INTERNAL_NET_NAME' attached to nic3" 
                fi
            fi
        done
        # Set static MAC addresses for consistent IP assignment
        set_mac_addresses "$vm_name" "$vm_id"
    done
}

#-----------------------------------------------------------------------------------------------------------------------
# Set MAC addresses for consistent networking
set_mac_addresses() {
    local vm_name=$1
    local vm_id=$2
    
    ${VBOX_MANAGE} modifyvm "${vm_name}" \
        --macaddress1 "080027$(printf '%06X' $((vm_id + 0x100)))" \
        --macaddress2 "080027$(printf '%06X' $((vm_id + 0x200)))" \
        --macaddress3 "080027$(printf '%06X' $((vm_id + 0x300)))"
}
#-----------------------------------------------------------------------------------------------------------------------
# Network validation
validate_networks() {
    log_info "Validating network configuration"
    
    validate_hostonly_network
    validate_nat_network
    validate_vm_networks
    
    log_success "Network validation passed"
}

validate_hostonly_network() {
    if ! ${VBOX_MANAGE} list hostonlyifs | grep -q "${HOST_ONLY_NET_NAME}"; then
        log_error "Host-only network validation failed"
        return 1
    fi
    
    log_info "Host-only network active: ${HOST_ONLY_NET_NAME}"
    return 0
}

validate_nat_network() {
    if [ "${NAT_NET_ENABLED}" != "true" ]; then
        return 0
    fi
    
    if ! ${VBOX_MANAGE} list natnets | grep -q "${NAT_NET_NAME}"; then
        log_error "NAT network validation failed"
        return 1
    fi
    
    log_info "NAT network active: ${NAT_NET_NAME}"
    return 0
}

validate_vm_networks() {
    for vm_name in "${!VM_CONFIGS[@]}"; do
        local nic_count=$(${VBOX_MANAGE} showvminfo "$vm_name" --machinereadable | grep -c '^nic[0-9]=')
        
        if [ "$nic_count" -lt 2 ]; then
            log_error "VM ${vm_name} has insufficient network interfaces"
            return 1
        fi
        
        log_info "VM ${vm_name} network configuration OK"
    done
}

# Network teardown
teardown_networks() {
    log_info "Starting network teardown"
    
    # Remove NAT network
    if ${VBOX_MANAGE} list natnets | grep -q "${NAT_NET_NAME}"; then
        ${VBOX_MANAGE} natnetwork remove --netname "${NAT_NET_NAME}"
        log_info "Removed NAT network: ${NAT_NET_NAME}"
    fi
    
    # Remove host-only interface
    if ${VBOX_MANAGE} list hostonlyifs | grep -q "${HOST_ONLY_NET_NAME}"; then
        # First remove any DHCP servers
        if ${VBOX_MANAGE} list dhcpservers | grep -q "${HOST_ONLY_NET_NAME}"; then
            ${VBOX_MANAGE} dhcpserver remove --ifname "${HOST_ONLY_NET_NAME}"
        fi
        
        ${VBOX_MANAGE} hostonlyif remove "${HOST_ONLY_NET_NAME}"
        log_info "Removed host-only interface: ${HOST_ONLY_NET_NAME}"
    fi
    
    log_success "Network teardown completed"
}

# Network status reporting
network_status() {
    echo ""
    echo "=== Network Status Report ==="
    echo "Generated: $(date)"
    echo ""
    
    echo "--- Host Network Interfaces ---"
    ${VBOX_MANAGE} list hostonlyifs
    echo ""
    
    echo "--- NAT Networks ---"
    ${VBOX_MANAGE} list natnets
    echo ""
    
    echo "--- DHCP Servers ---"
    ${VBOX_MANAGE} list dhcpservers
    echo ""
    
    echo "--- VM Network Configurations ---"
    for vm_name in "${!VM_CONFIGS[@]}"; do
        echo "VM: ${vm_name}"
        ${VBOX_MANAGE} showvminfo "$vm_name" | grep -E 'NIC|MAC|Cable'
        echo ""
    done
}

# Main execution
case "$1" in
    setup)
        setup_networks
        ;;
    teardown)
        teardown_networks
        ;;
    status)
        network_status
        ;;
    validate)
        validate_networks
        ;;
    *)
        echo "Usage: $0 {setup|teardown|status|validate}"
        exit 1
        ;;
esac


# example how to use it : 
# ./03_setup_networks.sh setup      - Configures all networks
# ./03_setup_networks.sh teardown   - Cleans up networks
# ./03_setup_networks.sh status     - Shows current network state
# ./03_setup_networks.sh validate   - Checks network health