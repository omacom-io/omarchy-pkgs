#!/bin/bash
# Setup script for omarchy-nvim
# This can be called from Omarchy setup scripts

set -euo pipefail

PACKAGE_DIR="/usr/share/omarchy-nvim"
CONFIG_DIR="${HOME}/.config/nvim"
DATA_DIR="${HOME}/.local/share/nvim"
STATE_DIR="${HOME}/.local/state/nvim"
CACHE_DIR="${HOME}/.cache/nvim"

# Check if package is installed
if [[ ! -d "$PACKAGE_DIR" ]]; then
  echo "Error: omarchy-nvim package not installed"
  exit 1
fi

# Check if nvim config already exists
if [[ -d "$CONFIG_DIR" ]]; then
  if gum confirm "$(echo -e "Neovim configuration already exists at $CONFIG_DIR.\nThis will create a backup and overwrite it. Continue?")"; then
    # Backup existing config
    BACKUP_DIR="${CONFIG_DIR}.backup.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing config to $BACKUP_DIR"
    mv "$CONFIG_DIR" "$BACKUP_DIR"
  else
    echo "Setup cancelled."
    exit 0
  fi
fi

echo "Setting up Neovim configuration..."

# Make sure everything is clear
rm -rf $DATA_DIR $CACHE_DIR $STATE_DIR

# Create directories if needed
mkdir -p "$(dirname "$CONFIG_DIR")"
mkdir -p "$(dirname "$DATA_DIR")"

# Copy files (cache will be regenerated on first use)
cp -r "$PACKAGE_DIR/config" "$CONFIG_DIR"
cp -r "$PACKAGE_DIR/data" "$DATA_DIR"

# Ensure proper ownership of all nvim directories
chown -R "${USER}:${USER}" "$CONFIG_DIR"
chown -R "${USER}:${USER}" "$DATA_DIR"

# Create link for current theme
ln -snf "${HOME}/.config/omarchy/current/theme/neovim.lua" "${CONFIG_DIR}/lua/plugins/theme.lua"

# Restore git working trees
for dir in $DATA_DIR/lazy/*/; do
  if [ -d "$dir/.git" ]; then
    git --git-dir="$dir/.git" --work-tree="$dir" restore .
  fi
done

# Set nvim.desktop as default so it takes priority in Nautilus
xdg-mime default nvim.desktop text/plain
xdg-mime default nvim.desktop text/english
xdg-mime default nvim.desktop text/x-makefile
xdg-mime default nvim.desktop text/x-c++hdr
xdg-mime default nvim.desktop text/x-c++src
xdg-mime default nvim.desktop text/x-chdr
xdg-mime default nvim.desktop text/x-csrc
xdg-mime default nvim.desktop text/x-java
xdg-mime default nvim.desktop text/x-moc
xdg-mime default nvim.desktop text/x-pascal
xdg-mime default nvim.desktop text/x-tcl
xdg-mime default nvim.desktop text/x-tex
xdg-mime default nvim.desktop application/x-shellscript
xdg-mime default nvim.desktop text/x-c
xdg-mime default nvim.desktop text/x-c++
xdg-mime default nvim.desktop application/xml
xdg-mime default nvim.desktop text/xml

echo "Neovim setup complete!"
