#!/usr/bin/env bash

set -euo pipefail

USER="$1"

if [ -z "$USER" ]; then
    echo 'Username is required'
    exit 1
fi

CONFIG_FILE="$HOME/.git/$USER"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration for $USER not found"
    exit 1
fi

git config --local include.path "$CONFIG_FILE"

echo "Git user configuration updated successfully for $USER"