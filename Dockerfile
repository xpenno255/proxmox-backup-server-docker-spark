# syntax=docker/dockerfile:1
#
# Proxmox Backup Server - ARM64 Docker Image
# Installs PBS 4.x using pre-built ARM64 packages from
# https://github.com/wofferl/proxmox-backup-arm64
#
# Build: docker build -t pbs .

ARG DEBIAN_VERSION=trixie
ARG PBS_VERSION=4.1.2-1

FROM debian:${DEBIAN_VERSION}

ARG PBS_VERSION
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
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
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built ARM64 PBS packages from wofferl releases
RUN mkdir -p /tmp/pbs-packages && cd /tmp/pbs-packages && \
    RELEASE_URL="https://github.com/wofferl/proxmox-backup-arm64/releases/download/${PBS_VERSION}" && \
    # Core server package
    curl -fSL -O "${RELEASE_URL}/proxmox-backup-server_${PBS_VERSION}_arm64.deb" && \
    # Client
    curl -fSL -O "${RELEASE_URL}/proxmox-backup-client_${PBS_VERSION}_arm64.deb" && \
    # File restore
    curl -fSL -O "${RELEASE_URL}/proxmox-backup-file-restore_${PBS_VERSION}_arm64.deb" && \
    # Documentation
    curl -fSL -O "${RELEASE_URL}/proxmox-backup-docs_${PBS_VERSION}_all.deb" && \
    # Supporting packages
    curl -fSL -O "${RELEASE_URL}/proxmox-mini-journalreader_1.6-1_arm64.deb" && \
    curl -fSL -O "${RELEASE_URL}/proxmox-termproxy_2.0.3_arm64.deb" && \
    curl -fSL -O "${RELEASE_URL}/proxmox-widget-toolkit_5.1.5_all.deb" && \
    curl -fSL -O "${RELEASE_URL}/pve-xtermjs_5.5.0-3_all.deb" && \
    curl -fSL -O "${RELEASE_URL}/pbs-i18n_3.6.6_all.deb" && \
    curl -fSL -O "${RELEASE_URL}/libjs-qrcodejs_1.20230525-pve1_all.deb" && \
    curl -fSL -O "${RELEASE_URL}/libproxmox-acme-plugins_1.7.0_all.deb" && \
    # Install all packages (dpkg first pass may fail on deps, apt fixes it)
    dpkg -i *.deb || true && \
    apt-get update && apt-get install -f -y --no-install-recommends && \
    # Cleanup
    rm -rf /tmp/pbs-packages /var/lib/apt/lists/*

# Copy default configuration
COPY config/pbs/ /etc/proxmox-backup-default/

# Copy runit service definitions
COPY config/runit/ /runit/

# Copy entrypoint
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Persistent data volumes
VOLUME ["/etc/proxmox-backup", "/var/log/proxmox-backup", "/var/lib/proxmox-backup"]

# PBS web interface
EXPOSE 8007

ENTRYPOINT ["/entrypoint.sh"]
CMD ["runsvdir", "/runit"]
