#!/bin/bash

# Determine the absolute path of the script
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."

# Change to the root directory
cd "$ROOT_DIR" || { echo "Failed to change to the root directory. Aborting."; exit 1; }

# Check if .env exists and copy example.env to .env if not
if [ ! -f ".env" ]; then
  if [ -f "example.env" ]; then
    cp "example.env" ".env"
    echo "example.env has been copied to .env."

    # Prompt to adjust the .env file
    echo "Please adjust the .env file and run the script again."
    exit 1
  else
    echo "example.env does not exist. Aborting."
    exit 1
  fi
fi

# Load environment variables from the .env file
source ".env"

# Check if the INSTALLED variable is set to false
if grep -q "INSTALLED=false" ".env"; then
  echo "The INSTALLED variable is set to false. Please adjust the .env file and run the script again."
  exit 1
fi

echo "INSTALLATION begins..."

# Create .configs directory in the root directory if it does not exist
mkdir -p "$CONFIGS_DIR"
echo "$CONFIGS_DIR created."

# Check if the frappe_docker directory already exists
if [ -d "frappe_docker" ]; then
  echo "The frappe_docker directory already exists. Skipping cloning."
else
  # Clone the repository
  git clone https://github.com/frappe/frappe_docker.git $FRAPPE_DOCKER_DIR
  echo "Repository https://github.com/frappe/frappe_docker.git has been cloned into $FRAPPE_DOCKER_DIR."
fi