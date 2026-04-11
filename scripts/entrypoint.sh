#!/bin/bash
set -e

# Add PBS binaries to PATH if they exist in non-standard locations
for pbs_path in /usr/lib/x86_64-linux-gnu/proxmox-backup /usr/lib/aarch64-linux-gnu/proxmox-backup /usr/lib/proxmox-backup; do
    if [ -d "$pbs_path" ] && [[ ":$PATH:" != *":$pbs_path:"* ]]; then
        export PATH="${PATH}:${pbs_path}"
        echo "==> Added $pbs_path to PATH"
    fi
done

# Check PBS binary locations and update runit scripts if needed
PBS_PROXY_BIN=$(which proxmox-backup-proxy 2>/dev/null || find /usr -name "proxmox-backup-proxy" -type f 2>/dev/null | head -1)
PBS_API_BIN=$(which proxmox-backup-api-daemon 2>/dev/null || find /usr -name "proxmox-backup-api-daemon" -type f 2>/dev/null | head -1 || find /usr -name "proxmox-backup-api" -type f 2>/dev/null | head -1)

if [ -n "$PBS_PROXY_BIN" ]; then
    echo "==> Found PBS proxy binary: $PBS_PROXY_BIN"
    sed -i "s|/usr/bin/proxmox-backup-proxy|$PBS_PROXY_BIN|g" /runit/proxmox-backup-proxy/run 2>/dev/null || true
fi

if [ -n "$PBS_API_BIN" ]; then
    echo "==> Found PBS api binary: $PBS_API_BIN"
    sed -i "s|/usr/bin/proxmox-backup-api.*|$PBS_API_BIN|g" /runit/proxmox-backup-api/run 2>/dev/null || true
fi

# --- NAS / NFS Mount ---
# If NAS_ADDRESS is set, wait for the NAS and mount via NFS before starting services.
NAS_ADDRESS="${NAS_ADDRESS:-}"
NAS_SHARE="${NAS_SHARE:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"
NAS_MOUNT_OPTS="${NAS_MOUNT_OPTS:-rw,nolock,vers=4,soft,timeo=50}"
NAS_RETRY_INTERVAL="${NAS_RETRY_INTERVAL:-60}"

if [ -n "$NAS_ADDRESS" ] && [ -n "$NAS_SHARE" ]; then
    echo "==> NAS mount configured: ${NAS_ADDRESS}:${NAS_SHARE} -> ${NAS_MOUNT_POINT}"

    # Wait for NAS to become reachable (check NFS port 2049 — ping not available in container)
    until bash -c "echo >/dev/tcp/${NAS_ADDRESS}/2049" 2>/dev/null; do
        echo "==> Waiting for NAS at ${NAS_ADDRESS} (retrying in ${NAS_RETRY_INTERVAL}s)..."
        sleep "$NAS_RETRY_INTERVAL"
    done
    echo "==> NAS at ${NAS_ADDRESS} is reachable"

    # Check if mount point is already mounted (use mountpoint if available, fallback to mount|grep)
    already_mounted=false
    if command -v mountpoint >/dev/null 2>&1; then
        if mountpoint -q "$NAS_MOUNT_POINT" 2>/dev/null; then
            already_mounted=true
        fi
    else
        if mount | grep -q " on ${NAS_MOUNT_POINT} "; then
            already_mounted=true
        fi
    fi

    # Mount NFS share if not already mounted
    if [ "$already_mounted" != "true" ]; then
        echo "==> Mounting ${NAS_ADDRESS}:${NAS_SHARE} to ${NAS_MOUNT_POINT}..."
        echo "==> Mount options: ${NAS_MOUNT_OPTS}"
        mkdir -p "$NAS_MOUNT_POINT"
        if mount -v -t nfs -o "$NAS_MOUNT_OPTS" "${NAS_ADDRESS}:${NAS_SHARE}" "$NAS_MOUNT_POINT" 2>&1; then
            echo "==> NFS mount successful"
        else
            echo "==> ERROR: NFS mount failed with exit code $?"
            echo "==> Checking if nfs kernel module is available..."
            cat /proc/filesystems | grep nfs || echo "==> WARNING: nfs not in /proc/filesystems"
            echo "==> Attempting to load nfs module..."
            modprobe nfs 2>/dev/null || true
        fi
    else
        echo "==> ${NAS_MOUNT_POINT} is already mounted"
    fi

    # Verify mount and show contents
    echo "==> Verifying NAS mount..."
    if mount | grep -q "${NAS_MOUNT_POINT}"; then
        echo "==> NAS mount confirmed:"
        mount | grep "${NAS_MOUNT_POINT}"
        echo "==> Contents of ${NAS_MOUNT_POINT}:"
        ls -la "${NAS_MOUNT_POINT}" 2>/dev/null || echo "==> WARNING: Cannot list ${NAS_MOUNT_POINT} contents"
    else
        echo "==> WARNING: ${NAS_MOUNT_POINT} is NOT mounted! PBS datastore will fail."
    fi

    # Create datastore directory if configured
    PBS_DATASTORE="${PBS_DATASTORE:-}"
    if [ -n "$PBS_DATASTORE" ]; then
        DATASTORE_PATH="${NAS_MOUNT_POINT}/${PBS_DATASTORE}"
        if [ -d "$NAS_MOUNT_POINT" ] && mount | grep -q "${NAS_MOUNT_POINT}"; then
            echo "==> Creating datastore directory: ${DATASTORE_PATH}"
            mkdir -p "${DATASTORE_PATH}/.chunks"
            echo "==> Datastore directory ready"
        else
            echo "==> WARNING: Cannot create datastore directory - NAS not mounted at ${NAS_MOUNT_POINT}"
        fi
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
