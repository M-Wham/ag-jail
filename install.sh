#!/bin/bash

# ag-jail Installer
# Installs a secure Antigravity IDE environment using raw Podman.
# No Distrobox — full D-Bus isolation, ungoogled-chromium, clean restart lifecycle.

set -eo pipefail

# Configuration
JAIL_DIR="$HOME/Antigravity-Jail"
CONTAINER_NAME="ag-safe"
BIN_DIR="$HOME/.local/bin"
LOG_FILE="$PWD/install.log"
UBUNTU_IMAGE="public.ecr.aws/lts/ubuntu:24.04"

HOST_UID=$(id -u)
HOST_GID=$(id -g)
HOST_USER=$(id -un)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Install a package using the host package manager.
# Args: <pacman-name> <apt-name> <dnf-name> <zypper-name>
pkg_install() {
	if command -v pacman &>/dev/null; then
		sudo pacman -S --noconfirm "$1" >>"$LOG_FILE" 2>&1
	elif command -v apt-get &>/dev/null; then
		sudo apt-get install -y "$2" >>"$LOG_FILE" 2>&1
	elif command -v dnf &>/dev/null; then
		sudo dnf install -y "$3" >>"$LOG_FILE" 2>&1
	elif command -v zypper &>/dev/null; then
		sudo zypper install -y "$4" >>"$LOG_FILE" 2>&1
	else
		return 1
	fi
}

# Clear log file
>"$LOG_FILE"

echo -e "${GREEN}Starting ag-jail Installation...${NC}"
echo "Detailed logs are being saved to: $LOG_FILE"
echo ""

# STEP 1: Dependencies
echo -e "${YELLOW}[1/5] Checking dependencies...${NC}"
if ! command -v podman &>/dev/null; then
	echo -e "${RED}Error: Podman is not installed. Please install podman first.${NC}"
	exit 1
fi
if ! command -v slirp4netns &>/dev/null && ! command -v pasta &>/dev/null; then
	echo -e "${YELLOW}slirp4netns not found, attempting to install...${NC}"
	if ! pkg_install slirp4netns slirp4netns slirp4netns slirp4netns; then
		echo -e "${RED}Could not install slirp4netns automatically. Please install it manually.${NC}"
		exit 1
	fi
fi
if ! command -v xhost &>/dev/null; then
	echo -e "${YELLOW}xhost not found, attempting to install...${NC}"
	if ! pkg_install xorg-xhost x11-xserver-utils xorg-x11-server-utils xhost; then
		echo -e "${RED}Could not install xhost automatically. Please install it manually for your distro.${NC}"
		exit 1
	fi
fi

# Choose network backend: pasta is faster (kernel-backed), slirp4netns is the fallback
if command -v pasta &>/dev/null; then
	NET_MODE="pasta"
else
	NET_MODE="slirp4netns:allow_host_loopback=true"
fi

# STEP 2: Directories
echo -e "${YELLOW}[2/5] Creating jail directory...${NC}"
mkdir -p "$JAIL_DIR" >>"$LOG_FILE" 2>&1
mkdir -p "$BIN_DIR"

# Remove stale Distrobox-era aliases that would shadow the installed binaries
for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
	[ -f "$RC" ] || continue
	sed -i '/^alias ag-start="distrobox /d;/^alias ag-kill="podman kill/d;/^alias ag-update="distrobox /d' "$RC"
done

# STEP 3: Create container
echo -e "${YELLOW}[3/5] Creating container...${NC}"

# If the container exists but is missing the XDG runtime dir mount (e.g. was created
# before Wayland support was added), remove it so it gets recreated correctly.
CONTAINER_NEEDS_CREATE=true
if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
	# Check that the container has all required mounts (rw runtime dir and GPU access)
	MOUNTS=$(podman inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{.Source}}:{{.RW}} {{end}}' 2>/dev/null)
	# HostConfig.Devices is always empty in Podman for directory-level device passthrough;
	# check the original create command args instead.
	CREATE_CMD=$(podman inspect "$CONTAINER_NAME" --format '{{join .Config.CreateCommand " "}}' 2>/dev/null)
	if echo "$MOUNTS" | grep -q "/run/user/$HOST_UID:true" && echo "$CREATE_CMD" | grep -q "/dev/dri" && echo "$CREATE_CMD" | grep -q "$NET_MODE"; then
		echo "Container already exists with correct configuration, skipping creation." >>"$LOG_FILE"
		CONTAINER_NEEDS_CREATE=false
	else
		echo "Container configuration outdated, recreating..." | tee -a "$LOG_FILE"
		podman stop "$CONTAINER_NAME" >>"$LOG_FILE" 2>/dev/null || true
		podman rm "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1
	fi
fi

if [ "$CONTAINER_NEEDS_CREATE" = true ]; then
	podman create \
		--name "$CONTAINER_NAME" \
		--hostname ag-jail \
		--init \
		--userns=keep-id \
		--workdir / \
		--network "$NET_MODE" \
		--dns 1.1.1.1 \
		--dns 8.8.8.8 \
		--device /dev/dri \
		--shm-size=1g \
		-v "$JAIL_DIR:/home/$HOST_USER:z" \
		-v /tmp/.X11-unix:/tmp/.X11-unix:ro \
		-v "/run/user/$HOST_UID:/run/user/$HOST_UID:rw" \
		-e DISPLAY="${DISPLAY:-:0}" \
		-e WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
		-e XDG_RUNTIME_DIR="/run/user/$HOST_UID" \
		-e DBUS_SESSION_BUS_ADDRESS="" \
		-e GTK_USE_PORTAL=0 \
		-e HOME="/home/$HOST_USER" \
		-e USER="$HOST_USER" \
		"$UBUNTU_IMAGE" \
		tail -f /dev/null >>"$LOG_FILE" 2>&1
fi

# STEP 4: Install everything inside the container
echo -e "${YELLOW}[4/5] Setting up container environment...${NC}"
echo "This step may take a few minutes..."
podman start "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1

podman exec --user root "$CONTAINER_NAME" bash -c "
	set -e

	# Ensure the container user is named after the host user.
	# Ubuntu 24.04 images ship a built-in 'ubuntu' user at UID 1000. With
	# --userns=keep-id the host UID maps directly, so we need the name to match.
	# Rename any existing user at HOST_UID that isn't already named correctly,
	# or create the user from scratch if the UID is absent.
	if getent passwd ${HOST_UID} > /dev/null 2>&1; then
		EXISTING=$(getent passwd ${HOST_UID} | cut -d: -f1)
		if [ "\$EXISTING" != "${HOST_USER}" ]; then
			usermod -l ${HOST_USER} -d /home/${HOST_USER} -s /bin/bash "\$EXISTING" 2>/dev/null || true
		else
			usermod -d /home/${HOST_USER} -s /bin/bash ${HOST_USER} 2>/dev/null || true
		fi
	else
		useradd -u ${HOST_UID} -g ${HOST_GID} -d /home/${HOST_USER} -s /bin/bash -M ${HOST_USER} 2>/dev/null || true
	fi

	# Base packages
	apt-get update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
		sudo curl wget gnupg ca-certificates software-properties-common dbus

	# Grant passwordless sudo to jail user for ag-update/etc.
	echo '${HOST_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ag-jail
	chmod 440 /etc/sudoers.d/ag-jail

	# Install ungoogled-chromium
	if ! command -v ungoogled-chromium > /dev/null 2>&1; then
		echo 'Adding xtradeb PPA...' >&2
		add-apt-repository -y ppa:xtradeb/apps
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y ungoogled-chromium
		echo 'ungoogled-chromium installed.' >&2
	else
		echo 'ungoogled-chromium already installed, skipping.' >&2
	fi

	# Container-safe chromium wrapper: --no-sandbox is required because Podman
	# containers have no inner user namespace for the sandbox. GPU and shm are
	# handled at the container level (--device /dev/dri, --shm-size=1g).
	cat > /usr/local/bin/ag-chromium << 'WRAPPER'
#!/bin/sh
exec /usr/bin/ungoogled-chromium --no-sandbox \"\$@\" 2>/dev/null
WRAPPER
	chmod +x /usr/local/bin/ag-chromium

	# Replace xdg-open so Antigravity cannot escape to the host browser via D-Bus.
	cat > /usr/local/bin/xdg-open << 'WRAPPER'
#!/bin/sh
exec /usr/local/bin/ag-chromium \"\$@\"
WRAPPER
	chmod +x /usr/local/bin/xdg-open

	# Symlink common Chrome binary names so Antigravity's auto-detection works.
	ln -sf /usr/local/bin/ag-chromium /usr/local/bin/google-chrome
	ln -sf /usr/local/bin/ag-chromium /usr/local/bin/chromium-browser
	ln -sf /usr/local/bin/ag-chromium /usr/local/bin/chromium

	# Install Antigravity
	if ! command -v antigravity > /dev/null 2>&1; then
		echo 'Adding Antigravity repository...' >&2
		mkdir -p /etc/apt/keyrings
		curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
			gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg

		echo 'deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main' | \
			tee /etc/apt/sources.list.d/antigravity.list > /dev/null

		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y antigravity
		echo 'Antigravity installed.' >&2
	else
		echo 'Antigravity already installed, skipping.' >&2
	fi
" 2>&1 | tee -a "$LOG_FILE"

# Done with setup — stop the container for a clean initial state
podman stop "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1

# Migrate any workspace paths that still contain the host-side jail directory
# prefix. This happens when Antigravity was previously run on the host or in a
# different container where the home was not yet remapped, causing it to store
# paths like file:///home/$HOST_USER/Antigravity-Jail/Project instead of the
# correct container-internal file:///home/$HOST_USER/Project.
if [ -d "$JAIL_DIR/.config/Antigravity" ]; then
echo -e "${YELLOW}Migrating workspace paths...${NC}"
find "$JAIL_DIR/.config/Antigravity" -name "*.json" -not -path "*/History/*" \
	-exec grep -ql "Antigravity-Jail" {} \; \
	-exec sed -i "s|/home/$HOST_USER/Antigravity-Jail/|/home/$HOST_USER/|g" {} \; \
	>>"$LOG_FILE" 2>&1 || true
# Also fix paths stored in SQLite state databases (global + per-workspace)
if command -v sqlite3 &>/dev/null; then
	find "$JAIL_DIR/.config/Antigravity/User" \( -name "state.vscdb" -o -name "state.vscdb.backup" \) | while read db; do
		sqlite3 "$db" \
			"UPDATE ItemTable SET value = replace(replace(value, '/home/$HOST_USER/Antigravity-Jail/', '/home/$HOST_USER/'), '/home/$HOST_USER/Antigravity-Jail\"', '/home/$HOST_USER\"') WHERE value LIKE '%Antigravity-Jail%';" \
			>>"$LOG_FILE" 2>&1 || true
	done
	# sidebarWorkspaces and scratchWorkspaces are protobuf blobs — can't text-replace,
	# so delete them. Antigravity resets them to empty on next launch.
	GLOBAL_DB="$JAIL_DIR/.config/Antigravity/User/globalStorage/state.vscdb"
	if [ -f "$GLOBAL_DB" ]; then
		sqlite3 "$GLOBAL_DB" \
			"DELETE FROM ItemTable WHERE key IN ('antigravityUnifiedStateSync.sidebarWorkspaces', 'antigravityUnifiedStateSync.scratchWorkspaces');" \
			>>"$LOG_FILE" 2>&1 || true
	fi

fi

# Clear GPU/shader caches from the Antigravity agent browser profile.
# These caches may be stale (built against a different GPU context) and can cause
# ungoogled-chromium to crash (SIGTRAP) on first run. Chromium rebuilds them automatically.
BROWSER_PROFILE="$JAIL_DIR/.gemini/antigravity-browser-profile"
if [ -d "$BROWSER_PROFILE" ]; then
	rm -rf \
		"$BROWSER_PROFILE/GPUPersistentCache" \
		"$BROWSER_PROFILE/GrShaderCache" \
		"$BROWSER_PROFILE/GraphiteDawnCache" \
		"$BROWSER_PROFILE/ShaderCache" \
		>>"$LOG_FILE" 2>&1 || true
	echo "Cleared GPU caches from agent browser profile." >>"$LOG_FILE"
fi
fi # end: [ -d "$JAIL_DIR/.config/Antigravity" ]

# STEP 5: Write binaries
echo -e "${YELLOW}[5/5] Writing binaries...${NC}"

# ag-start: launches Antigravity in the sandbox
# - Allows local X11 connections
# - Starts the stopped container
# - Passes current DISPLAY and blocks D-Bus at exec time
# - Stops the container when Antigravity exits (kills any lingering background agents)
cat >"$BIN_DIR/ag-start" <<SCRIPT
#!/bin/bash
cd /
xhost +local: 2>/dev/null || true
echo "Starting container..."
podman start ag-safe
# Remove stale Antigravity IPC sockets so a fresh instance always opens cleanly
podman exec ag-safe pkill -9 antigravity 2>/dev/null || true
rm -f /run/user/\$(id -u)/vscode-*.sock 2>/dev/null || true
echo "Launching Antigravity (window may take 30-60 seconds to appear)..."
podman exec \\
	--user $HOST_USER \\
	-e DISPLAY="\${DISPLAY:-:0}" \\
	-e WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-}" \\
	-e XDG_RUNTIME_DIR="/run/user/\$(id -u)" \\
	-e DBUS_SESSION_BUS_ADDRESS="" \\
	-e GTK_USE_PORTAL=0 \\
	-e HOME="/home/$HOST_USER" \\
	ag-safe \\
	dbus-run-session -- bash -c '
cd /home/$HOST_USER
antigravity "\$@"
# The antigravity CLI (like all VS Code launchers) spawns the Electron GUI as a
# detached orphan process and exits immediately. Wait for the real GUI to finish
# before returning so that the container is not stopped prematurely.
sleep 1
while pgrep -u "\$(id -u)" -x antigravity > /dev/null 2>&1; do
	sleep 2
done
' -- "\$@"
podman stop ag-safe > /dev/null
SCRIPT
chmod +x "$BIN_DIR/ag-start"

# ag-kill: gracefully stops the container (SIGTERM, then SIGKILL after timeout)
# Use this instead of the old 'podman kill' so the container restarts cleanly next time
cat >"$BIN_DIR/ag-kill" <<'SCRIPT'
#!/bin/sh
podman stop ag-safe
SCRIPT
chmod +x "$BIN_DIR/ag-kill"

# ag-update: updates Antigravity and ungoogled-chromium
cat >"$BIN_DIR/ag-update" <<'SCRIPT'
#!/bin/sh
podman start ag-safe > /dev/null
podman exec --user root ag-safe \
	sh -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y antigravity ungoogled-chromium"
podman stop ag-safe > /dev/null
echo ""
echo "Update complete."
echo "NOTE: If Antigravity prompts you to set the Chrome binary path, enter:"
echo "  /usr/local/bin/ag-chromium"
SCRIPT
chmod +x "$BIN_DIR/ag-update"

# ag-enter: opens a shell inside the container for debugging or installing extras
cat >"$BIN_DIR/ag-enter" <<SCRIPT
#!/bin/bash
if ! podman ps --format '{{.Names}}' | grep -q '^ag-safe$'; then
	echo "Starting container..."
	podman start ag-safe > /dev/null
fi
podman exec -it \\
	--user $HOST_USER \\
	--workdir /home/$HOST_USER \\
	-e DISPLAY="\${DISPLAY:-:0}" \\
	-e WAYLAND_DISPLAY="\${WAYLAND_DISPLAY:-}" \\
	-e XDG_RUNTIME_DIR="/run/user/\$(id -u)" \\
	-e DBUS_SESSION_BUS_ADDRESS="" \\
	-e GTK_USE_PORTAL=0 \\
	-e HOME="/home/$HOST_USER" \\
	ag-safe \\
	bash
SCRIPT
chmod +x "$BIN_DIR/ag-enter"

echo -e "\n${GREEN}✔ Installation Complete!${NC}"
echo "Commands:"
echo "  ag-start  — launch the IDE"
echo "  ag-kill   — stop the container"
echo "  ag-enter  — open a shell in the container (for installs/debugging)"
echo "  ag-update — update Antigravity and ungoogled-chromium"

# Always remind to open a new terminal — shell aliases from old installs survive
# in the current session even after .bashrc is edited.
echo -e "\n${YELLOW}ACTION REQUIRED:${NC} Open a new terminal before running ag-start."
echo "Existing terminals may still have old aliases that will intercept the commands."

echo -e "\n${YELLOW}ANTIGRAVITY BROWSER SETUP:${NC}"
echo "To use the Antigravity agent browser tools, set the Chrome binary path in"
echo "Antigravity settings (Browser section) to:"
echo -e "  ${GREEN}/usr/local/bin/ag-chromium${NC}"
echo "This wrapper enables ungoogled-chromium to run inside the container."

# PATH check
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
	echo -e "\n${RED}NOTE:${NC} '$HOME/.local/bin' is not in your PATH yet."
	echo "Please restart your terminal or run: source ~/.profile"
fi
