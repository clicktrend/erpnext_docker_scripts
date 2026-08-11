#!/bin/bash
# Reclaim disk space after a successful deploy.
#
# Why this exists: erpnext-custom-setup.sh builds with --no-cache, so every
# single deploy produces a complete fresh layer set (~4.6 GB custom + ~3.8 GB
# base) plus a new build cache -- and nothing ever removed the old ones. By
# 2026-08-10 the host had accumulated 59 images / 84 GB, sat at 88 % disk with
# 19 GB left, and was a few deploys away from a full disk (which corrupts
# MariaDB). Cleaning it out by hand freed 99 GB. This script keeps it from
# happening again.
#
# It runs at the END of a successful deploy on purpose: for as long as the
# deploy can still fail, the previous image is the rollback target and must
# stay. Never wire it in earlier.
#
# Kept, always:
#   * every image used by a running container (also protected by docker itself,
#     since we never pass --force)
#   * base:latest -- the input for the next build
#   * the KEEP_RELEASES most recent tags of each managed repository
#
# Usage:
#   scripts/prune-images.sh              # prune
#   scripts/prune-images.sh --dry-run    # show what would go, change nothing
#   KEEP_RELEASES=5 scripts/prune-images.sh
#
# Exits 0 even when individual steps fail: housekeeping must never turn a
# successful deploy into a failed one.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

KEEP_RELEASES="${KEEP_RELEASES:-3}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Repositories this script is allowed to touch. Anything else on the host
# (traefik, mariadb, unrelated leftovers) is deliberately out of scope -- an
# automatic cleanup should only ever delete what its own pipeline created.
MANAGED_REPOS=("$ERPNEXT_CUSTOM_IMAGE" "base")

say() { echo "  $*"; }
disk_used() { df -P / | awk 'NR==2 {print $3}'; }
disk_line() { df -Ph / | awk 'NR==2 {printf "%s belegt, %s frei (%s)", $3, $4, $5}'; }

BEFORE=$(disk_used)
echo ""
echo "──────────────────────────────────────────"
echo "  Aufräumen: $(disk_line)"
[ "$DRY_RUN" = "1" ] && echo "  (--dry-run: es wird nichts gelöscht)"
echo "──────────────────────────────────────────"

# --- images currently backing a container -----------------------------------
mapfile -t RUNNING < <(docker ps --format '{{.Image}}' 2>/dev/null | sort -u)
say "in Benutzung: ${#RUNNING[@]} Image(s)"

is_protected() {
  local img=$1
  [ "$img" = "base:latest" ] && return 0
  local r
  for r in "${RUNNING[@]}"; do [ "$img" = "$r" ] && return 0; done
  return 1
}

# --- collect removal candidates ---------------------------------------------
DELETE=()
for repo in "${MANAGED_REPOS[@]}"; do
  # Newest first. CreatedAt sorts correctly as a string ("2026-08-08 10:23:45
  # +0000 UTC"), which beats sorting the version tag -- 0.0.10 would otherwise
  # rank below 0.0.9.
  mapfile -t TAGGED < <(
    docker images --format '{{.CreatedAt}}|{{.Repository}}:{{.Tag}}' "$repo" 2>/dev/null \
      | grep -v '<none>' | sort -r | cut -d'|' -f2
  )
  [ "${#TAGGED[@]}" -eq 0 ] && continue

  local_kept=0
  for img in "${TAGGED[@]}"; do
    if is_protected "$img"; then
      continue
    elif [ "$local_kept" -lt "$KEEP_RELEASES" ]; then
      local_kept=$((local_kept + 1))
    else
      DELETE+=("$img")
    fi
  done
  say "$repo: ${#TAGGED[@]} Tags, behalte die $KEEP_RELEASES neuesten (+ laufende)"
done

# --- remove -----------------------------------------------------------------
if [ "${#DELETE[@]}" -eq 0 ]; then
  say "keine veralteten Tags"
else
  say "veraltet: ${#DELETE[@]} Tags"
  for img in "${DELETE[@]}"; do say "  - $img"; done
  if [ "$DRY_RUN" = "0" ]; then
    # No --force: anything unexpectedly still referenced stays put and merely
    # reports a conflict, rather than being ripped out from under a container.
    docker rmi "${DELETE[@]}" >/dev/null 2>&1 || say "  (einzelne Tags blieben, siehe 'docker images')"
  fi
fi

if [ "$DRY_RUN" = "0" ]; then
  # Dangling layers left behind by the removals above and by --fresh rebuilds.
  docker image prune -f >/dev/null 2>&1 || true
  # With --no-cache builds the cache is never reused -- it is pure ballast.
  docker builder prune -af >/dev/null 2>&1 || true
  # Anonymous volumes pile up on every compose down/up. Without --all, named
  # volumes (erpnext_sites, mariadb_db-data) are out of reach by construction;
  # in-use volumes are protected regardless.
  docker volume prune -f >/dev/null 2>&1 || true
fi

AFTER=$(disk_used)
FREED=$(( (BEFORE - AFTER) / 1024 ))
echo ""
if [ "$DRY_RUN" = "1" ]; then
  say "Vorschau beendet, nichts verändert."
else
  say "freigegeben: ${FREED} MB"
  say "jetzt: $(disk_line)"
fi
echo ""

exit 0
