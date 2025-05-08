#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

install_os() {
    local vm_name="$1"
    local iso_file="$2"
    
    log_info "Starting OS installation for $vm_name"
    
    # Attach ISO
    ${VBOX_MANAGE} storagectl "$vm_name" --name "IDE Controller" --add ide
    # vboxmanage storagectl "ubuntu-server-for-nginx" --name "IDE Controller" --add ide
    
    ${VBOX_MANAGE} storageattach "$vm_name" --storagectl "IDE Controller" \
        --port 0 --device 0 --type dvddrive --medium "${ISO_DIR}/${iso_file}"
    # vboxmanage storageattach "ubuntu-server-for-nginx" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium ""D:\DevOops Projects\VirtualBox\ISOs\ubuntu-24.04.2-desktop-amd64.iso"
    
    # Configure boot order
    ${VBOX_MANAGE} modifyvm "$vm_name" --boot1 dvd --boot2 disk --boot3 none --boot4 none
    # vboxmanage modifyvm "ubuntu-server-for-nginx" --boot1 dvd --boot2 disk --boot3 none --boot4 none
    
    # Start VM in headless mode
    ${VBOX_MANAGE} startvm "$vm_name" --type headless
    # vboxmanage startvm "ubuntu-server-for-nginx" --type headless
    
    log_info "OS installation started for $vm_name. Please complete the installation manually."
    log_info "After installation, shut down the VM and run the provisioning script."
}

main() {
    if [ $# -eq 0 ]; then
        log_error "Usage: $0 <vm_name> <iso_file>"
        exit 1
    fi
    
    # make loop to all vms
    check_dependencies
    install_os "$1" "$2"
}

main "$@"