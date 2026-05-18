#!/usr/bin/env bash

set -euo pipefail

USER="$1"

if [ -z "$USER" ]; then
    echo 'Username is required'
    exit 1
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git/identities"
CONFIG_FILE="$CONFIG_DIR/$USER"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration for '$USER' not found. Available identities:"
    ls "$CONFIG_DIR" 2>/dev/null | sed 's/^/  /'
    exit 1
fi

git config --local include.path "$CONFIG_FILE"

echo "Git user configuration updated successfully for $USER"