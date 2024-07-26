#!/bin/bash

# Source the common file
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Check if the target file already exists
if [ -f "$ERPNEXT_TARGET_ENV_FILE" ]; then
    echo "The file $ERPNEXT_TARGET_ENV_FILE already exists. Aborting."
    exit 1
fi

# Check if the mariadb.env file exists
if [ ! -f "$MARIADB_TARGET_ENV_FILE" ]; then
    echo "The file $MARIADB_TARGET_ENV_FILE does not exist. Aborting."
    exit 1
fi

# Read DB_PASSWORD from the mariadb.env file
DB_PASSWORD=$(grep 'DB_PASSWORD' "$MARIADB_TARGET_ENV_FILE" | cut -d '=' -f2)

# Check if DB_PASSWORD was found
if [ -z "$DB_PASSWORD" ]; then
    echo "DB_PASSWORD was not found in the file $MARIADB_TARGET_ENV_FILE. Aborting."
    exit 1
fi

# Check if the traefik.env file exists
if [ ! -f "$TRAEFIK_TARGET_ENV_FILE" ]; then
    echo "The file $TRAEFIK_TARGET_ENV_FILE does not exist. Aborting."
    exit 1
fi

# Read EMAIL from the traefik.env file
EMAIL=$(grep 'EMAIL' "$TRAEFIK_TARGET_ENV_FILE" | cut -d '=' -f2)

# Check if EMAIL was found
if [ -z "$EMAIL" ]; then
    echo "EMAIL was not found in the file $TRAEFIK_TARGET_ENV_FILE. Aborting."
    exit 1
fi

# Prompt for the value for SITES
read -p "Please enter the value for SITES (e.g. one.example.com): " SITES

# Check if SITES was entered
if [ -z "$SITES" ]; then
    echo "You did not enter a value for SITES. Aborting."
    exit 1
fi

# Copy the file
cp $ERPNEXT_EXAMPLE_SOURCE_FILE $ERPNEXT_TARGET_ENV_FILE

# Replace placeholders in the target file
sed -i "s/DB_PASSWORD=123/DB_PASSWORD=$DB_PASSWORD/g" $ERPNEXT_TARGET_ENV_FILE
sed -i "s/LETSENCRYPT_EMAIL=mail@example.com/LETSENCRYPT_EMAIL=$EMAIL/g" $ERPNEXT_TARGET_ENV_FILE
sed -i 's/DB_HOST=/DB_HOST=mariadb-database/g' $ERPNEXT_TARGET_ENV_FILE
sed -i 's/DB_PORT=/DB_PORT=3306/g' $ERPNEXT_TARGET_ENV_FILE
sed -i "s/SITES=\`erp.example.com\`/SITES=\`$SITES\`/g" $ERPNEXT_TARGET_ENV_FILE

# Define PROJECT_NAME and replace . with -
PROJECT_NAME="erpnext-$(echo "$SITES" | tr '.' '-')"
echo "ROUTER=$PROJECT_NAME" >> $ERPNEXT_TARGET_ENV_FILE
echo "BENCH_NETWORK=$PROJECT_NAME" >> $ERPNEXT_TARGET_ENV_FILE

echo "The file $ERPNEXT_TARGET_ENV_FILE has been successfully created."

# Create Docker Compose
docker compose --project-name erpnext --env-file $ERPNEXT_TARGET_ENV_FILE \
  -f $FRAPPE_DOCKER_DIR/compose.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.redis.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.multi-bench.yaml \
  -f $FRAPPE_DOCKER_DIR/overrides/compose.multi-bench-ssl.yaml config > $ERPNEXT_TARGET_YAML_FILE

echo "The file $ERPNEXT_TARGET_YAML_FILE has been successfully created."