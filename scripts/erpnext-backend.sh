#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo "Please provide a command to execute."
    exit 1
fi

# Assemble the command from the arguments
COMMAND="$*"

# Check if the backend container is running
if ! docker compose --project-name erpnext ps | grep -q "backend.*Up"; then
    echo "The backend container is not running. Aborting."
    exit 1
fi

# Execute the Docker command
docker compose --project-name $ERPNEXT_PROJECT_NAME exec backend $COMMAND

# Check if the command was successful
if [ $? -eq 0 ]; then
    echo "The command '$COMMAND' was executed successfully."
else
    echo "There was a problem executing the command '$COMMAND'."
    exit 1
fi