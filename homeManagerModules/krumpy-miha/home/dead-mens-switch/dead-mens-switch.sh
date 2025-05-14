#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Treat unset variables as an error when substituting.
set -u

# The return value of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if no command exited with a non-zero status.
set -o pipefail

error_exit() { 
    DISPLAY=:0 notify-send -u critical -t 9999999 "Dead mens switch upload failed" "$1"
    exit 1
}
trap 'error_exit "An error occurred on line $LINENO."' ERR

# Retrieve all secrets at once
SECRET_SERVICE_RAW=$(secret-tool lookup UserName "dead mens switch")

# Function to extract specific values from the JSON
get_value() {
    echo "$SECRET_SERVICE_RAW" | jq -r ".$1"
}

# Set variables
SOURCE_DIR_RAW=$(get_value "source_dir")
SOURCE_DIR=$(eval echo "$SOURCE_DIR_RAW")
ARCHIVE_NAME="dead_mens_switch_$(date +'%Y-%m-%d_%H:%M').7z"
TMP_ARCHIVE_PATH="/tmp/$ARCHIVE_NAME"
ZIP_PASSWORD=$(get_value "zip_password")
FTP_HOST=$(get_value "ftp_host")
FTP_USER=$(get_value "ftp_user")
FTP_PASS=$(get_value "ftp_pass")

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR" >&2
    exit 1
fi

# Create password-protected 7-zip file in /tmp
7z a -t7z -m0=lzma2 -mx=9 -mfb=64 -md=32m -ms=on -mhe=on -p"$ZIP_PASSWORD" -mmt=on -mtc=on -mtm=on -mta=on "$TMP_ARCHIVE_PATH" "$SOURCE_DIR"

# Upload using curl
curl -T "$TMP_ARCHIVE_PATH" "ftp://$FTP_HOST" --user "$FTP_USER:$FTP_PASS"

# Clean up
rm "$TMP_ARCHIVE_PATH"

# Send system notification
DISPLAY=:0 notify-send -t 50000 "Dead mens switch upload successfull" "The file $ARCHIVE_NAME has been uploaded."

echo "Script completed successfully."