#!/bin/bash

set -e

CONFIG_DIR="$HOME/.config"
CONFIG_FILE="$CONFIG_DIR/pihole_backup.env"

# Colors
COLOR_RESET="\033[0m"
COLOR_CYAN="\033[0;36m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[1;33m"

echo -e "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "${COLOR_CYAN}  Pi-hole Backup Password Setup${COLOR_RESET}"
echo -e "${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"

# Check if config file already exists
if [ -f "$CONFIG_FILE" ]; then
  echo -e "${COLOR_YELLOW}Warning: Configuration file already exists at:${COLOR_RESET}"
  echo "  $CONFIG_FILE"
  echo ""
  read -p "Overwrite it? (y/N): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Prompt for password
echo "Enter your Pi-hole admin password:"
read -s PIHOLE_PASSWORD
echo ""

if [ -z "$PIHOLE_PASSWORD" ]; then
  echo -e "${COLOR_YELLOW}Error: Password cannot be empty${COLOR_RESET}"
  exit 1
fi

# Write config file
cat > "$CONFIG_FILE" << EOF
# Pi-hole backup configuration
# This file is sourced by pihole_backup_and_sync.sh
PIHOLE_PASSWORD='$PIHOLE_PASSWORD'
EOF

# Set secure permissions (owner read/write only)
chmod 600 "$CONFIG_FILE"

echo -e "${COLOR_GREEN}✓${COLOR_RESET} Configuration saved to: $CONFIG_FILE"
echo -e "${COLOR_GREEN}✓${COLOR_RESET} Permissions set to 600 (owner read/write only)"
echo ""
echo "You can now run: ./pihole_backup_and_sync.sh"
echo ""
