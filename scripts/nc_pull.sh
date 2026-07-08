#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:-}"
CFG="/etc/nc-sync/accounts.conf"
SETTINGS="/etc/nc-sync/settings.conf"
TG_SEND="/usr/local/bin/tg_send"

# defaults
MIN_FREE_GIB=20
# rclone bisync interprets --max-delete as a percentage.
MAX_DELETE=50
RCLONE_TRANSFERS=4
RCLONE_CHECKERS=8
RCLONE_TIMEOUT=5m
RCLONE_CONTIMEOUT=15s

if [[ -f "$SETTINGS" ]]; then
  # shellcheck disable=SC1090
  source "$SETTINGS"
fi

if [[ -z "${INSTANCE}" ]]; then
  echo "Usage: nc_pull <instance>" >&2
  exit 2
fi
if [[ ! -f "$CFG" ]]; then
  echo "Missing $CFG" >&2
  exit 2
fi

line="$(grep -E "^${INSTANCE}\|" "$CFG" || true)"
if [[ -z "$line" ]]; then
  echo "Instance not found in $CFG: $INSTANCE" >&2
  exit 2
fi

REMOTE="$(echo "$line" | cut -d'|' -f2)"
DEST="$(echo "$line" | cut -d'|' -f3)"

mkdir -p /var/log/nc-sync /var/lib/nc-sync /var/lock "$DEST"

# Lock pro Instance
LOCK="/var/lock/nc-sync-${INSTANCE}.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  exit 0
fi

# Free Space Check
if ! /usr/local/bin/nc_check_space; then
  "$TG_SEND" "⛔ Bi-Sync abgebrochen (${INSTANCE}): zu wenig freier Speicher (Minimum ${MIN_FREE_GIB} GiB)."
  exit 75
fi

# Remote reachable?
set +e
rclone lsd "${REMOTE}:" --contimeout "$RCLONE_CONTIMEOUT" --timeout 2m >/dev/null 2>&1
RC_REMOTE=$?
set -e
if [[ $RC_REMOTE -ne 0 ]]; then
  "$TG_SEND" "❌ Remote nicht erreichbar (${INSTANCE})
Remote: ${REMOTE}:
Exit: ${RC_REMOTE}"
  exit 10
fi

TS="$(date -Is | tr ':' '-')"
LOG="/var/log/nc-sync/bisync-${INSTANCE}-${TS}.json"
ERR="/var/log/nc-sync/bisync-${INSTANCE}-${TS}.errors.tsv"
WORKDIR="/var/lib/nc-sync/bisync/${INSTANCE}"
mkdir -p "$WORKDIR"

BISYNC_INIT_FLAGS=()
if ! compgen -G "${WORKDIR}/*.lst" >/dev/null; then
  BISYNC_INIT_FLAGS=(--resync --resync-mode path1)
fi

set +e
rclone bisync "${REMOTE}:" "${DEST}" \
  "${BISYNC_INIT_FLAGS[@]}" \
  --fast-list --transfers "${RCLONE_TRANSFERS}" --checkers "${RCLONE_CHECKERS}" \
  --retries 3 --low-level-retries 20 --retries-sleep 30s \
  --contimeout "${RCLONE_CONTIMEOUT}" --timeout "${RCLONE_TIMEOUT}" \
  --workdir "${WORKDIR}" --resilient --recover --max-lock 5m \
  --max-delete "${MAX_DELETE}" \
  --conflict-resolve path1 --conflict-loser delete \
  --log-level INFO --use-json-log --log-file "${LOG}"
RC=$?
set -e

jq -r 'select(.level=="error") | [.time, (.object//"-"), .msg] | @tsv' "${LOG}" > "${ERR}" || true

if [[ -s "${ERR}" ]]; then
  "$TG_SEND" "❌ Bi-Sync-Fehler (${INSTANCE})
Remote: ${REMOTE}:
Zeit | Datei | Fehler:
$(tail -n 20 "${ERR}")"
fi

if [[ $RC -ne 0 ]]; then
  "$TG_SEND" "⚠️ Bi-Sync-Job Exitcode (${INSTANCE}): ${RC}
Log: ${LOG}"
fi

exit $RC
