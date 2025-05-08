#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/00_config.sh"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Provisioning configuration
PROVISION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/provision"
ANSIBLE_VAULT_PASSWORD_FILE="${PROVISION_DIR}/.vault_pass"
SSH_TIMEOUT=60
SSH_RETRY_INTERVAL=5

provision_vm() {
    local vm_name="$1"
    local vm_ip="$2"
    local vm_role="${3:-base}"  # Default role is 'base'

    log_info "Starting provisioning for ${vm_name} (${vm_ip}) as ${vm_role}"

    # Wait for SSH access
    if ! wait_for_ssh "${vm_ip}"; then
        log_error "SSH connection failed for ${vm_ip}"
        return 1
    fi

    # Bootstrap basic dependencies
    bootstrap_vm "${vm_ip}"

    # Apply role-specific provisioning
    case "${vm_role}" in
        nginx)
            provision_nginx "${vm_ip}"
            ;;
        mysql)
            provision_mysql "${vm_ip}"
            ;;
        laravel)
            provision_laravel "${vm_ip}"
            ;;
        nodejs)
            provision_nodejs "${vm_ip}"
            ;;
        *)
            provision_base "${vm_ip}"
            ;;
    esac

    # Apply Ansible playbook if available
    apply_ansible "${vm_ip}" "${vm_role}"

    log_success "Completed provisioning for ${vm_name}"
}

wait_for_ssh() {
    local ip="$1"
    local attempt=0
    local max_attempts=$((SSH_TIMEOUT / SSH_RETRY_INTERVAL))

    log_info "Waiting for SSH on ${ip} (timeout: ${SSH_TIMEOUT}s) (max_attempts: ${max_attempts})"
    
    while ! nc -z -w1 "${ip}" 22; do
        attempt=$((attempt + 1))
        
        if [ ${attempt} -ge ${max_attempts} ]; then
            log_error "SSH timeout reached for ${ip}"
            return 1
        fi
        sleep ${SSH_RETRY_INTERVAL}
    done
    
    # Additional check to ensure SSH is really ready
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" true; then
        log_error "SSH port open but service not ready on ${ip}"
        return 1
    fi

    return 0
}

bootstrap_vm() {
    local ip="$1"

    log_info "Bootstrapping basic dependencies on ${ip}"
    
    ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<-'EOF'
        # Update package lists
        sudo apt-get update -qq
        
        # Install basic packages
        sudo apt-get install -y -qq \
            apt-transport-https \
            ca-certificates \
            curl \
            software-properties-common \
            gnupg-agent \
            python3-minimal
        
        # Configure Python symlink for Ansible
        if ! command -v python &> /dev/null && command -v python3 &> /dev/null; then
            sudo ln -s $(which python3) /usr/bin/python
        fi
EOF
}

provision_base() {
    local ip="$1"

    log_info "Applying base provisioning to ${ip}"
    
    ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<-'EOF'
        # Install common tools
        sudo apt-get install -y -qq \
            git \
            htop \
            net-tools \
            tree \
            unzip \
            wget
        
        # Configure basic security
        sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo systemctl restart sshd
EOF
}

provision_nginx() {
    local ip="$1"
    local nginx_log="/tmp/nginx_provision_${ip}.log"
    
    log_header "Provisioning Nginx on ${ip}"

    if ! ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<'EOF' > "${nginx_log}" 2>&1
        # Install Nginx with HTTP/3 and Brotli support
        sudo apt-get update -qq
        sudo apt-get install -y -qq \
            nginx-extras \
            libnginx-mod-http-brotli \
            certbot \
            python3-certbot-nginx
        
        # Configure Nginx
        sudo mkdir -p /etc/nginx/snippets
        sudo tee /etc/nginx/snippets/security.conf > /dev/null <<'CONF'
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" always;
CONF

        # Enable and start Nginx
        sudo systemctl enable nginx
        sudo systemctl restart nginx
        
        # Firewall configuration
        if command -v ufw >/dev/null; then
            sudo ufw allow 'Nginx Full'
            sudo ufw --force enable
        fi
EOF
    then
        log_error "Nginx installation failed"
        log_debug "Check log: ${nginx_log}"
        return 1
    fi

    log_success "Nginx provisioned successfully"
    log_info "Access server at: http://${ip}"
    return 0
}

provision_mysql() {
    local ip="$1"
    local mysql_root_pwd=$(openssl rand -base64 24)
    local mysql_log="/tmp/mysql_provision_${ip}.log"

    log_header "Provisioning MySQL on ${ip}"

    if ! ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<EOF > "${mysql_log}" 2>&1
        # Install MySQL Server securely
        sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password ${mysql_root_pwd}"
        sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${mysql_root_pwd}"
        sudo apt-get update -qq
        sudo apt-get install -y -qq mysql-server mysql-client
        
        # Run security script
        sudo mysql_secure_installation <<MYSQL_SECURE
n
y
y
y
y
MYSQL_SECURE

        # Create .my.cnf for root user
        sudo tee /root/.my.cnf > /dev/null <<CONF
[client]
user=root
password=${mysql_root_pwd}
CONF

        # Performance tuning (adjust based on available RAM)
        sudo tee /etc/mysql/mysql.conf.d/mysqld.cnf > /dev/null <<'CONF'
[mysqld]
innodb_buffer_pool_size = 256M
innodb_log_file_size = 128M
max_connections = 100
thread_cache_size = 8
CONF

        sudo systemctl restart mysql
EOF
    then
        log_error "MySQL installation failed"
        return 1
    fi

    log_success "MySQL provisioned successfully"
    log_info "Root password: ${mysql_root_pwd}"
    log_info "Connection string: mysql -h ${ip} -u root -p"
    return 0
}

provision_nodejs() {
    local ip="$1"
    local node_version="18"  # LTS version
    local node_log="/tmp/node_provision_${ip}.log"

    log_header "Provisioning Node.js ${node_version} on ${ip}"

    if ! ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<'EOF' > "${node_log}" 2>&1
        # Install Node.js via Nodesource
        curl -fsSL https://deb.nodesource.com/setup_${node_version}.x | sudo -E bash -
        sudo apt-get install -y -qq nodejs
        
        # Install build tools and PM2 process manager
        sudo apt-get install -y -qq build-essential
        sudo npm install -g pm2 yarn
        
        # Configure npm
        mkdir -p ~/.npm-global
        npm config set prefix '~/.npm-global'
        echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
        source ~/.bashrc
        
        # Setup PM2 startup
        pm2 startup | grep "sudo" | bash
        pm2 save
EOF
    then
        log_error "Node.js installation failed"
        return 1
    fi

    log_success "Node.js ${node_version} provisioned successfully"
    log_info "Installed versions:"
    ssh "${VBOX_USER}@${ip}" "node -v && npm -v && pm2 --version"
    return 0
}

provision_laravel() {
    local ip="$1"
    local app_name="laravel_app"
    local laravel_log="/tmp/laravel_provision_${ip}.log"

    log_header "Provisioning Laravel environment on ${ip}"

    if ! ssh -o StrictHostKeyChecking=no "${VBOX_USER}@${ip}" <<'EOF' > "${laravel_log}" 2>&1
        # Install PHP and required extensions
        sudo apt-get update -qq
        sudo apt-get install -y -qq \
            php8.1 \
            php8.1-cli \
            php8.1-common \
            php8.1-mysql \
            php8.1-zip \
            php8.1-gd \
            php8.1-mbstring \
            php8.1-curl \
            php8.1-xml \
            php8.1-bcmath \
            php8.1-fpm \
            php8.1-opcache

        # Install Composer
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        php composer-setup.php --install-dir=/usr/local/bin --filename=composer
        php -r "unlink('composer-setup.php');"

        # Create Laravel project
        composer create-project laravel/laravel ${app_name} --prefer-dist
        cd ${app_name}
        
        # Configure environment
        cp .env.example .env
        php artisan key:generate
        
        # Set permissions
        sudo chown -R www-data:www-data storage bootstrap/cache
        sudo chmod -R 775 storage bootstrap/cache
        
        # Configure Nginx (if installed)
        if [ -f /etc/nginx/sites-available/default ]; then
            sudo tee /etc/nginx/sites-available/laravel > /dev/null <<'CONF'
            server {
                listen 80;
                server_name _;
                root /home/${VBOX_USER}/${app_name}/public;

                add_header X-Frame-Options "SAMEORIGIN";
                add_header X-Content-Type-Options "nosniff";

                index index.php;

                location / {
                    try_files $uri $uri/ /index.php?$query_string;
                }

                location ~ \.php$ {
                    fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
                    fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
                    include fastcgi_params;
                }
            }
            CONF
            sudo ln -sf /etc/nginx/sites-available/laravel /etc/nginx/sites-enabled/
            sudo systemctl restart nginx
        fi
EOF
    then
        log_error "Laravel provisioning failed"
        return 1
    fi

    log_success "Laravel environment ready"
    log_info "Application directory: /home/${VBOX_USER}/${app_name}"
    log_info "Access the app at: http://${ip}"
    return 0
}

main() {
    check_dependencies
    
    # Load VM provisioning configuration
    if [ -f "${CONFIG_DIR}/vm_provisioning.csv" ]; then
        while IFS=, read -r vm_name vm_ip vm_role; do
            # Trim leading/trailing whitespace from each field
            vm_name="$(echo "$vm_name" | xargs)"
            [[ "$vm_name" =~ ^#.*$ || -z "$vm_name" ]] && continue
            provision_vm "${vm_name}" "${vm_ip}" "${vm_role}"
        done < <(grep -v '^\s*#' "${CONFIG_DIR}/vm_provisioning.csv")
    else
        log_warning "No provisioning configuration found at ${CONFIG_DIR}/vm_provisioning.csv"
        log_info "Example usage: provision_vm \"ubuntu-vm\" \"192.168.99.101\" \"docker\""
    fi
}

main "$@"
