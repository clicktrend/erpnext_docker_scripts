#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Execute the Docker command
docker compose --project-name $ERPNEXT_PROJECT_NAME -f $ERPNEXT_TARGET_YAML_FILE up backup

echo "Backup executed."