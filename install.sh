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
UBUNTU_IMAGE="public.ecr.aws/lts/ubuntu:22.04"

HOST_UID=$(id -u)
HOST_GID=$(id -g)
HOST_USER=$(id -un)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Clear log file
>"$LOG_FILE"

echo -e "${GREEN}Starting ag-jail Installation...${NC}"
echo "Detailed logs are being saved to: $LOG_FILE"
echo ""

# STEP 1: Dependencies
echo -e "${YELLOW}[1/7] Checking dependencies...${NC}"
if ! command -v podman &>/dev/null; then
	echo -e "${RED}Error: Podman is not installed. Please install podman first.${NC}"
	exit 1
fi
if ! command -v xhost &>/dev/null; then
	echo -e "${YELLOW}Warning: xhost not found. X11 display auth may not work correctly.${NC}"
fi

# STEP 2: Directories
echo -e "${YELLOW}[2/7] Creating jail directory...${NC}"
mkdir -p "$JAIL_DIR" >>"$LOG_FILE" 2>&1
mkdir -p "$BIN_DIR"

# STEP 3: Create container
echo -e "${YELLOW}[3/7] Creating container...${NC}"
if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
	echo "Container already exists, skipping creation." >>"$LOG_FILE"
else
	podman create \
		--name "$CONTAINER_NAME" \
		--hostname ag-jail \
		--init \
		--userns=keep-id \
		-v "$JAIL_DIR:/home/$HOST_USER:z" \
		-v /tmp/.X11-unix:/tmp/.X11-unix:ro \
		-e DISPLAY="${DISPLAY:-:0}" \
		-e DBUS_SESSION_BUS_ADDRESS="" \
		-e HOME="/home/$HOST_USER" \
		-e USER="$HOST_USER" \
		"$UBUNTU_IMAGE" \
		tail -f /dev/null >>"$LOG_FILE" 2>&1
fi

# STEP 4: Container base setup
echo -e "${YELLOW}[4/7] Setting up container environment...${NC}"
podman start "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1

podman exec --user root "$CONTAINER_NAME" bash -c "
	set -e
	# Fix home directory in /etc/passwd (Podman auto-creates entry with home=/)
	if grep -q '^${HOST_USER}:' /etc/passwd; then
		usermod -d /home/${HOST_USER} -s /bin/bash ${HOST_USER} 2>/dev/null || true
	fi

	apt-get update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
		sudo curl wget gnupg ca-certificates software-properties-common

	# Grant passwordless sudo to jail user for ag-update/etc.
	echo '${HOST_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ag-jail
	chmod 440 /etc/sudoers.d/ag-jail
" 2>&1 | tee -a "$LOG_FILE"

# STEP 5: Install ungoogled-chromium
echo -e "${YELLOW}[5/7] Installing ungoogled-chromium...${NC}"
echo "This step may take a few minutes..."
podman exec --user root "$CONTAINER_NAME" bash -c "
	set -e
	if ! command -v ungoogled-chromium > /dev/null 2>&1; then
		echo 'Adding xtradeb PPA...' >&2
		add-apt-repository -y ppa:xtradeb/apps
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y ungoogled-chromium
		echo 'ungoogled-chromium installed.' >&2
	else
		echo 'ungoogled-chromium already installed, skipping.' >&2
	fi

	# Replace xdg-open with a wrapper that always uses ungoogled-chromium.
	# /usr/local/bin takes priority over /usr/bin, so this shadows the real xdg-open.
	# This is the key fix for preventing Antigravity from opening the host browser via D-Bus.
	cat > /usr/local/bin/xdg-open << 'WRAPPER'
#!/bin/sh
exec ungoogled-chromium \"\$@\" 2>/dev/null
WRAPPER
	chmod +x /usr/local/bin/xdg-open
" 2>&1 | tee -a "$LOG_FILE"

# STEP 6: Install Antigravity
echo -e "${YELLOW}[6/7] Installing Antigravity...${NC}"
podman exec --user root "$CONTAINER_NAME" bash -c "
	set -e
	if ! command -v antigravity > /dev/null 2>&1; then
		echo 'Adding Antigravity repository...' >&2
		mkdir -p /etc/apt/keyrings
		curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
			gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg

		echo 'deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main' | \
			tee /etc/apt/sources.list.d/antigravity.list > /dev/null

		echo 'Installing Antigravity...' >&2
		apt-get update -qq
		DEBIAN_FRONTEND=noninteractive apt-get install -y antigravity
		echo 'Antigravity installed.' >&2
	else
		echo 'Antigravity already installed, skipping.' >&2
	fi
" 2>&1 | tee -a "$LOG_FILE"

# Done with setup — stop the container for a clean initial state
podman stop "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1

# STEP 7: Write binaries
echo -e "${YELLOW}[7/7] Writing binaries...${NC}"

# ag-start: launches Antigravity in the sandbox
# - Allows local X11 connections
# - Starts the stopped container
# - Passes current DISPLAY and blocks D-Bus at exec time
# - Stops the container when Antigravity exits (kills any lingering background agents)
cat >"$BIN_DIR/ag-start" <<SCRIPT
#!/bin/bash
xhost +local: 2>/dev/null || true
podman start ag-safe > /dev/null
podman exec \\
	--user $HOST_USER \\
	-e DISPLAY="\${DISPLAY:-:0}" \\
	-e DBUS_SESSION_BUS_ADDRESS="" \\
	-e HOME="/home/$HOST_USER" \\
	ag-safe \\
	antigravity "\$@"
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
	-e DISPLAY="\${DISPLAY:-:0}" \\
	-e DBUS_SESSION_BUS_ADDRESS="" \\
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

# PATH check
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
	echo -e "\n${RED}NOTE:${NC} '$HOME/.local/bin' is not in your PATH yet."
	echo "Please restart your terminal or run: source ~/.profile"
fi
