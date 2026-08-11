#!/bin/bash
# Shared alert dispatcher for the ERPNext production host.
#
# Every alerting source on this host (backup failure, disk watch, ...) goes
# through here, so there is exactly one place that knows *where* alerts land.
#
# Usage:
#   scripts/notify.sh <severity> <subject> [body ...]
#     severity: info | warn | crit   (controls the prefix only)
#
# Channels are configured in .configs/alerts.env (git-ignored, NOT synced by
# `deploy sync` -- it holds secrets). See alerts.env.example.
#   ALERT_TELEGRAM_TOKEN     bot token from @BotFather
#   ALERT_TELEGRAM_CHAT_ID   target chat / group / channel id
#   ALERT_WEBHOOK            optional generic webhook, receives {"text": "..."}
#
# Design rule: this script NEVER fails its caller. A broken alert channel must
# not take down the job it is watching, and must not mask that job's own exit
# code. Every error is logged to the journal and swallowed; exit is always 0.
#
# It is also deliberately dependency-free (no jq, no python) -- the whole point
# is that it still works when the host is in a bad state.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."

# alerts.env is the canonical location; backup.env is also sourced so the older
# ALERT_WEBHOOK setting there keeps working without a migration step.
[ -f "$ROOT_DIR/.configs/alerts.env" ] && source "$ROOT_DIR/.configs/alerts.env"
[ -f "$ROOT_DIR/.configs/backup.env" ] && source "$ROOT_DIR/.configs/backup.env"

SEVERITY="${1:-info}"
shift || true
SUBJECT="${1:-(no subject)}"
shift || true
BODY="$*"

HOST="$(hostname)"
WHEN="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

case "$SEVERITY" in
  crit) MARK="🔴 CRIT" ;;
  warn) MARK="🟠 WARN" ;;
  *)    MARK="🔵 INFO" ;;
esac

TEXT="$MARK  $SUBJECT
host: $HOST
time: $WHEN"
[ -n "$BODY" ] && TEXT="$TEXT

$BODY"

# Telegram caps messages at 4096 chars; leave room for the header.
if [ "${#TEXT}" -gt 3900 ]; then
  TEXT="${TEXT:0:3900}
[... truncated]"
fi

# Escape a string for use inside a JSON string literal. Handles the cases that
# actually occur in log tails: backslash, quote, newline, CR, tab.
json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\r'/}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

ESCAPED="$(json_escape "$TEXT")"
SENT=0

# --- Telegram ---
if [ -n "${ALERT_TELEGRAM_TOKEN:-}" ] && [ -n "${ALERT_TELEGRAM_CHAT_ID:-}" ]; then
  # No parse_mode on purpose: plain text cannot break on unescaped markdown
  # characters appearing in a log tail.
  if curl -fsS -m 15 -o /dev/null \
      -X POST "https://api.telegram.org/bot${ALERT_TELEGRAM_TOKEN}/sendMessage" \
      -H 'Content-Type: application/json' \
      -d "{\"chat_id\":\"${ALERT_TELEGRAM_CHAT_ID}\",\"disable_web_page_preview\":true,\"text\":\"${ESCAPED}\"}" \
      2>/dev/null; then
    SENT=1
  else
    logger -p daemon.err -t erpnext-notify "telegram send failed for: $SUBJECT"
  fi
fi

# --- Generic webhook (Slack/Discord/Teams/ntfy/...) ---
if [ -n "${ALERT_WEBHOOK:-}" ]; then
  if curl -fsS -m 15 -o /dev/null -X POST "$ALERT_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"${ESCAPED}\"}" 2>/dev/null; then
    SENT=1
  else
    logger -p daemon.err -t erpnext-notify "webhook POST failed for: $SUBJECT"
  fi
fi

# --- Always: journal, so an alert is never lost even with no channel configured ---
if [ "$SENT" = "1" ]; then
  logger -p daemon.notice -t erpnext-notify "[$SEVERITY] $SUBJECT"
else
  logger -p daemon.err -t erpnext-notify \
    "[$SEVERITY] $SUBJECT -- NO CHANNEL DELIVERED (check .configs/alerts.env)"
fi

exit 0
