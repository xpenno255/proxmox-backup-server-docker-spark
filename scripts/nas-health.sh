#!/bin/bash
# Docker HEALTHCHECK script — checks NAS mount is alive
# Returns 0 (healthy) if /backups is an active NFS mount with accessible content
# Returns 1 (unhealthy) otherwise

MOUNT_POINT="${NAS_MOUNT_POINT:-/backups}"

# If no NAS is configured, skip the check — container is healthy without NAS
if [ -z "${NAS_ADDRESS}" ]; then
    echo "HEALTHY: No NAS configured (NAS_ADDRESS not set)"
    exit 0
fi

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
