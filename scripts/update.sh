#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "Updating scripts..."
git pull

echo "Updating frappe_docker fork..."
git -C "$FRAPPE_DOCKER_DIR" pull

echo "Update complete."
