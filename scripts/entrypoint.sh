#!/bin/bash
set -e

# --- NAS / NFS Mount ---
# If NAS_ADDRESS is set, wait for the NAS and mount via NFS before starting services.
NAS_ADDRESS="${NAS_ADDRESS:-}"
NAS_SHARE="${NAS_SHARE:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"
NAS_MOUNT_OPTS="${NAS_MOUNT_OPTS:-rw,nolock,vers=3,soft,timeo=50}"
NAS_RETRY_INTERVAL="${NAS_RETRY_INTERVAL:-60}"

if [ -n "$NAS_ADDRESS" ] && [ -n "$NAS_SHARE" ]; then
    echo "==> NAS mount configured: ${NAS_ADDRESS}:${NAS_SHARE} -> ${NAS_MOUNT_POINT}"

    # Wait for NAS to become reachable (check NFS port 2049 — ping not available in container)
    until bash -c "echo >/dev/tcp/${NAS_ADDRESS}/2049" 2>/dev/null; do
        echo "==> Waiting for NAS at ${NAS_ADDRESS} (retrying in ${NAS_RETRY_INTERVAL}s)..."
        sleep "$NAS_RETRY_INTERVAL"
    done
    echo "==> NAS at ${NAS_ADDRESS} is reachable"

    # Mount NFS share if not already mounted
    if ! mountpoint -q "$NAS_MOUNT_POINT" 2>/dev/null; then
        echo "==> Mounting ${NAS_ADDRESS}:${NAS_SHARE} to ${NAS_MOUNT_POINT}..."
        mkdir -p "$NAS_MOUNT_POINT"
        mount -t nfs -o "$NAS_MOUNT_OPTS" "${NAS_ADDRESS}:${NAS_SHARE}" "$NAS_MOUNT_POINT"
        echo "==> NFS mount successful"
    else
        echo "==> ${NAS_MOUNT_POINT} is already mounted"
    fi
fi

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
