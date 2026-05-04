# =============================================================================
#  Makefile – Forge Minecraft Server Manager
#  Usage: make <target>
# =============================================================================

CONTAINER  = minecraft_forge
NETWORK    = mc_net
SUBNET     = 10.1.0.0/16
GATEWAY    = 10.1.0.1
IP        ?= 10.1.8.4   # override: make setup IP=10.1.5.10

.PHONY: help setup start stop restart logs status console backup nuke

# ── DEFAULT ───────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  Forge Minecraft Server – available commands:"
	@echo ""
	@echo "  make setup      – first-time setup (creates network, volume, container)"
	@echo "  make start      – start the server"
	@echo "  make stop       – gracefully stop the server (30s timeout)"
	@echo "  make restart    – restart the server"
	@echo "  make logs       – tail live server logs (Ctrl+C to exit)"
	@echo "  make status     – show container status and assigned IP"
	@echo "  make console    – open the in-game server console (Ctrl+C to exit)"
	@echo "  make backup     – backup world data to ./backups/"
	@echo "  make nuke       – ⚠️  destroy container + volume (world data deleted!)"
	@echo ""
	@echo "  Override IP:  make setup IP=10.1.5.10"
	@echo ""

# ── SETUP ─────────────────────────────────────────────────────────────────────
setup:
	@echo "[setup] Creating network if needed…"
	@docker network inspect $(NETWORK) > /dev/null 2>&1 || \
		docker network create --driver bridge --subnet $(SUBNET) --gateway $(GATEWAY) $(NETWORK)
	@echo "[setup] Creating volume if needed…"
	@docker volume inspect minecraft_data > /dev/null 2>&1 || \
		docker volume create minecraft_data
	@echo "[setup] Pulling image…"
	@docker pull itzg/minecraft-server:latest
	@echo "[setup] Removing old container if exists…"
	@docker rm -f $(CONTAINER) 2>/dev/null || true
	@echo "[setup] Starting container with IP $(IP)…"
	@MINECRAFT_IP=$(IP) docker compose up -d
	@echo ""
	@echo "  ✓ Server started. Connect via: $$(hostname -I | awk '{print $$1}'):25565"
	@echo "  Run 'make logs' to watch startup (takes 2-5 min first time)."
	@echo ""

# ── START ─────────────────────────────────────────────────────────────────────
start:
	@echo "[start] Starting $(CONTAINER)…"
	@docker start $(CONTAINER)
	@echo "  ✓ Started. Connect: $$(hostname -I | awk '{print $$1}'):25565"

# ── STOP ──────────────────────────────────────────────────────────────────────
stop:
	@echo "[stop] Stopping $(CONTAINER) gracefully…"
	@docker stop --time=30 $(CONTAINER)
	@echo "  ✓ Server stopped."

# ── RESTART ───────────────────────────────────────────────────────────────────
restart:
	@echo "[restart] Restarting $(CONTAINER)…"
	@docker restart $(CONTAINER)
	@echo "  ✓ Restarted. Run 'make logs' to confirm startup."

# ── LOGS ──────────────────────────────────────────────────────────────────────
logs:
	@docker logs -f $(CONTAINER)

# ── STATUS ────────────────────────────────────────────────────────────────────
status:
	@echo ""
	@echo "  Container:"
	@docker ps -a --filter name=$(CONTAINER) --format "    {{.Names}}  status={{.Status}}  ports={{.Ports}}"
	@echo ""
	@echo "  IP inside Docker network:"
	@docker inspect $(CONTAINER) \
		--format "    {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" 2>/dev/null || echo "    (container not running)"
	@echo ""
	@echo "  LAN IP to share with players:"
	@echo "    $$(hostname -I | awk '{print $$1}'):25565"
	@echo ""

# ── CONSOLE ───────────────────────────────────────────────────────────────────
console:
	@echo "[console] Attaching to server console (type 'stop' to shut down, Ctrl+C to detach)…"
	@docker exec -it $(CONTAINER) rcon-cli

# ── BACKUP ────────────────────────────────────────────────────────────────────
backup:
	@mkdir -p backups
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	echo "[backup] Saving world data to backups/world_$$TIMESTAMP.tar.gz …"; \
	docker run --rm \
		-v minecraft_data:/data:ro \
		-v $$(pwd)/backups:/backups \
		busybox tar czf /backups/world_$$TIMESTAMP.tar.gz -C /data .; \
	echo "  ✓ Backup saved to backups/world_$$TIMESTAMP.tar.gz"

# ── NUKE ──────────────────────────────────────────────────────────────────────
nuke:
	@echo "⚠️  This will DELETE the container AND all world data."
	@read -p "   Type YES to confirm: " confirm; \
	if [ "$$confirm" = "YES" ]; then \
		docker rm -f $(CONTAINER) 2>/dev/null || true; \
		docker volume rm minecraft_data 2>/dev/null || true; \
		echo "  ✓ Container and volume removed."; \
	else \
		echo "  Aborted."; \
	fi
