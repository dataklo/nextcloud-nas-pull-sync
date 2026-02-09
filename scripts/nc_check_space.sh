#!/usr/bin/env bash
set -euo pipefail

SETTINGS="/etc/nc-sync/settings.conf"
# defaults
MOUNT_PATH="/mnt/nas"
MIN_FREE_GIB=20
SPACE_ALERT_COOLDOWN="6h"

if [[ -f "$SETTINGS" ]]; then
  # shellcheck disable=SC1090
  source "$SETTINGS"
fi

CHECK_PATH="${MOUNT_PATH}"
MIN_FREE_BYTES=$((MIN_FREE_GIB * 1024 * 1024 * 1024))

# Parse cooldown like: 30s, 15min, 2h, 1d
cooldown_str="${SPACE_ALERT_COOLDOWN}"
cooldown_seconds=21600
if [[ "$cooldown_str" =~ ^([0-9]+)(s|sec|m|min|h|d)$ ]]; then
  n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"
  case "$u" in
    s|sec) cooldown_seconds=$n ;;
    m|min) cooldown_seconds=$((n*60)) ;;
    h) cooldown_seconds=$((n*3600)) ;;
    d) cooldown_seconds=$((n*86400)) ;;
  esac
fi

STATE_DIR="/var/lib/nc-sync"
STATE_FILE="${STATE_DIR}/space_alert.state"
mkdir -p "$STATE_DIR"

TG_SEND="/usr/local/bin/tg_send"

free_bytes="$(df -B1 --output=avail "$CHECK_PATH" | tail -n 1 | tr -d ' ')"
read -r _ _ _ use_pct mountpoint < <(df -B1 --output=size,used,avail,pcent,target "$CHECK_PATH" | tail -n 1)

now="$(date +%s)"
last=0
[[ -f "$STATE_FILE" ]] && last="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

if [[ "$free_bytes" -lt "$MIN_FREE_BYTES" ]]; then
  if [[ $((now - last)) -ge "$cooldown_seconds" ]]; then
    free_gib=$((free_bytes / 1024 / 1024 / 1024))
    "$TG_SEND" "⚠️ Speicherwarnung: < ${MIN_FREE_GIB} GiB frei
Pfad: ${CHECK_PATH} (Mount: ${mountpoint})
Frei: ${free_gib} GiB
Belegung: ${use_pct}"
    echo "$now" > "$STATE_FILE"
  fi
  exit 75
fi

exit 0
