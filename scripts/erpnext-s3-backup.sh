#!/bin/bash
# ERPNext -> S3 backup.
#
# Creates a Frappe database backup inside the backend container and uploads it
# (plus the site_config backup, which holds the encryption_key needed for a full
# restore) to S3 via rclone. Designed to be run by the erpnext-backup.timer
# systemd unit.
#
# Disk-safe: the DB dump is a few MB and is streamed out of the container with
# `docker exec cat`, so nothing large is staged on the (currently near-full)
# host disk. File/attachment backups are intentionally NOT done here yet -- they
# would create multi-GB tarballs locally; enable only after the host disk has
# headroom (see README).
#
# The IAM user is write-only (s3:PutObject + s3:ListBucket, no Delete/Get). So:
#   - uploads use --no-check-dest (no HEAD on destination -> no GetObject needed)
#   - retention is handled by an S3 lifecycle rule on the bucket, NOT by this
#     script. The rclone-delete prune below is opt-in (ENABLE_S3_PRUNE=1) for the
#     case where the user is later granted s3:DeleteObject.
#
# Config lives in .configs/backup.env (git-ignored, not synced). Optional:
#   RCLONE_REMOTE     rclone remote name (default: s3backup)
#   S3_BUCKET         target bucket (default: backup-erp-adomio-com)
#   ENABLE_S3_PRUNE   1 to delete S3 objects older than RETENTION_DAYS (default 0)
#   RETENTION_DAYS    age threshold for prune (default: 30)

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
cd "$ROOT_DIR" || { echo "cannot cd to $ROOT_DIR"; exit 1; }

# --- defaults (override in .configs/backup.env) ---
PROJECT_NAME="erpnext"
SITE="erp.adomio.com"
BENCH_DIR="/home/frappe/frappe-bench"
RCLONE_REMOTE="s3backup"
S3_BUCKET="backup-erp-adomio-com"
S3_PREFIX="db"
ENABLE_S3_PRUNE="0"
RETENTION_DAYS="30"

# Optional env overrides + rclone credentials remote.
[ -f "$ROOT_DIR/.configs/backup.env" ] && source "$ROOT_DIR/.configs/backup.env"
export RCLONE_CONFIG="${RCLONE_CONFIG:-$ROOT_DIR/.configs/rclone.conf}"

log() { echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') [erpnext-s3-backup] $*"; }
fail() { log "ERROR: $*"; exit 1; }

command -v rclone >/dev/null 2>&1 || fail "rclone not installed on host"
[ -f "$RCLONE_CONFIG" ] || fail "rclone config not found: $RCLONE_CONFIG"

DC=(docker compose --project-name "$PROJECT_NAME")

STAGE_DIR="$(mktemp -d /tmp/erpnext-backup.XXXXXX)"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

log "creating DB backup for $SITE ..."
"${DC[@]}" exec -T backend bench --site "$SITE" backup >/dev/null \
  || fail "bench backup failed"

# Newest DB dump + its matching site_config backup (same timestamp prefix).
DBFILE="$("${DC[@]}" exec -T backend bash -c \
  "ls -t $BENCH_DIR/sites/$SITE/private/backups/*-database.sql.gz | head -1" | tr -d '\r')"
[ -n "$DBFILE" ] || fail "no database dump found after backup"
PREFIX="${DBFILE%-database.sql.gz}"
CFGFILE="${PREFIX}-site_config_backup.json"
DBNAME="$(basename "$DBFILE")"
CFGNAME="$(basename "$CFGFILE")"

log "streaming $DBNAME out of container ..."
"${DC[@]}" exec -T backend cat "$DBFILE" > "$STAGE_DIR/$DBNAME"
"${DC[@]}" exec -T backend cat "$CFGFILE" > "$STAGE_DIR/$CFGNAME" 2>/dev/null || true

[ -s "$STAGE_DIR/$DBNAME" ] || fail "streamed dump is empty"
gzip -t "$STAGE_DIR/$DBNAME" || fail "streamed dump failed gzip integrity check"
SIZE="$(du -h "$STAGE_DIR/$DBNAME" | cut -f1)"

# S3 key: db/YYYY/MM/<timestamped-filename>. --no-check-dest avoids a HEAD on the
# destination so the write-only IAM user needs no s3:GetObject.
DEST="$RCLONE_REMOTE:$S3_BUCKET/$S3_PREFIX/$(date -u +%Y/%m)"
log "uploading ($SIZE) to $DEST ..."
# --s3-no-head: skip the post-upload HEAD integrity check (needs s3:GetObject,
# which the write-only user lacks). --no-check-dest / --s3-no-check-bucket avoid
# the pre-flight HEAD/CreateBucket. Together: a pure PutObject-only upload.
rclone copy "$STAGE_DIR/" "$DEST/" \
  --s3-server-side-encryption AES256 \
  --s3-no-check-bucket --s3-no-head --no-check-dest --stats-one-line \
  || fail "rclone upload failed"

# Retention is normally an S3 lifecycle rule (server-side). Only prune from the
# client if explicitly enabled AND the IAM user has s3:DeleteObject.
if [ "${ENABLE_S3_PRUNE:-0}" = "1" ]; then
  log "pruning S3 objects older than ${RETENTION_DAYS}d under $S3_PREFIX/ ..."
  rclone delete "$RCLONE_REMOTE:$S3_BUCKET/$S3_PREFIX" \
    --min-age "${RETENTION_DAYS}d" --rmdirs || log "WARN: prune step failed (non-fatal)"
fi

log "done: $DBNAME uploaded to s3://$S3_BUCKET/$S3_PREFIX/$(date -u +%Y/%m)/"
