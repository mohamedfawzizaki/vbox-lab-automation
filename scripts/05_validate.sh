#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

# Validation thresholds
PING_TIMEOUT=2
SSH_TIMEOUT=5
HTTP_TIMEOUT=5
SERVICE_TIMEOUT=10

validate_environment() {
    local all_ok=true
    local validation_results=()
    
    log_header "Starting Environment Validation"
    
    # 1. Validate VirtualBox Host Environment
    validate_host_environment || all_ok=false
    
    # 2. Validate VM Status and Basic Connectivity
    validate_vm_status || all_ok=false
    
    # 3. Validate Network Connectivity
    validate_network_connectivity || all_ok=false
    
    # 4. Validate Services
    validate_services || all_ok=false
    
    # 5. Validate Storage
    validate_storage || all_ok=false
    
    # 6. Specialized Role Validation
    validate_roles || all_ok=false
    
    # Display summary
    log_header "Validation Summary"
    for result in "${validation_results[@]}"; do
        echo -e "$result"
    done
    
    if $all_ok; then
        log_success "All validation tests passed"
        return 0
    else
        log_error "Some validation tests failed"
        return 1
    fi
}

validate_host_environment() {
    local host_ok=true
    
    log_section "Validating Host Environment"
    
    # Check VirtualBox installation
    if ! command -v VBoxManage &> /dev/null; then
        validation_results+=("${RED}✗${NC} VirtualBox not installed")
        host_ok=false
    else
        validation_results+=("${GREEN}✓${NC} VirtualBox installed")
        
        # Check VirtualBox version
        vbox_version=$(VBoxManage --version)
        validation_results+=("${GREEN}✓${NC} VirtualBox version: $vbox_version")
    fi
    
    # Check available resources
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -lt 4 ]; then
        validation_results+=("${YELLOW}⚠${NC} Low CPU cores ($cpu_cores), recommend 4+")
    else
        validation_results+=("${GREEN}✓${NC} CPU cores: $cpu_cores")
    fi
    
    local mem_gb=$(free -g | awk '/Mem:/ {print $2}')
    if [ "$mem_gb" -lt 8 ]; then
        validation_results+=("${YELLOW}⚠${NC} Low memory ($mem_gb GB), recommend 8GB+")
    else
        validation_results+=("${GREEN}✓${NC} Memory: $mem_gb GB")
    fi
    
    $host_ok && return 0 || return 1
}

validate_vm_status() {
    local vms_ok=true
    
    log_section "Validating VM Status"
    
    # Get list of running VMs
    local running_vms=$(VBoxManage list runningvms | awk -F'"' '{print $2}')
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        if [[ ! "$running_vms" =~ "$vm_name" ]]; then
            validation_results+=("${RED}✗${NC} VM $vm_name is not running")
            vms_ok=false
        else
            validation_results+=("${GREEN}✓${NC} VM $vm_name is running")
            
            # Check VM state
            local vm_state=$(VBoxManage showvminfo "$vm_name" --machinereadable | grep "VMState=" | cut -d'"' -f2)
            validation_results+=("   - State: $vm_state")
        fi
    done
    
    $vms_ok && return 0 || return 1
}

validate_network_connectivity() {
    local network_ok=true
    
    log_section "Validating Network Connectivity"
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        IFS=',' read -r os_type memory cpus disk_size networks <<< "${VM_CONFIGS[$vm_name]}"
        local vm_id=$(echo "$vm_name" | grep -oE '[0-9]+$')
        local vm_ip="${HOST_ONLY_NET_IP%.*}.$((100 + ${vm_id:-0}))"
        
        # Ping test
        if ! ping -c 1 -W $PING_TIMEOUT "$vm_ip" &> /dev/null; then
            validation_results+=("${RED}✗${NC} Cannot ping $vm_name at $vm_ip")
            network_ok=false
        else
            validation_results+=("${GREEN}✓${NC} $vm_name pingable at $vm_ip")
            
            # SSH test
            if ! nc -z -w $SSH_TIMEOUT "$vm_ip" 22 &> /dev/null; then
                validation_results+=("${RED}✗${NC} SSH not responding on $vm_name")
                network_ok=false
            else
                validation_results+=("${GREEN}✓${NC} SSH accessible on $vm_name")
            fi
        fi
        
        # Inter-VM connectivity test
        for other_vm in "${!VM_CONFIGS[@]}"; do
            if [ "$vm_name" != "$other_vm" ]; then
                local other_id=$(echo "$other_vm" | grep -oE '[0-9]+$')
                local other_ip="${HOST_ONLY_NET_IP%.*}.$((100 + ${other_id:-0}))"
                
                if ! ssh -o ConnectTimeout=$SSH_TIMEOUT "${VBOX_USER}@${vm_ip}" \
                    ping -c 1 -W $PING_TIMEOUT "$other_ip" &> /dev/null; then
                    validation_results+=("${YELLOW}⚠${NC} $vm_name cannot reach $other_vm ($other_ip)")
                fi
            fi
        done
    done
    
    $network_ok && return 0 || return 1
}

validate_services() {
    local services_ok=true
    
    log_section "Validating Services"
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        IFS=',' read -r os_type memory cpus disk_size networks <<< "${VM_CONFIGS[$vm_name]}"
        local vm_id=$(echo "$vm_name" | grep -oE '[0-9]+$')
        local vm_ip="${HOST_ONLY_NET_IP%.*}.$((100 + ${vm_id:-0}))"
        
        # Check common services
        local services_to_check=("nginx" "nodejs" "mysql")
        for service in "${services_to_check[@]}"; do
            if ssh -o ConnectTimeout=$SSH_TIMEOUT "${VBOX_USER}@${vm_ip}" \
                "command -v $service" &> /dev/null; then
                
                # Check if service is running
                if ssh -o ConnectTimeout=$SSH_TIMEOUT "${VBOX_USER}@${vm_ip}" \
                    "systemctl is-active --quiet $service" &> /dev/null; then
                    validation_results+=("${GREEN}✓${NC} $service running on $vm_name")
                else
                    validation_results+=("${YELLOW}⚠${NC} $service installed but not running on $vm_name")
                fi
            fi
        done
    done
    
    $services_ok && return 0 || return 1
}

validate_storage() {
    local storage_ok=true
    
    log_section "Validating Storage"
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        local disk_info=$(VBoxManage showvminfo "$vm_name" --machinereadable | \
                         grep -E '^"SATA-.*-ImageUUID' | head -1)
        
        if [ -z "$disk_info" ]; then
            validation_results+=("${RED}✗${NC} No disk attached to $vm_name")
            storage_ok=false
        else
            validation_results+=("${GREEN}✓${NC} $vm_name has disk attached")
            
            # Check disk space in VM
            IFS=',' read -r os_type memory cpus disk_size networks <<< "${VM_CONFIGS[$vm_name]}"
            local vm_id=$(echo "$vm_name" | grep -oE '[0-9]+$')
            local vm_ip="${HOST_ONLY_NET_IP%.*}.$((100 + ${vm_id:-0}))"
            
            if ssh -o ConnectTimeout=$SSH_TIMEOUT "${VBOX_USER}@${vm_ip}" \
                "[ \$(df -h / | awk 'NR==2 {print \$5}' | tr -d '%') -gt 90 ]" &> /dev/null; then
                validation_results+=("${YELLOW}⚠${NC} $vm_name root filesystem >90% full")
            fi
        fi
    done
    
    $storage_ok && return 0 || return 1
}

# Helper functions
log_header() {
    echo -e "\n${GREEN}===${NC} ${YELLOW}$1${NC} ${GREEN}===${NC}"
}

log_section() {
    echo -e "\n${BLUE}--- $1 ---${NC}"
}

main() {
    validate_environment
    exit $?
}

main "$@"