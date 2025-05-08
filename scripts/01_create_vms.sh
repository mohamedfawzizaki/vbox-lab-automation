#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

create_vm() {
    local vm_name="$1"
    local os_type="$2"
    local memory="$3"
    local cpus="$4"
    local disk_size="$5"

    log_info "Creating VM: $vm_name"
    log_info "           Os Type    : $os_type"
    log_info "           Memory     : $memory"
    log_info "           CPUS       : $cpus"
    log_info "           Disc Size  : $disk_size"
    
    # Create VM
    ${VBOX_MANAGE} createvm --name "$vm_name" --basefolder "$VMS_DIR" --ostype "$os_type" --register
    
    # Set system properties
    ${VBOX_MANAGE} modifyvm "$vm_name" --memory "$memory" \
        --cpus "$cpus" \
        --acpi on \
        --ioapic on \
        --paravirtprovider kvm \
        --graphicscontroller vmsvga \
        --vram 16
    
    # Create storage controller and disk
    ${VBOX_MANAGE} storagectl "$vm_name" --name "SATA Controller" --add sata
    ${VBOX_MANAGE} createmedium disk --filename "${VMS_DIR}/${vm_name}/${vm_name}.vdi" \
        --size "$disk_size" --format VDI
    ${VBOX_MANAGE} storageattach "$vm_name" --storagectl "SATA Controller" \
        --port 0 --device 0 --type hdd --medium "${VMS_DIR}/${vm_name}/${vm_name}.vdi"
    
    log_success "Created VM: $vm_name"
}

main() {
    # check_dependencies
    
    mkdir -p "${VMS_DIR}"
    mkdir -p "${LOG_DIR}"
    
    for vm_name in "${!VM_CONFIGS[@]}"; do
        IFS=',' read -r os_type memory cpus disk_size <<< "${VM_CONFIGS[$vm_name]}"
        create_vm "$vm_name" "${os_type:-$DEFAULT_OS_TYPE}" "${memory:-$DEFAULT_VM_MEMORY}" \
            "${cpus:-$DEFAULT_VM_CPUS}" "${disk_size:-$DEFAULT_VM_DISK}"
    done
}

main "$@"
