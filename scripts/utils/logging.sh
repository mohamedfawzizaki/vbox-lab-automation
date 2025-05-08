# Standardized logging

#!/bin/bash

# Logging functions
log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - $1" >> "${LOG_DIR}/lab_setup.log"
}

log_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS - $1" >> "${LOG_DIR}/lab_setup.log"
}

log_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING - $1" >> "${LOG_DIR}/lab_setup.log"
}

log_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - $1" >> "${LOG_DIR}/lab_setup.log"
}