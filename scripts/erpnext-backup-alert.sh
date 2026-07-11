#!/bin/bash
# OnFailure handler for erpnext-backup.service. Invoked by
# erpnext-backup-alert@.service with the failed unit name as $1.
#
# Makes a silent backup failure loud: writes to the journal (err priority) and a
# persistent log file, and -- if configured in .configs/backup.env -- POSTs to a
# webhook and/or emails the failure with the last lines of the failed run.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
[ -f "$ROOT_DIR/.configs/backup.env" ] && source "$ROOT_DIR/.configs/backup.env"

UNIT="${1:-erpnext-backup.service}"
HOST="$(hostname)"
WHEN="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
MSG="ERPNext backup FAILED: $UNIT on $HOST at $WHEN"
LOGFILE="/var/log/erpnext-backup.log"

# 1) Journal (shows up in `journalctl -p err`)
logger -p daemon.err -t erpnext-backup "$MSG"

# 2) Persistent log file with the last lines of the failed unit
LOGTAIL="$(journalctl -u "$UNIT" -n 25 --no-pager 2>/dev/null)"
{ echo "=== $MSG ==="; echo "$LOGTAIL"; echo; } >> "$LOGFILE" 2>/dev/null || true

# 3) Optional webhook (Slack/Discord/Teams/healthchecks/...)
if [ -n "${ALERT_WEBHOOK:-}" ]; then
  curl -fsS -m 15 -X POST -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MSG\"}" "$ALERT_WEBHOOK" >/dev/null 2>&1 \
    || logger -p daemon.err -t erpnext-backup "alert webhook POST failed"
fi

# 4) Optional email (needs a working MTA / mail command on the host)
if [ -n "${ALERT_EMAIL:-}" ] && command -v mail >/dev/null 2>&1; then
  printf '%s\n\n--- last 25 log lines ---\n%s\n' "$MSG" "$LOGTAIL" \
    | mail -s "[ALERT] ERPNext backup failed on $HOST" "$ALERT_EMAIL" \
    || logger -p daemon.err -t erpnext-backup "alert email send failed"
fi

exit 0
