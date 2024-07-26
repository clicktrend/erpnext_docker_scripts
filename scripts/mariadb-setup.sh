#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if the target file already exists
if [ -f "$MARIADB_TARGET_ENV_FILE" ]; then
    echo "The file $MARIADB_TARGET_ENV_FILE already exists. Aborting."
    exit 1
fi

# Function to generate a random password
generate_random_password() {
    # Generate a 16-character random password without disruptive characters like '
    tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

# Interactive prompt to ask if a random password should be generated
read -p "Should the password be generated randomly? (yes/no): " GENERATE_PASSWORD

if [[ "$GENERATE_PASSWORD" =~ ^[Yy]es$ ]]; then
    PASSWORD=$(generate_random_password)
    echo "A random password has been generated."
else
    # Prompt for a custom password
    read -s -p "Please enter the password: " PASSWORD
    echo
    read -s -p "Please confirm the password: " PASSWORD_CONFIRM
    echo

    # Check if the passwords match
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "The passwords do not match. Aborting."
        exit 1
    fi
fi

# Create file content
FILE_CONTENT="DB_PASSWORD=$PASSWORD"

# Write to file
echo -e $FILE_CONTENT > $MARIADB_TARGET_ENV_FILE

echo "The file $MARIADB_TARGET_ENV_FILE has been successfully created."