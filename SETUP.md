# Setup Guide - Build on ARM64 Spark Mini PC

## Prerequisites

On the Spark, ensure you have:
- Docker (confirmed: v28.5.1)
- Git

## Step 1: Clone / Copy the project

Option A - If pushed to GitHub:
```bash
git clone https://github.com/<your-username>/proxmox-backup-server-docker.git
cd proxmox-backup-server-docker
```

Option B - Copy from Windows (from the Windows machine):
```bash
scp -r "/c/Users/spenc/OneDrive - University of Birmingham/VibeCode/proxmox-backup-server-docker" xpenno255@192.168.1.110:~/pbs-docker
```

## Step 2: Build the Docker image

```bash
cd ~/pbs-docker
docker build -t pbs-test .
```

This should take just a few minutes - it downloads pre-built .deb packages from
wofferl/proxmox-backup-arm64 GitHub releases, no compilation needed.

## Step 3: Test run

```bash
docker run -d --name pbs-test \
  --tmpfs /run \
  -p 8007:8007 \
  -v pbs_etc:/etc/proxmox-backup \
  -v pbs_logs:/var/log/proxmox-backup \
  -v pbs_lib:/var/lib/proxmox-backup \
  pbs-test
```

Wait ~15 seconds, then check:
```bash
docker logs pbs-test
curl -sk https://localhost:8007
```

Access the web UI at: https://192.168.1.110:8007
Default credentials: admin@pbs / pbspbs

## Step 4: Debug if needed

```bash
# Check container status
docker ps -a | grep pbs

# View logs
docker logs pbs-test

# Shell into container
docker exec -it pbs-test bash

# Check runit services
docker exec pbs-test sv status /runit/*

# Stop and remove
docker stop pbs-test && docker rm pbs-test
```

## Step 5: Iterate

Common issues to watch for:
- Missing runtime library deps (fix: add to apt-get install in Dockerfile)
- runit service names not matching actual PBS binary names
- entrypoint.sh creating admin user may need adjustments
- File permissions on runit run scripts (must be executable)

## Project Structure

```
pbs-docker/
├── Dockerfile              # Single-stage: download wofferl .debs + install
├── VERSION                 # 4.1.2-1
├── docker-compose.yml      # Quick-start config
├── scripts/
│   ├── entrypoint.sh       # First-run init (SSL cert, admin user)
│   └── check-version.sh    # Checks wofferl releases for updates
├── config/
│   ├── pbs/datastore.cfg   # Default PBS config
│   └── runit/              # Service definitions
│       ├── proxmox-backup-proxy/run  # Web proxy (port 8007)
│       ├── proxmox-backup-api/run    # API daemon
│       └── cron/run                  # Cron scheduler
├── .github/workflows/      # CI/CD (for when pushed to GitHub)
│   ├── build-test.yml
│   ├── release.yml
│   └── check-updates.yml
├── .github/dependabot.yml
├── .dockerignore
├── .gitignore
├── LICENSE
└── README.md
```

## Key Design Decisions

- **ARM64 only** - uses wofferl's pre-built packages, no compilation
- **PBS 4.1.2-1** on Debian Trixie
- **runit** as process supervisor (runs proxy, api daemon, cron)
- **Entrypoint** handles first-run setup (SSL cert, default admin user)
- **Weekly GitHub Actions** cron checks for new wofferl releases, creates PRs
