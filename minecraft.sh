#!/usr/bin/env bash
# =============================================================================
#  Forge Minecraft Server – Rootless Docker Setup Script
#  No sudo/root required. Requires rootless Docker already configured.
#
#  Usage:
#    bash setup_minecraft.sh                        # default IP 10.1.8.4
#    MINECRAFT_IP=10.1.5.10 bash setup_minecraft.sh # custom IP
# =============================================================================

set -euo pipefail

# ── USER CONFIG ───────────────────────────────────────────────────────────────
STATIC_IP="${MINECRAFT_IP:-10.1.8.4}"
SUBNET="10.1.0.0/16"
GATEWAY="10.1.0.1"
NETWORK_NAME="mc_net"
CONTAINER_NAME="minecraft_forge"
VOLUME_NAME="minecraft_data"
MC_PORT=25565
MEMORY="4G"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── SANITY CHECKS ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] && error "Do NOT run as root. This script is for rootless Docker."
command -v docker &>/dev/null || error "Docker not found. Is rootless Docker installed and in your PATH?"

if ! docker info 2>/dev/null | grep -q "rootless"; then
    warn "Could not confirm rootless mode – proceeding anyway."
fi
info "Docker OK: $(docker --version)"

# ── VALIDATE IP ───────────────────────────────────────────────────────────────
if [[ ! "$STATIC_IP" =~ ^10\.1\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    error "IP '$STATIC_IP' is not a valid 10.1.x.x address."
fi
info "Static IP → $STATIC_IP"

# ── CREATE DOCKER NETWORK ─────────────────────────────────────────────────────
# Using bridge driver – the only one supported in rootless Docker.
# macvlan requires root and is NOT used here.
if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    warn "Network '$NETWORK_NAME' already exists – skipping creation."
else
    info "Creating Docker bridge network '$NETWORK_NAME' ($SUBNET) …"
    docker network create \
        --driver bridge \
        --subnet "$SUBNET" \
        --gateway "$GATEWAY" \
        "$NETWORK_NAME"
fi

# ── CREATE PERSISTENT VOLUME ──────────────────────────────────────────────────
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
    warn "Volume '$VOLUME_NAME' already exists – world data preserved."
else
    info "Creating persistent volume '$VOLUME_NAME' …"
    docker volume create "$VOLUME_NAME"
fi

# ── PULL IMAGE ────────────────────────────────────────────────────────────────
info "Pulling itzg/minecraft-server:latest …"
docker pull itzg/minecraft-server:latest

# ── REMOVE STALE CONTAINER ────────────────────────────────────────────────────
if docker inspect "$CONTAINER_NAME" &>/dev/null; then
    warn "Removing old container '$CONTAINER_NAME' …"
    docker rm -f "$CONTAINER_NAME"
fi

# ── START CONTAINER ───────────────────────────────────────────────────────────
info "Launching Forge Minecraft server …"
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network "$NETWORK_NAME" \
    --ip "$STATIC_IP" \
    -p "${MC_PORT}:${MC_PORT}" \
    -v "${VOLUME_NAME}:/data" \
    -e TYPE=FORGE \
    -e VERSION=LATEST \
    -e EULA=TRUE \
    -e MEMORY="$MEMORY" \
    -e ONLINE_MODE=FALSE \
    -e PAUSE_WHEN_EMPTY_SECONDS=0 \
    -e DIFFICULTY=normal \
    -e MAX_PLAYERS=20 \
    -e MOTD="Forge Server" \
    -e LOG_TIMESTAMP=true \
    itzg/minecraft-server:latest

# ── USER-LEVEL SYSTEMD AUTOSTART ──────────────────────────────────────────────
# Installs into ~/.config/systemd/user/ — no root needed.
# Crash recovery is handled by Docker's --restart=unless-stopped.
# Boot autostart without login requires: sudo loginctl enable-linger $USER
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/minecraft-forge.service"
mkdir -p "$SYSTEMD_USER_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Forge Minecraft Server (rootless Docker)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start ${CONTAINER_NAME}
ExecStop=/usr/bin/docker stop --time=30 ${CONTAINER_NAME}

[Install]
WantedBy=default.target
EOF

if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user enable minecraft-forge.service
    info "User systemd service enabled → $SERVICE_FILE"

    if loginctl show-user "$USER" 2>/dev/null | grep -q "Linger=yes"; then
        info "Linger enabled – server autostart at boot even without login. ✓"
    else
        warn "────────────────────────────────────────────────────────"
        warn " Linger is NOT enabled for '$USER'."
        warn " Server will only start after you log in."
        warn " Ask your admin to run once:"
        warn "   sudo loginctl enable-linger $USER"
        warn "────────────────────────────────────────────────────────"
    fi
else
    warn "systemctl not found – skipping user service. Use 'make start' instead."
fi

# ── DONE ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Forge Minecraft Server – Setup Complete ✓         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  🌐  Container IP  : ${YELLOW}${STATIC_IP}${NC}  (internal)"
echo -e "  🌐  Connect via   : ${YELLOW}$(hostname -I | awk '{print $1}'):${MC_PORT}${NC}  (LAN)"
echo -e "  🔌  Port          : ${YELLOW}${MC_PORT}${NC}"
echo -e "  💾  Data volume   : ${YELLOW}${VOLUME_NAME}${NC}"
echo -e "  📦  Container     : ${YELLOW}${CONTAINER_NAME}${NC}"
echo ""
echo -e "  TLauncher: launch ${YELLOW}Forge $(docker logs ${CONTAINER_NAME} 2>/dev/null | grep -o 'minecraft version [0-9.]*' | tail -1 | awk '{print $3}' || echo '(check logs)')${NC} and connect to the LAN IP above."
echo ""
echo -e "  Quick commands (use the Makefile):"
echo -e "  ${YELLOW}make start${NC}    ${YELLOW}make stop${NC}    ${YELLOW}make restart${NC}    ${YELLOW}make logs${NC}    ${YELLOW}make status${NC}"
echo ""
echo -e "  ⚠️  First launch takes ${YELLOW}2-5 min${NC} (Forge installs itself)."
echo -e "     Watch: ${YELLOW}make logs${NC}"
echo ""