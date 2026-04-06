# NAS Resilience - NFS-in-Container Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the PBS container self-healing by mounting NFS storage internally, waiting for the NAS to come online before starting services, and recovering automatically when the NAS goes offline.

**Architecture:** The container gains NFS client capabilities and mounts `192.168.1.53:/volume1/Proxmox` directly, removing the host-level fstab dependency. The entrypoint probes NAS availability in a loop before mounting and starting services. Docker's `restart: unless-stopped` handles crash recovery, and a healthcheck monitors ongoing NAS connectivity.

**Tech Stack:** Docker, NFS v3, bash, runit

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Dockerfile` | Modify | Add `nfs-common` package |
| `scripts/entrypoint.sh` | Modify | Add NAS wait loop + NFS mount before existing init |
| `docker-compose.yml` | Modify | Add env vars, `cap_add`, healthcheck, remove old backup mount comment |
| `scripts/nas-health.sh` | Create | Lightweight NAS reachability check for Docker healthcheck |

---

### Task 1: Add NFS client to Dockerfile

**Files:**
- Modify: `Dockerfile:18-32` (apt-get install block)

- [ ] **Step 1: Add nfs-common to runtime dependencies**

In the `apt-get install` block, add `nfs-common` after `smartmontools`:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        runit \
        cron \
        ca-certificates \
        curl \
        openssl \
        libfuse3-3 \
        libsgutils2-1.48 \
        libsystemd0 \
        libacl1 \
        libpam0g \
        zlib1g \
        libzstd1 \
        libuuid1 \
        libjs-extjs \
        smartmontools \
        nfs-common \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Add /backups mount point**

After the `VOLUME` line (line 72), add:

```dockerfile
# NFS backup storage mount point
RUN mkdir -p /backups
```

- [ ] **Step 3: Copy nas-health.sh script**

After the entrypoint COPY block, add:

```dockerfile
COPY scripts/nas-health.sh /nas-health.sh
RUN chmod +x /nas-health.sh
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add nfs-common for in-container NFS mount support"
```

---

### Task 2: Create NAS health check script

**Files:**
- Create: `scripts/nas-health.sh`

- [ ] **Step 1: Write the health check script**

```bash
#!/bin/bash
# Docker HEALTHCHECK script — checks NAS mount is alive
# Returns 0 (healthy) if /backups is an active NFS mount with accessible content
# Returns 1 (unhealthy) otherwise

MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"

# Check if mount point is an active mount
if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "UNHEALTHY: $MOUNT_POINT is not mounted"
    exit 1
fi

# Check if we can stat the mount (catches stale NFS handles)
if ! stat "$MOUNT_POINT" >/dev/null 2>&1; then
    echo "UNHEALTHY: $MOUNT_POINT is not accessible (stale mount?)"
    exit 1
fi

echo "HEALTHY: $MOUNT_POINT is mounted and accessible"
exit 0
```

- [ ] **Step 2: Commit**

```bash
git add scripts/nas-health.sh
git commit -m "feat: add NAS health check script for Docker HEALTHCHECK"
```

---

### Task 3: Update entrypoint with NAS wait loop and NFS mount

**Files:**
- Modify: `scripts/entrypoint.sh` (add NAS logic before existing first-run block)

- [ ] **Step 1: Add NAS wait and mount logic to entrypoint**

Insert the following block at the top of `entrypoint.sh`, after `set -e` and before the `PBS_ETC` variable declarations:

```bash
# --- NAS / NFS Mount ---
# If NAS_ADDRESS is set, wait for the NAS and mount via NFS before starting services.
NAS_ADDRESS="${NAS_ADDRESS:-}"
NAS_SHARE="${NAS_SHARE:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"
NAS_MOUNT_OPTS="${NAS_MOUNT_OPTS:-rw,nolock,vers=3,soft,timeo=50}"
NAS_RETRY_INTERVAL="${NAS_RETRY_INTERVAL:-60}"

if [ -n "$NAS_ADDRESS" ] && [ -n "$NAS_SHARE" ]; then
    echo "==> NAS mount configured: ${NAS_ADDRESS}:${NAS_SHARE} -> ${NAS_MOUNT_POINT}"

    # Wait for NAS to become reachable
    until ping -c 1 -W 3 "$NAS_ADDRESS" >/dev/null 2>&1; do
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
```

- [ ] **Step 2: Verify the full entrypoint reads correctly**

The complete file should now be:

```bash
#!/bin/bash
set -e

# --- NAS / NFS Mount ---
NAS_ADDRESS="${NAS_ADDRESS:-}"
NAS_SHARE="${NAS_SHARE:-}"
NAS_MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"
NAS_MOUNT_OPTS="${NAS_MOUNT_OPTS:-rw,nolock,vers=3,soft,timeo=50}"
NAS_RETRY_INTERVAL="${NAS_RETRY_INTERVAL:-60}"

if [ -n "$NAS_ADDRESS" ] && [ -n "$NAS_SHARE" ]; then
    echo "==> NAS mount configured: ${NAS_ADDRESS}:${NAS_SHARE} -> ${NAS_MOUNT_POINT}"

    until ping -c 1 -W 3 "$NAS_ADDRESS" >/dev/null 2>&1; do
        echo "==> Waiting for NAS at ${NAS_ADDRESS} (retrying in ${NAS_RETRY_INTERVAL}s)..."
        sleep "$NAS_RETRY_INTERVAL"
    done
    echo "==> NAS at ${NAS_ADDRESS} is reachable"

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

    if [ -d "$PBS_DEFAULT" ]; then
        cp -rn "$PBS_DEFAULT/." "$PBS_ETC/" 2>/dev/null || true
    fi

    mkdir -p "$PBS_ETC/ssl" "$PBS_LIB" /var/log/proxmox-backup /run/proxmox-backup

    if [ ! -f "$PBS_ETC/proxy.pem" ]; then
        echo "==> Generating self-signed SSL certificate..."
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "$PBS_ETC/proxy.key" \
            -out "$PBS_ETC/proxy.pem" \
            -sha256 -days 3650 -nodes \
            -subj "/CN=Proxmox Backup Server/O=PBS Docker" 2>/dev/null
        chmod 640 "$PBS_ETC/proxy.key"
    fi

    if [ ! -f "$PBS_ETC/user.cfg" ]; then
        echo "==> Creating default admin user (admin@pbs / pbspbs)..."
        cat > "$PBS_ETC/user.cfg" << 'EOF'
user: admin@pbs
	enable: true
	expire: 0
EOF
        proxmox-backup-manager user update admin@pbs --password "pbspbs" 2>/dev/null || true
    fi

    echo "==> Initialization complete. Access PBS at https://<host>:8007"
    echo "==> Default credentials: admin@pbs / pbspbs (CHANGE IMMEDIATELY)"
fi

mkdir -p /run/proxmox-backup

exec "$@"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/entrypoint.sh
git commit -m "feat: add NAS wait loop and NFS mount to entrypoint"
```

---

### Task 4: Update docker-compose.yml

**Files:**
- Modify: `docker-compose.yml`

- [ ] **Step 1: Update compose with NAS env vars, capabilities, and healthcheck**

Replace the full file with:

```yaml
services:
  pbs:
    image: ghcr.io/spencerarrasmith/proxmox-backup-server:latest
    container_name: proxmox-backup-server
    ports:
      - "8007:8007"
    environment:
      - NAS_ADDRESS=192.168.1.53
      - NAS_SHARE=/volume1/Proxmox
      - NAS_MOUNT_POINT=/backups
      - NAS_MOUNT_OPTS=rw,nolock,vers=3,soft,timeo=50
      - NAS_RETRY_INTERVAL=60
    volumes:
      - pbs_etc:/etc/proxmox-backup
      - pbs_logs:/var/log/proxmox-backup
      - pbs_lib:/var/lib/proxmox-backup
    tmpfs:
      - /run
    cap_add:
      - SYS_ADMIN
    restart: unless-stopped
    stop_signal: SIGHUP
    mem_limit: 2g
    healthcheck:
      test: ["/nas-health.sh"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 120s

volumes:
  pbs_etc:
  pbs_logs:
  pbs_lib:
```

- [ ] **Step 2: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add NAS environment config, SYS_ADMIN cap, and healthcheck"
```

---

### Task 5: Update CI smoke test for NFS changes

**Files:**
- Modify: `.github/workflows/build-test.yml`

- [ ] **Step 1: Update smoke test to skip NAS wait**

The smoke test runs without a NAS, so the container should start fine (NAS_ADDRESS is unset, so the wait loop is skipped). Verify the existing test still works by checking that no NAS env vars are passed. No changes needed if the entrypoint correctly skips the NAS block when `NAS_ADDRESS` is empty.

The current smoke test command:

```yaml
docker run -d --name pbs-test \
  --tmpfs /run \
  -p 8007:8007 \
  pbs-test:arm64
```

This is correct — no `NAS_ADDRESS` means the NAS block is skipped entirely.

- [ ] **Step 2: Commit (only if changes were needed)**

No commit expected for this task.

---

### Task 6: Clean up host fstab (instructions for user)

This task is documentation only — to be run manually on the Spark after the container solution is verified.

- [ ] **Step 1: Document fstab cleanup command**

After verifying the container mounts NFS correctly, remove the host-level NFS mount from `/etc/fstab` on the Spark:

```bash
# On the Spark — comment out or remove this line from /etc/fstab:
# 192.168.1.53:/volume1/Proxmox /mnt/nas-proxmox nfs rw,nolock,vers=3,soft,timeo=50 0 0

sudo nano /etc/fstab
# Comment out the 192.168.1.53 line
sudo systemctl daemon-reload
```

---

### Task 7: Initialize git repo and push to GitHub

- [ ] **Step 1: Check if git repo exists, init if needed**

```bash
cd /path/to/proxmox-backup-server-docker
git init
git remote add origin git@github.com:spencerarrasmith/proxmox-backup-server-docker.git
```

- [ ] **Step 2: Stage all files and create initial commit (if fresh repo)**

```bash
git add -A
git commit -m "feat: PBS Docker image with self-healing NAS mount support"
```

- [ ] **Step 3: Push to GitHub**

```bash
git push -u origin main
```

- [ ] **Step 4: Tag a release to trigger CI/CD build**

```bash
git tag v4.1.2-1
git push origin v4.1.2-1
```

This triggers the release workflow which builds the ARM64 image and pushes to `ghcr.io/spencerarrasmith/proxmox-backup-server:latest`.
