#!/bin/bash

# Determine the absolute path of the script
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."

# Change to the root directory
cd "$ROOT_DIR" || { echo "Failed to change to the root directory. Aborting."; exit 1; }

# Load environment variables from the .env file
if [ ! -f ".env" ]; then
    echo ".env does not exist. Run setup.sh first! Aborting."
    exit 1
fi

source ".env"