#!/bin/bash

# Include the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if the target file already exists
if [ -f "$TRAEFIK_TARGET_ENV_FILE" ]; then
    echo "The file $TRAEFIK_TARGET_ENV_FILE already exists. Aborting."
    exit 1
fi

# Interactive user input
read -p "Please enter the TRAEFIK_DOMAIN: " TRAEFIK_DOMAIN
read -p "Please enter the EMAIL: " EMAIL

# Prompt for password and hash it
read -s -p "Please enter the password: " PASSWORD
echo
read -s -p "Please confirm the password: " PASSWORD_CONFIRM
echo

# Check if the passwords match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Passwords do not match. Aborting."
    exit 1
fi

# Hash the password (openssl must be installed)
HASHED_PASSWORD=$(openssl passwd -apr1 "$PASSWORD")

# Create file content
FILE_CONTENT="TRAEFIK_DOMAIN=$TRAEFIK_DOMAIN\nEMAIL=$EMAIL\nHASHED_PASSWORD='$HASHED_PASSWORD'"

# Write to file
echo -e "$FILE_CONTENT" > "$TRAEFIK_TARGET_ENV_FILE"

echo "The file $TRAEFIK_TARGET_ENV_FILE has been successfully created."