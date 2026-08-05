#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────
confirm() {
  read -rp "$1 [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

step() {
  echo ""
  echo "──────────────────────────────────────────"
  echo "  $1"
  echo "──────────────────────────────────────────"
}

# ── Preflight: Deploy key ──────────────────────────────────────────────────────
DEPLOY_KEY_FILE="${CONFIGS_DIR}/deploy_key"
if [ ! -f "$DEPLOY_KEY_FILE" ]; then
  echo ""
  echo "  ERROR: Deploy key not found at $DEPLOY_KEY_FILE"
  echo ""
  echo "  Generate it once with:"
  echo "    ssh-keygen -t ed25519 -C 'erpnext-build-deploy-key' -f $DEPLOY_KEY_FILE -N ''"
  echo "  Then add the public key as a read-only Deploy Key in GitLab."
  exit 1
fi

# ── Step 1: Update ─────────────────────────────────────────────────────────────
step "1/8  Update scripts + frappe_docker"
scripts/update.sh

# ── Step 2: apps.json review ───────────────────────────────────────────────────
step "2/8  Review apps.json"
echo ""
cat "$ERPNEXT_CUSTOM_APPS_JSON_FILE"
echo ""
if confirm "Edit apps.json before building?"; then
  ${EDITOR:-nano} "$ERPNEXT_CUSTOM_APPS_JSON_FILE"
fi

# ── Step 3: Bump version tag ───────────────────────────────────────────────────
step "3/8  Version tag"
echo "Current ERPNEXT_CUSTOM_TAG: $ERPNEXT_CUSTOM_TAG"
read -rp "New tag (leave empty to keep '$ERPNEXT_CUSTOM_TAG'): " NEW_TAG
if [ -n "$NEW_TAG" ]; then
  sed -i "s/^ERPNEXT_CUSTOM_TAG=.*/ERPNEXT_CUSTOM_TAG=$NEW_TAG/" .env
  export ERPNEXT_CUSTOM_TAG=$NEW_TAG
  echo "Tag set to: $ERPNEXT_CUSTOM_TAG"
fi

# ── Confirm before building ────────────────────────────────────────────────────
echo ""
echo "Ready to deploy with:"
echo "  FRAPPE_BRANCH = $FRAPPE_BRANCH"
echo "  CUSTOM_IMAGE  = $ERPNEXT_CUSTOM_IMAGE:$ERPNEXT_CUSTOM_TAG"
echo "  APPS          = $(cat $ERPNEXT_CUSTOM_APPS_JSON_FILE | grep url | awk -F'"' '{print $4}' | paste -sd ', ')"
echo ""
confirm "Start build?" || { echo "Aborted."; exit 0; }

# ── Step 4: Build ──────────────────────────────────────────────────────────────
step "4/8  Build custom image + generate compose"
scripts/erpnext-custom-setup.sh --fresh || { echo "Build failed. Aborting."; exit 1; }

# ── Step 5: Restart ────────────────────────────────────────────────────────────
step "5/8  Restart ERPNext"
scripts/erpnext-custom-docker.sh restart || { echo "Restart failed. Aborting."; exit 1; }

# ── Step 6: Backup ─────────────────────────────────────────────────────────────
# `bench migrate` is the point of no return: patches rename DocTypes and drop columns,
# and there is no `migrate --undo`. The nightly S3 backup can be up to 24h old, which is
# 24h of production work to re-enter by hand. So: take one immediately before.
step "6/8  Backup site (DB + files) before migrating"
scripts/erpnext-backend.sh bench --site all backup --with-files || { echo "Backup failed. Aborting BEFORE migrate."; exit 1; }

# A backup that silently wrote nothing is worse than no backup, because it buys false
# confidence for the step that follows. Prove a fresh, plausibly-sized dump landed.
docker compose --project-name "$ERPNEXT_PROJECT_NAME" exec -T backend bash -lc '
  newest=$(ls -t sites/*/private/backups/*-database.sql.gz 2>/dev/null | head -1)
  [ -n "$newest" ] || { echo "  no backup file found at all"; exit 1; }
  age=$(( $(date +%s) - $(stat -c %Y "$newest") ))
  size=$(stat -c %s "$newest")
  printf "  %s\n  %s bytes, %ss old\n" "$newest" "$size" "$age"
  [ "$age" -lt 1800 ] || { echo "  that backup predates this run — nothing was written now"; exit 1; }
  [ "$size" -gt 1048576 ] || { echo "  under 1 MB — implausible for this site"; exit 1; }
' || { echo "Backup verification failed. Aborting BEFORE migrate."; exit 1; }

# ── Step 7: Migrate + Build assets ────────────────────────────────────────────
step "7/8  Migrate + build assets"
scripts/erpnext-backend.sh bench migrate || { echo "Migration failed. Aborting."; exit 1; }
scripts/erpnext-backend.sh bench build   || { echo "Asset build failed. Aborting."; exit 1; }

# ── Step 8: Final restart ──────────────────────────────────────────────────────
step "8/8  Final restart"
scripts/erpnext-custom-docker.sh restart || { echo "Restart failed."; exit 1; }

echo ""
echo "══════════════════════════════════════════"
echo "  Deployment complete: $ERPNEXT_CUSTOM_IMAGE:$ERPNEXT_CUSTOM_TAG"
echo "══════════════════════════════════════════"
