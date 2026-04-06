# Proxmox Backup Server - ARM64 Docker

Docker image for [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server) (PBS) on **ARM64** (aarch64).

Uses pre-built ARM64 packages from [wofferl/proxmox-backup-arm64](https://github.com/wofferl/proxmox-backup-arm64) on a Debian Trixie base.

## Quick Start

```bash
# Using docker-compose (recommended)
wget https://raw.githubusercontent.com/spencerarrasmith/proxmox-backup-server-docker/main/docker-compose.yml
docker compose up -d

# Or pull directly
docker pull ghcr.io/spencerarrasmith/proxmox-backup-server:latest
docker run -d --name pbs \
  --tmpfs /run \
  -p 8007:8007 \
  -v pbs_etc:/etc/proxmox-backup \
  -v pbs_logs:/var/log/proxmox-backup \
  -v pbs_lib:/var/lib/proxmox-backup \
  ghcr.io/spencerarrasmith/proxmox-backup-server:latest
```

Access the web UI at **https://\<host-ip\>:8007**

Default credentials: `admin@pbs` / `pbspbs` (change immediately after first login)

## Volumes

| Path | Purpose |
|------|---------|
| `/etc/proxmox-backup` | Configuration, SSL certificates |
| `/var/log/proxmox-backup` | Log files |
| `/var/lib/proxmox-backup` | Task data, internal state |
| `/backups` | Mount your backup storage here |

## Configuration

### docker-compose.yml

```yaml
services:
  pbs:
    image: ghcr.io/spencerarrasmith/proxmox-backup-server:latest
    ports:
      - "8007:8007"
    volumes:
      - pbs_etc:/etc/proxmox-backup
      - pbs_logs:/var/log/proxmox-backup
      - pbs_lib:/var/lib/proxmox-backup
      - /mnt/backups:/backups    # Your backup storage
    tmpfs:
      - /run
    restart: unless-stopped
    mem_limit: 2g
```

### Smartctl Support (optional)

To enable disk health monitoring:

```yaml
services:
  pbs:
    cap_add:
      - SYS_RAWIO
    devices:
      - /dev/sda:/dev/sda
```

## Automated Updates

A [weekly GitHub Actions workflow](.github/workflows/check-updates.yml) monitors [wofferl/proxmox-backup-arm64](https://github.com/wofferl/proxmox-backup-arm64/releases) for new releases. When a new version is detected, it automatically creates a pull request with updated package versions for review.

## Building Locally

```bash
# On ARM64 natively
docker build -t pbs-local .

# On AMD64 via QEMU emulation
docker buildx build --platform linux/arm64 -t pbs-local .
```

Build time is fast (minutes, not hours) since we use pre-built packages rather than compiling from source.

## Known Limitations

- **ARM64 only** - This image targets ARM64 platforms (Raspberry Pi 4/5, Apple Silicon, AWS Graviton, etc.)
- **No ZFS support** - ZFS requires kernel modules not available in containers
- **No shell via PVE auth** - Use PAM authentication instead

## Credits

- [wofferl/proxmox-backup-arm64](https://github.com/wofferl/proxmox-backup-arm64) - Pre-built ARM64 packages
- [ayufan/pve-backup-server-dockerfiles](https://github.com/ayufan/pve-backup-server-dockerfiles) - Docker architecture reference
- [Proxmox community scripts](https://community-scripts.github.io/ProxmoxVE/) - LXC installation reference

## License

AGPL-3.0, matching Proxmox Backup Server. See [LICENSE](LICENSE).
