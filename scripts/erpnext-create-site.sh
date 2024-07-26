#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if the mariadb.env file exists
if [ ! -f "$MARIADB_TARGET_ENV_FILE" ]; then
    echo "The file $MARIADB_TARGET_ENV_FILE does not exist. Aborting."
    exit 1
fi

# Check if the backend container is running
if ! docker compose --project-name erpnext ps | grep -q "backend.*Up"; then
    echo "The backend container is not running. Aborting."
    exit 1
fi

# Read DB_PASSWORD from the mariadb.env file
DB_PASSWORD=$(grep 'DB_PASSWORD' "$MARIADB_TARGET_ENV_FILE" | cut -d '=' -f2)

# Check if DB_PASSWORD was found
if [ -z "$DB_PASSWORD" ]; then
    echo "DB_PASSWORD was not found in the file $MARIADB_TARGET_ENV_FILE. Aborting."
    exit 1
fi

# Prompt interactively for the SITE value
read -p "Please enter the value for SITE (e.g., one.example.com): " SITE

# Check if SITE was entered
if [ -z "$SITE" ]; then
    echo "You did not enter a value for SITE. Aborting."
    exit 1
fi

# Prompt interactively for the ADMIN_PASSWORD
read -s -p "Please enter the password: " ADMIN_PASSWORD
echo
read -s -p "Please confirm the password: " ADMIN_PASSWORD_CONFIRM
echo

# Check if the passwords match
if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
    echo "The passwords do not match. Aborting."
    exit 1
fi

# Create the Docker compose
docker compose --project-name erpnext exec backend \
    bench new-site --no-mariadb-socket --mariadb-root-password $DB_PASSWORD --install-app erpnext --admin-password $ADMIN_PASSWORD $SITE

echo "The site $SITE was successfully created."