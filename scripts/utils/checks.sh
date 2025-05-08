# Dependency checks

#!/bin/bash

check_dependencies() {
    local missing=()
    
    # Check VirtualBox is installed
    if ! command -v VBoxManage &> /dev/null; then
        missing+=("VirtualBox")
    fi
    
    # Check other dependencies
    required_commands=("ssh" "scp" "nc")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
    
    # Check user permissions
    if ! groups "$(whoami)" | grep -q vboxusers; then
        log_warning "Current user is not in vboxusers group"
    fi
}

check_vm_running() {
    local vm_name="$1"
    if ! ${VBOX_MANAGE} list runningvms | grep -q "$vm_name"; then
        log_error "VM $vm_name is not running"
        return 1
    fi
    return 0
}