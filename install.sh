#!/bin/bash

# ag-jail Installer
# Installs a secure Google Antigravity environment.

set -e

# Configuration
JAIL_DIR="$HOME/Antigravity-Jail"
CONTAINER_NAME="ag-safe"
BIN_DIR="$HOME/.local/bin"
LOG_FILE="install.log"

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
echo -e "${YELLOW}[1/6] Checking dependencies...${NC}"
if ! command -v podman &>/dev/null; then
	echo -e "${RED}Error: Podman is not installed. Please install podman first.${NC}"
	exit 1
fi
if ! command -v distrobox &>/dev/null; then
	echo -e "${RED}Error: Distrobox is not installed. Please install distrobox first.${NC}"
	exit 1
fi

# STEP 2: Directories
echo -e "${YELLOW}[2/6] Creating jail directory...${NC}"
mkdir -p "$JAIL_DIR" >>"$LOG_FILE" 2>&1

# STEP 3: Container
echo -e "${YELLOW}[3/6] Building container (This may take a minute)...${NC}"
if distrobox list | grep -q "$CONTAINER_NAME"; then
	echo "Container exists, skipping creation." >>"$LOG_FILE"
else
	distrobox create --name "$CONTAINER_NAME" --image public.ecr.aws/lts/ubuntu:22.04 --home "$JAIL_DIR" --yes >>"$LOG_FILE" 2>&1
fi

# STEP 4: Internal Chrome
echo -e "${YELLOW}[4/6] Installing Internal Chrome...${NC}"
distrobox enter "$CONTAINER_NAME" -- sh -c "if ! command -v google-chrome > /dev/null 2>&1; then wget -q -O chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo apt-get update -qq && sudo apt-get install -y ./chrome.deb -qq && rm chrome.deb && xdg-settings set default-web-browser google-chrome.desktop; fi" >>"$LOG_FILE" 2>&1

# STEP 5: Antigravity
echo -e "${YELLOW}[5/6] Installing Antigravity...${NC}"
distrobox enter "$CONTAINER_NAME" -- sh -c "if ! command -v antigravity > /dev/null 2>&1; then sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg && echo 'deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main' | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null && sudo apt-get update -qq && sudo apt-get install -y antigravity -qq; fi" >>"$LOG_FILE" 2>&1

# STEP 6: Binaries
echo -e "${YELLOW}[6/6] Finalizing setup...${NC}"
mkdir -p "$BIN_DIR"

# ag-start
echo '#!/bin/sh' >"$BIN_DIR/ag-start"
echo "distrobox enter $CONTAINER_NAME -- antigravity \"\$@\"" >>"$BIN_DIR/ag-start"
chmod +x "$BIN_DIR/ag-start"

# ag-kill
echo '#!/bin/sh' >"$BIN_DIR/ag-kill"
echo "podman kill $CONTAINER_NAME" >>"$BIN_DIR/ag-kill"
chmod +x "$BIN_DIR/ag-kill"

# ag-update
echo '#!/bin/sh' >"$BIN_DIR/ag-update"
echo "distrobox enter $CONTAINER_NAME -- sh -c \"sudo apt update && sudo apt install antigravity -y\"" >>"$BIN_DIR/ag-update"
chmod +x "$BIN_DIR/ag-update"

echo -e "\n${GREEN}✔ Installation Complete!${NC}"
echo "You can now run 'ag-start' to launch the IDE."

# Path Check
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
	echo -e "${RED}NOTE:${NC} '$HOME/.local/bin' is not in your PATH yet."
	echo "Please restart your terminal or run: source ~/.profile"
fi
