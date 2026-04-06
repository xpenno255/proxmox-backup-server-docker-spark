#!/bin/bash
set -e

PBS_ETC="/etc/proxmox-backup"
PBS_DEFAULT="/etc/proxmox-backup-default"
PBS_LIB="/var/lib/proxmox-backup"

# First-run initialization: copy default config if /etc/proxmox-backup is empty
if [ ! -f "$PBS_ETC/user.cfg" ]; then
    echo "==> First run detected, initializing PBS configuration..."

    # Copy default config files
    if [ -d "$PBS_DEFAULT" ]; then
        cp -rn "$PBS_DEFAULT/." "$PBS_ETC/" 2>/dev/null || true
    fi

    # Ensure required directories exist
    mkdir -p "$PBS_ETC/ssl" "$PBS_LIB" /var/log/proxmox-backup /run/proxmox-backup

    # Generate self-signed SSL certificate if none exists
    if [ ! -f "$PBS_ETC/proxy.pem" ]; then
        echo "==> Generating self-signed SSL certificate..."
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "$PBS_ETC/proxy.key" \
            -out "$PBS_ETC/proxy.pem" \
            -sha256 -days 3650 -nodes \
            -subj "/CN=Proxmox Backup Server/O=PBS Docker" 2>/dev/null
        chmod 640 "$PBS_ETC/proxy.key"
    fi

    # Create default admin user (admin@pbs with password 'pbspbs')
    if [ ! -f "$PBS_ETC/user.cfg" ]; then
        echo "==> Creating default admin user (admin@pbs / pbspbs)..."
        # Create user.cfg
        cat > "$PBS_ETC/user.cfg" << 'EOF'
user: admin@pbs
	enable: true
	expire: 0
EOF
        # Set default password - user should change this immediately
        proxmox-backup-manager user update admin@pbs --password "pbspbs" 2>/dev/null || true
    fi

    echo "==> Initialization complete. Access PBS at https://<host>:8007"
    echo "==> Default credentials: admin@pbs / pbspbs (CHANGE IMMEDIATELY)"
fi

# Ensure /run directory exists (needed for tmpfs mount)
mkdir -p /run/proxmox-backup

# Execute the main command (default: runsvdir /runit)
exec "$@"
