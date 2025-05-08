#!/bin/bash

# main.sh - Master script for end-to-end VM provisioning automation

# Set error handling
set -eo pipefail

# Load utilities
MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MAIN_SCRIPT_DIR}/scripts/utils/logging.sh"
source "${MAIN_SCRIPT_DIR}/scripts/utils/checks.sh"

# Configuration
DEFAULT_ISO="ubuntu-24.04.2-desktop-amd64.iso"
CONFIG_DIR="${MAIN_SCRIPT_DIR}/configs"
LOG_DIR="${MAIN_SCRIPT_DIR}/logs"

# Global variables
declare -A VMS_TO_INSTALL

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Automated VirtualBox Environment Provisioning"
    echo
    echo "Options:"
    echo "  -a, --all          Run full provisioning pipeline"
    echo "  -c, --create-vms   Create VMs from vm_configs.csv"
    echo "  -i, --install-os   Install OS on specified VMs"
    echo "  -n, --networks     Configure network settings"
    echo "  -h, --help         Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --all           Complete environment setup"
    echo "  $0 -c -n           Create VMs and configure networks"
}

check_prerequisites() {
    log_info "Starting system validation"
    check_dependencies
    log_success "All prerequisites met"
}

create_vms() {
    log_info "Starting VM creation process"
    "${MAIN_SCRIPT_DIR}/scripts/01_create_vms.sh"
}

configure_networking() {
    log_info "Configuring virtual networks"
    "${MAIN_SCRIPT_DIR}/scripts/03_setup_networks.sh" setup
}

install_operating_systems() {
    log_info "Beginning OS installations"
    
    # Load VM configurations
    while IFS=',' read -r vm_name _ || [ -n "$vm_name" ]; do
        [[ "$vm_name" =~ ^#.*$ || -z "$vm_name" ]] && continue
        VMS_TO_INSTALL["$vm_name"]=1
    done < <(grep -v '^\s*#' "${CONFIG_DIR}/vm_configs.csv")

    # Install OS on each VM
    for vm in "${!VMS_TO_INSTALL[@]}"; do
        log_info "Installing OS on ${vm}"
        "${MAIN_SCRIPT_DIR}/scripts/02_install_os.sh" "${vm}" "${DEFAULT_ISO}"
    done
}

full_provisioning() {
    log_info "Starting complete provisioning workflow"
    check_prerequisites
    create_vms
    install_operating_systems
    configure_networking
    log_success "Full provisioning completed successfully"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                # full_provisioning
                exit 0
                ;;
            -c|--create-vms)
                create_vms
                shift
                ;;
            -i|--install-os)
                install_operating_systems
                shift
                ;;
            -n|--networks)
                configure_networking
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Invalid option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    # Create necessary directories
    mkdir -p "${LOG_DIR}"
    mkdir -p "${MAIN_SCRIPT_DIR}/vms"

    check_prerequisites
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    else
        # echo "$@"
        parse_arguments "$@"
    fi
}

main "$@"