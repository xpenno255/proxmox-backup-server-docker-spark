#!/bin/bash
set -euo pipefail

# Check for new Proxmox Backup Server ARM64 releases from wofferl/proxmox-backup-arm64
# Compares latest GitHub release tag against current VERSION file.
# Outputs machine-readable results for GitHub Actions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

CURRENT_VERSION=$(cat "$VERSION_FILE")
echo "Current version: $CURRENT_VERSION"

# Fetch latest release tag from wofferl/proxmox-backup-arm64
echo "Checking wofferl/proxmox-backup-arm64 for new releases..."
LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/wofferl/proxmox-backup-arm64/releases/latest" | \
    grep -oP '"tag_name":\s*"\K[^"]+')

if [[ -z "$LATEST_VERSION" ]]; then
    echo "ERROR: Failed to fetch latest release from GitHub"
    echo "UPDATE_AVAILABLE=false"
    exit 1
fi

echo "Latest version: $LATEST_VERSION"

if [[ "$LATEST_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "Already up to date."
    echo "UPDATE_AVAILABLE=false"
else
    # Use sort -V to determine if latest is actually newer
    NEWER=$(printf '%s\n%s' "$CURRENT_VERSION" "$LATEST_VERSION" | sort -V | tail -1)
    if [[ "$NEWER" == "$LATEST_VERSION" && "$NEWER" != "$CURRENT_VERSION" ]]; then
        echo "New version available!"
        echo "UPDATE_AVAILABLE=true"
        echo "NEW_VERSION=$LATEST_VERSION"

        # Fetch the asset list to update package versions in Dockerfile
        echo "Fetching asset list for $LATEST_VERSION..."
        ASSETS=$(curl -fsSL "https://api.github.com/repos/wofferl/proxmox-backup-arm64/releases/tags/${LATEST_VERSION}" | \
            grep -oP '"name":\s*"\K[^"]+\.deb')
        echo "ASSETS:"
        echo "$ASSETS"
    else
        echo "Current version is equal or newer."
        echo "UPDATE_AVAILABLE=false"
    fi
fi
