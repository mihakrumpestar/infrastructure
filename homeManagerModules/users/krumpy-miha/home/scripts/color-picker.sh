#!/usr/bin/env bash

# Set script to exit if any command fails
set -e

function pick() {
    qdbus --literal org.kde.KWin.ScreenShot2 /ColorPicker org.kde.kwin.ColorPicker.pick | sed 's/^[^0-9]*//;s/[^0-9]*$//;'
}

function to_hex() {
    local decimal=$1
    # Extract RGB components (reverse byte order)
    local blue=$((decimal & 255))
    local green=$(((decimal >> 8) & 255))
    local red=$(((decimal >> 16) & 255))
    # Format as 6-digit RGB hex
    printf "%02x%02x%02x" "$red" "$green" "$blue"
}

color=$(pick)
hex_color="#$(to_hex "$color")"

# Copy to Wayland clipboard using wl-copy
echo -n "$hex_color" | wl-copy

# Optional: Print the color to stdout as well
echo "$hex_color"