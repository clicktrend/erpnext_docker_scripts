#!/bin/bash

# Include the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if the environment file exists
if [ ! -f "$TRAEFIK_TARGET_ENV_FILE" ]; then
    echo "The environment file $TRAEFIK_TARGET_ENV_FILE does not exist. Aborting."
    exit 1
fi

# Function to run the Docker Compose command
run_docker_compose() {
  local ACTION=$1
  case $ACTION in
    up)
      docker compose --project-name $TRAEFIK_PROJECT_NAME \
        --env-file $TRAEFIK_TARGET_ENV_FILE \
        -f $TRAEFIK_COMPOSE_FILE_1 \
        -f $TRAEFIK_COMPOSE_FILE_2 up -d
      ;;
    down)
      docker compose --project-name $TRAEFIK_PROJECT_NAME \
        --env-file $TRAEFIK_TARGET_ENV_FILE \
        -f $TRAEFIK_COMPOSE_FILE_1 \
        -f $TRAEFIK_COMPOSE_FILE_2 down
      ;;
    logs)
      docker compose --project-name $TRAEFIK_PROJECT_NAME \
        --env-file $TRAEFIK_TARGET_ENV_FILE \
        -f $TRAEFIK_COMPOSE_FILE_1 \
        -f $TRAEFIK_COMPOSE_FILE_2 logs
      ;;
    *)
      echo "Invalid action: $ACTION"
      exit 1
      ;;
  esac

  # Check if the command was successful
  if [ $? -eq 0 ]; then
      echo "Docker Compose successfully executed with action '$ACTION'."
  else
      echo "There was a problem executing Docker Compose with action '$ACTION'."
      exit 1
  fi
}

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo "Please provide an argument: 'up', 'down', or 'logs'."
    exit 1
fi

# Process the argument
case $1 in
    up|down|logs)
        run_docker_compose $1
        ;;
    *)
        echo "Invalid argument. Please use 'up', 'down', or 'logs'."
        exit 1
        ;;
esac