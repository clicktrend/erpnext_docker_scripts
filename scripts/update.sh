#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "Updating scripts..."
# This checkout carries apps.json from the version lock; a failed pull must stop the deploy
# (deploy.sh checks this exit code since 2026-10-13).
git pull || { echo "git pull failed in $(pwd). Aborting." >&2; exit 1; }

echo "Updating frappe_docker fork..."
# The fork checkout has its own local override on the server; a failed pull here keeps
# building from its current checkout, as before, but says so.
git -C "$FRAPPE_DOCKER_DIR" pull || echo "  (frappe_docker pull failed — building from its current checkout)" >&2

echo "Update complete."
