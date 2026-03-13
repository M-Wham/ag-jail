#!/bin/bash
# ag-jail Uninstaller

CONTAINER_NAME="ag-safe"
BIN_DIR="$HOME/.local/bin"

echo "Removing ag-jail..."

# 1. Stop and remove container
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true
echo "✔ Container removed"

# 2. Remove binaries
rm -f "$BIN_DIR/ag-start" \
	"$BIN_DIR/ag-kill" \
	"$BIN_DIR/ag-update" \
	"$BIN_DIR/ag-enter"
echo "✔ Binaries removed"

# 3. Optional: Remove data
read -p "Do you want to delete the data folder (~/Antigravity-Jail)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	rm -rf "$HOME/Antigravity-Jail"
	echo "✔ Data folder removed"
fi

echo "Uninstallation complete."
