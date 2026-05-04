# 🎮 Forge Minecraft Server — Rootless Docker

A fully containerised Forge Minecraft server running on rootless Docker.
No root or sudo required. Persistent world data, auto-restart on crash,
and survives logout via systemd user linger.

---

## 📋 Requirements

| Requirement              | Notes                              |
| ------------------------ | ---------------------------------- |
| Rootless Docker          | Already configured on your machine |
| `make`                   | For Makefile commands              |
| `bash`                   | For the setup script               |
| `loginctl enable-linger` | Already done ✅                    |

---

## 📁 Project Structure

```
minecraft/
├── setup_minecraft.sh   # First-time setup script
├── docker-compose.yml   # Container definition
├── Makefile             # Server management commands
└── README.md            # This file
```

---

## 🚀 First-Time Setup

Run the setup script once. It will:

- Create the Docker bridge network (`mc_net`, `10.1.0.0/16`)
- Create a persistent named volume (`minecraft_data`)
- Pull the latest `itzg/minecraft-server` image
- Start the Forge container with the correct settings
- Install and enable the systemd user service

```bash
bash setup_minecraft.sh
```

Custom container IP (internal only):

```bash
MINECRAFT_IP=10.1.100.100 bash setup_minecraft.sh
```

> ⚠️ First launch takes **2–5 minutes** — Forge downloads and installs itself inside the container. Watch progress with `make logs`.

---

## 🛠️ Daily Management (Makefile)

All server management is done through the Makefile:

```bash
make setup      # First-time full setup
make start      # Start the server
make stop       # Gracefully stop the server (30s timeout)
make restart    # Restart the server
make logs       # Tail live server logs (Ctrl+C to exit)
make status     # Show container state + IP addresses
make console    # Open the in-game server console
make backup     # Save world data to ./backups/
make nuke       # ⚠️  Delete container + world data (irreversible)
```

---

## 🔌 Connecting in TLauncher

| Setting           | Value                                |
| ----------------- | ------------------------------------ |
| Server address    | `10.1.8.4:25565`                     |
| TLauncher version | **Forge 26.1.2** (must match server) |
| Account type      | TL or any non-premium account        |

> The container has an internal IP of `10.1.100.100` inside the Docker
> network, but due to rootless Docker's network namespace isolation this
> IP is not reachable from outside. Always connect via `10.1.8.4:25565`.

---

## ⚙️ Server Configuration

All settings live in `docker-compose.yml` under `environment:`.
Edit the file then run `make restart` to apply.

| Environment variable       | Default        | Description                                  |
| -------------------------- | -------------- | -------------------------------------------- |
| `TYPE`                     | `FORGE`        | Server type                                  |
| `VERSION`                  | `LATEST`       | Minecraft version                            |
| `EULA`                     | `TRUE`         | Must accept Mojang EULA                      |
| `MEMORY`                   | `4G`           | JVM heap size                                |
| `ONLINE_MODE`              | `FALSE`        | `FALSE` = allows TLauncher / cracked clients |
| `PAUSE_WHEN_EMPTY_SECONDS` | `0`            | Disabled — server never pauses               |
| `DIFFICULTY`               | `normal`       | `peaceful` / `easy` / `normal` / `hard`      |
| `MAX_PLAYERS`              | `20`           | Max concurrent players                       |
| `MOTD`                     | `Forge Server` | Server list message                          |

For settings not exposed as environment variables, edit `server.properties` directly:

```bash
make console
# then type any server command, e.g:
# difficulty hard
# whitelist on
# op yourname
```

Or edit the file directly:

```bash
docker exec minecraft_forge sh -c "echo 'setting=value' >> /data/server.properties"
make restart
```

---

## 🔄 Autostart & Persistence

| Feature                     | How                                  |
| --------------------------- | ------------------------------------ |
| Auto-restart on crash       | `--restart unless-stopped` (Docker)  |
| Start on boot without login | systemd user service + linger        |
| Persistent world data       | Named Docker volume `minecraft_data` |

The systemd user service is installed at:

```
~/.config/systemd/user/minecraft-forge.service
```

Check its status:

```bash
systemctl --user status minecraft-forge.service
```

---

## 💾 Backups

Run `make backup` to create a timestamped archive of the world data:

```bash
make backup
# → backups/world_20260504_182400.tar.gz
```

To restore a backup:

```bash
make stop
docker run --rm \
  -v minecraft_data:/data \
  -v $(pwd)/backups:/backups \
  busybox tar xzf /backups/world_TIMESTAMP.tar.gz -C /data
make start
```

---

## 🧩 Adding Mods

Place `.jar` mod files into the container's `/data/mods/` folder:

```bash
# Copy a mod from your machine into the container
docker cp mymod.jar minecraft_forge:/data/mods/

# Restart to load it
make restart
```

> ⚠️ Mods must match the server's Forge and Minecraft version (`26.1.2` / Forge `64.0.7`).
> Players must also have the same mods installed on their TLauncher client.

---

## 🐛 Troubleshooting

**Server shows `Can't connect` in TLauncher**

- Check the server is running: `make status`
- Check it has fully started: `make logs` → look for `Done!`
- Make sure TLauncher is launching **Forge 26.1.2**, not vanilla

**`Incompatible FML modded server` error**

- You are connecting with vanilla Minecraft instead of Forge
- In TLauncher, select `Forge 26.1.2` from the version dropdown

**Server pauses after 60 seconds**

- `PAUSE_WHEN_EMPTY_SECONDS=0` is already set — run `make restart` to re-apply

**Container IP `10.1.100.100` is unreachable**

- Expected behaviour with rootless Docker — use `10.1.8.4:25565` instead
- The internal IP is only used for container-to-container communication

**systemd service fails with `No such file or directory`**

- Docker is not at `/usr/bin/docker` on this machine
- Fix: `sed -i "s|/usr/bin/docker|$(which docker)|g" ~/.config/systemd/user/minecraft-forge.service`
- Then: `systemctl --user daemon-reload && systemctl --user restart minecraft-forge.service`

---

## 🌐 Network Architecture

```
School LAN (10.1.0.0/16)
│
├── Your machine          10.1.8.4        (eno2 physical interface)
│   │
│   └── Docker bridge     mc_net
│       gateway           10.1.0.1
│       │
│       └── minecraft_forge container     10.1.100.100
│               port 25565 ──────────────────────────── mapped to host :25565
│
└── Other players on LAN
        connect to → 10.1.8.4:25565 ✅
        cannot reach → 10.1.100.100  ❌ (rootless Docker isolation)
```

---

## 📌 Quick Reference

```bash
# Connect address for players
10.1.8.4:25565

# TLauncher version
Forge 26.1.2

# Watch server start
make logs

# Open server console
make console

# Backup world
make backup
```

## To run minecraft Tlauncher:

```bash
java -jar TLauncher.jar
```
