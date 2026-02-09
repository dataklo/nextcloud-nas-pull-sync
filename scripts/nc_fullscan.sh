#!/usr/bin/env bash
set -euo pipefail

SETTINGS="/etc/nc-sync/settings.conf"
MOUNT_PATH="/mnt/nas"
if [[ -f "$SETTINGS" ]]; then
  # shellcheck disable=SC1090
  source "$SETTINGS"
fi

SCANROOT="${MOUNT_PATH}/daten"
QBASE="${MOUNT_PATH}/quarantine"
DATE="$(date +%F)"
LOGDIR="/var/log/nc-sync"
mkdir -p "$LOGDIR" "${QBASE}/${DATE}"

OUT="${LOGDIR}/clamav-${DATE}.log"
INF="${LOGDIR}/clamav-${DATE}.infected.txt"

set +e
clamdscan --fdpass -r --infected --no-summary "$SCANROOT" > "$OUT"
RC=$?
set -e

if [[ $RC -eq 2 ]]; then
  /usr/local/bin/tg_send "❌ ClamAV Scan FEHLER (Exit 2)
$(tail -n 30 "$OUT")"
  exit 2
fi

grep -F " FOUND" "$OUT" | sed 's/: .* FOUND$//' > "$INF" || true

if [[ -s "$INF" ]]; then
  while IFS= read -r f; do
    rel="${f#${SCANROOT}/}"
    dest="${QBASE}/${DATE}/${rel}"
    mkdir -p "$(dirname "$dest")"
    [[ -f "$f" ]] && mv -f "$f" "$dest" || true
  done < "$INF"

  /usr/local/bin/tg_send "🦠 ClamAV: INFIZIERTE DATEIEN GEFUNDEN
Quarantäne: ${QBASE}/${DATE}
Beispiele:
$(tail -n 20 "$INF")"
fi

exit 0
