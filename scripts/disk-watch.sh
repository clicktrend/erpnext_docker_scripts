#!/bin/bash
# Disk watchdog for the ERPNext production host.
#
# Run by erpnext-disk-watch.timer (every 15 min). Alerts via scripts/notify.sh
# when the root filesystem crosses a usage threshold, and again -- once -- when
# it recovers.
#
# Why this exists: on 2026-08-07 the host sat at 79% with 109 GB of the 113 GB
# used being reclaimable Docker image layers. A full disk corrupts MariaDB, and
# nothing on the host would have said a word.
#
# Config (optional, .configs/alerts.env):
#   DISK_WARN_PCT    default 80
#   DISK_CRIT_PCT    default 90
#   DISK_MOUNT       default /
#   INODE_WARN_PCT   default 85
#
# State is kept so a standing condition alerts once per level, not every 15 min.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
NOTIFY="$SCRIPT_DIR/notify.sh"

[ -f "$ROOT_DIR/.configs/alerts.env" ] && source "$ROOT_DIR/.configs/alerts.env"

DISK_MOUNT="${DISK_MOUNT:-/}"
DISK_WARN_PCT="${DISK_WARN_PCT:-80}"
DISK_CRIT_PCT="${DISK_CRIT_PCT:-90}"
INODE_WARN_PCT="${INODE_WARN_PCT:-85}"

# Overridable so the level/repeat logic can be exercised without root.
STATE_DIR="${ALERT_STATE_DIR:-/var/lib/erpnext-alerts}"
STATE_FILE="$STATE_DIR/disk-watch.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true

USED_PCT="$(df -P "$DISK_MOUNT" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
AVAIL_H="$(df -Ph "$DISK_MOUNT" | awk 'NR==2 {print $4}')"
SIZE_H="$(df -Ph "$DISK_MOUNT" | awk 'NR==2 {print $2}')"
INODE_PCT="$(df -Pi "$DISK_MOUNT" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

# Sanity: df failed or returned nonsense -> stay quiet rather than alert-storm.
case "$USED_PCT" in
  ''|*[!0-9]*) logger -p daemon.err -t erpnext-disk-watch "could not read df for $DISK_MOUNT"; exit 0 ;;
esac

PREV="$(cat "$STATE_FILE" 2>/dev/null || echo ok)"

if   [ "$USED_PCT" -ge "$DISK_CRIT_PCT" ]; then LEVEL=crit
elif [ "$USED_PCT" -ge "$DISK_WARN_PCT" ]; then LEVEL=warn
else                                            LEVEL=ok
fi

# Inode exhaustion looks like a healthy disk in `df -h` -- treat it as at least warn.
INODE_NOTE=""
case "$INODE_PCT" in
  ''|*[!0-9]*) : ;;
  *) if [ "$INODE_PCT" -ge "$INODE_WARN_PCT" ]; then
       INODE_NOTE="inodes: ${INODE_PCT}% used  <-- inode exhaustion also fills a disk"
       [ "$LEVEL" = "ok" ] && LEVEL=warn
     fi ;;
esac

# Where the space went, so the alert is actionable instead of merely alarming.
#
# Everything in the alert path MUST be time-bounded. The first version ran
# `du -x --max-depth=1 /var/lib/docker` here; on the real host that tree is
# ~100 GB across a huge overlay2 file count and the walk takes minutes -- long
# enough for systemd's TimeoutStartSec to kill the unit before the alert was
# ever sent. A watchdog that hangs exactly when it should fire is worse than
# none. `docker system df` reads Docker's own bookkeeping instead: ~0.6 s on
# the same host, and it reports the reclaimable share, which is the number
# somebody actually acts on.
top_consumers() {
  timeout 15 docker system df 2>/dev/null \
    || echo "(docker system df lieferte nicht rechtzeitig - Host pruefen)"
}

if [ "$LEVEL" != "$PREV" ]; then
  case "$LEVEL" in
    ok)
      "$NOTIFY" info "Disk wieder unter Schwellwert ($DISK_MOUNT)" \
        "Belegung: ${USED_PCT}% von ${SIZE_H} (${AVAIL_H} frei)"
      ;;
    warn|crit)
      "$NOTIFY" "$LEVEL" "Disk ${USED_PCT}% belegt auf ${DISK_MOUNT}" \
"Groesse: ${SIZE_H}, frei: ${AVAIL_H}
Schwellwerte: warn ${DISK_WARN_PCT}% / crit ${DISK_CRIT_PCT}%
${INODE_NOTE}

Groesste Verbraucher:
$(top_consumers)

Aufraeumen (pruefen, dann ausfuehren):
  docker image prune -a
  docker builder prune
  docker volume prune"
      ;;
  esac
  echo "$LEVEL" > "$STATE_FILE" 2>/dev/null || true
fi

exit 0
