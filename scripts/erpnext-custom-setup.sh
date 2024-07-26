#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if $ERPNEXT_CUSTOM_APPS_JSON_FILE exists
if [ ! -f "$ERPNEXT_CUSTOM_APPS_JSON_FILE" ]; then
  # Copy example apps.json to .configs folder if it doesn't exist
  cp "$FRAPPE_DOCKER_DIR/development/apps-example.json" "$ERPNEXT_CUSTOM_APPS_JSON_FILE"
  echo "Example apps.json has been copied to $ERPNEXT_CUSTOM_APPS_JSON_FILE."
else
  echo "The file $ERPNEXT_CUSTOM_APPS_JSON_FILE already exists. Skipping copy."
fi

# Encode the apps.json file in Base64
APPS_JSON_BASE64=$(base64 -w 0 "$ERPNEXT_CUSTOM_APPS_JSON_FILE")

# Decode the Base64 encoded string to verify it
DECODED_APPS_JSON=$(echo "$APPS_JSON_BASE64" | base64 --decode)

# Output the decoded JSON for verification
echo "Decoded JSON from Base64:"
echo "$DECODED_APPS_JSON"

# Check if ERPNEXT_TARGET_ENV_FILE exists
if [ ! -f "$ERPNEXT_TARGET_ENV_FILE" ]; then
  echo "The file $ERPNEXT_TARGET_ENV_FILE does not exist. Aborting."
  exit 1
fi

# Build Docker image
docker build \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=$ERPNEXT_CUSTOM_IMAGE:$ERPNEXT_CUSTOM_TAG \
  --file=$FRAPPE_DOCKER_DIR/images/custom/Containerfile $FRAPPE_DOCKER_DIR

echo "Custom image has been created."

# Export environment variables
export CUSTOM_IMAGE=$ERPNEXT_CUSTOM_IMAGE
export CUSTOM_TAG=$ERPNEXT_CUSTOM_TAG
export PULL_POLICY='never'

docker compose --project-name erpnext --env-file $ERPNEXT_TARGET_ENV_FILE \
  -f $FRAPPE_DOCKER_DIR/compose.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.redis.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.multi-bench.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.multi-bench-ssl.yaml config > $ERPNEXT_CUSTOM_TARGET_YAML_FILE

# Unset environment variables
unset CUSTOM_IMAGE
unset CUSTOM_TAG
unset PULL_POLICY

echo "Environment variables have been unset."

# Output success message
if [ $? -eq 0 ]; then
    echo "Docker Compose configuration has been successfully created and written to $ERPNEXT_CUSTOM_TARGET_YAML_FILE."
else
    echo "There was a problem creating the Docker Compose configuration."
    exit 1
fi