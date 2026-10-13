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

# ── Options ────────────────────────────────────────────────────────────────────
# Without options the script asks for the image tag and confirms the build, as before.
# An ssh session does not survive the ~20 min build, so a run without anyone at the
# terminal goes detached and answers both questions up front:
#   setsid nohup scripts/deploy.sh --tag 0.0.19.5 --yes > /tmp/deploy-0.0.19.5.log 2>&1 &
#   --tag <tag>  new ERPNEXT_CUSTOM_TAG, no prompt
#   --yes        no "Start build?" confirmation. Needs --tag with a NEW tag: the previous
#                image must stay on the host under its own tag for a rollback.
NEW_TAG=""
TAG_GIVEN=0
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)    NEW_TAG="${2:-}"; TAG_GIVEN=1; shift; [ $# -gt 0 ] && shift ;;
    --tag=*)  NEW_TAG="${1#--tag=}"; TAG_GIVEN=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    *) echo "Unknown option: $1 (allowed: --tag <tag>, --yes)" >&2; exit 2 ;;
  esac
done
if [ "$TAG_GIVEN" -eq 1 ] && ! [[ "$NEW_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Invalid --tag '$NEW_TAG' (letters, digits, '.', '_', '-')." >&2
  exit 2
fi
if [ "$ASSUME_YES" -eq 1 ] && [ "$TAG_GIVEN" -eq 0 ]; then
  echo "--yes needs --tag <new tag>: a build without anyone watching must not reuse the running image's tag." >&2
  exit 2
fi

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
step "1/9  Update scripts + frappe_docker"
# A failed pull used to print an error and carry on with whatever apps.json was on disk
# (the 2026-08-10 drift). The lock's apps.json only arrives through this pull, so it must succeed.
scripts/update.sh || { echo "Update failed (git pull). Aborting before anything is built." >&2; exit 1; }

# ── Step 2: apps.json = tags only ──────────────────────────────────────────────
# Versions are written in one place, deploy/erpnext-stack.lock.json in the parent repo
# (adomio-desktop), and rendered into this repo's apps.json; step 1 pulled it. Editing it here
# made the server the only place that knew what ran (v0.0.16.1 to v0.0.19.3), so it is not offered
# any more. A branch clones whatever its head is that day, so only tags may stand in apps.json.
step "2/9  apps.json (tags only, from the version lock)"
# Only the committed, pushed apps.json is the lock's. A local edit survives a pull that does not
# touch the file, and a local commit is something git elsewhere does not know: both would build a
# version the gate never saw.
if ! git diff --quiet HEAD -- apps.json; then
  echo "Aborted: apps.json has local changes; it must come from the version lock through git." >&2
  echo "  Compare with 'git diff apps.json', then let a human discard the change and pull (release runbook)." >&2
  exit 1
fi
if [ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}' 2>/dev/null)" ]; then
  echo "Aborted: this checkout is not at its upstream ($(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo 'none')); deploy only from the pushed state." >&2
  exit 1
fi
echo ""
# Private repos (git@…, e.g. adomio on GitLab) are only readable with the build's deploy key —
# the same key erpnext-custom-setup.sh hands to the build as a secret. Without it ls-remote fails
# with "Permission denied", which this check used to report as a missing tag (first lock deploy,
# 2026-10-13). So: read with the deploy key, and tell "no access" apart from "no such tag".
LS_REMOTE_SSH="ssh -i $DEPLOY_KEY_FILE -o IdentitiesOnly=yes -o BatchMode=yes"
bad=0
while read -r url ref; do
  if ! out=$(GIT_SSH_COMMAND="$LS_REMOTE_SSH" git ls-remote --tags "$url" "refs/tags/$ref" 2>&1); then
    printf '  %-45s %s  <- KEIN ZUGRIFF (%s)\n' "${url##*/}" "$ref" "$(printf '%s' "$out" | grep -m1 -i -E 'denied|fatal|error' | cut -c1-60)"; bad=1
  elif printf '%s' "$out" | grep -q "refs/tags/$ref"; then
    printf '  %-45s %s\n' "${url##*/}" "$ref"
  else
    printf '  %-45s %s  <- KEIN TAG\n' "${url##*/}" "$ref"; bad=1
  fi
done < <(python3 -c 'import json,sys; [print(a["url"], a["branch"]) for a in json.load(open(sys.argv[1]))]' "$ERPNEXT_CUSTOM_APPS_JSON_FILE")
if [ "$bad" -ne 0 ]; then
  echo "Aborted: apps.json has a ref that is not a readable tag (see above). A missing tag: change" >&2
  echo "  deploy/erpnext-stack.lock.json, render, commit, pull. No access: check $DEPLOY_KEY_FILE on that repo." >&2
  exit 1
fi

# ── Step 3: Bump version tag ───────────────────────────────────────────────────
step "3/9  Version tag"
echo "Current ERPNEXT_CUSTOM_TAG: $ERPNEXT_CUSTOM_TAG"
if [ "$TAG_GIVEN" -eq 0 ]; then
  read -rp "New tag (leave empty to keep '$ERPNEXT_CUSTOM_TAG'): " NEW_TAG
elif [ "$ASSUME_YES" -eq 1 ] && [ "$NEW_TAG" = "$ERPNEXT_CUSTOM_TAG" ]; then
  echo "Aborted: --tag $NEW_TAG is the running image's tag; a build without confirmation needs a new one." >&2
  exit 1
fi
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
if [ "$ASSUME_YES" -eq 1 ]; then
  echo "Start build? yes (--yes)"
else
  confirm "Start build?" || { echo "Aborted."; exit 0; }
fi

# ── Step 4: Build ──────────────────────────────────────────────────────────────
step "4/9  Build custom image + generate compose"
scripts/erpnext-custom-setup.sh --fresh || { echo "Build failed. Aborting."; exit 1; }

# ── Step 5: Restart ────────────────────────────────────────────────────────────
step "5/9  Restart ERPNext"
scripts/erpnext-custom-docker.sh restart || { echo "Restart failed. Aborting."; exit 1; }

# ── Step 6: Backup ─────────────────────────────────────────────────────────────
# `bench migrate` is the point of no return: patches rename DocTypes and drop columns,
# and there is no `migrate --undo`. The nightly S3 backup can be up to 24h old, which is
# 24h of production work to re-enter by hand. So: take one immediately before.
step "6/9  Backup site (DB + files) before migrating"
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
step "7/9  Migrate + build assets"
scripts/erpnext-backend.sh bench migrate || { echo "Migration failed. Aborting."; exit 1; }
scripts/erpnext-backend.sh bench build   || { echo "Asset build failed. Aborting."; exit 1; }

# ── Step 8: Final restart ──────────────────────────────────────────────────────
step "8/9  Final restart"
scripts/erpnext-custom-docker.sh restart || { echo "Restart failed."; exit 1; }

# ── Step 9: Housekeeping ───────────────────────────────────────────────────────
# Deliberately last. Every `exit 1` above leaves the previous image intact, which
# is what a rollback needs; only a deploy that got this far may throw it away.
# Because the build runs --no-cache, each deploy adds a full layer set (~8 GB
# with its base) that nothing used to remove -- the host reached 88 % disk this
# way. See scripts/prune-images.sh.
step "9/9  Clean up old images"
scripts/prune-images.sh || echo "  (Aufräumen übersprungen — Deploy ist davon unberührt)"

echo ""
echo "══════════════════════════════════════════"
echo "  Deployment complete: $ERPNEXT_CUSTOM_IMAGE:$ERPNEXT_CUSTOM_TAG"
echo "══════════════════════════════════════════"
