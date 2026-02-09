#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo ./uninstall.sh)" >&2
  exit 1
fi

CONFIG="/etc/nc-sync/config.env"

echo "==> Stopping and disabling systemd timers"

# Disable per-instance pull timers (best-effort)
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1091
  source "$CONFIG"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue
    IFS='|' read -r inst _ _ _ <<<"$line"
    [[ -z "$inst" ]] && continue
    systemctl disable --now "nc-pull@${inst}.timer" 2>/dev/null || true
  done < <(printf "%s\n" "${SYNC_TARGETS:-}")
fi

systemctl disable --now nc-fullscan.timer 2>/dev/null || true
systemctl disable --now nc-spacecheck.timer 2>/dev/null || true

echo "==> Removing systemd unit files"
rm -f /etc/systemd/system/nc-pull@.service \
      /etc/systemd/system/nc-pull@.timer \
      /etc/systemd/system/nc-fullscan.service \
      /etc/systemd/system/nc-fullscan.timer \
      /etc/systemd/system/nc-spacecheck.service \
      /etc/systemd/system/nc-spacecheck.timer

systemctl daemon-reload

echo "==> Removing installed scripts"
rm -f /usr/local/bin/tg_send \
      /usr/local/bin/nc_check_space \
      /usr/local/bin/nc_pull \
      /usr/local/bin/nc_fullscan

echo "==> Removing logrotate rule"
rm -f /etc/logrotate.d/nc-sync

echo
read -rp "Remove /etc/nc-sync (config + telegram credentials)? [y/N]: " ANSW
ANSW="${ANSW:-N}"
if [[ "$ANSW" =~ ^[Yy]$ ]]; then
  rm -rf /etc/nc-sync
  echo "Removed /etc/nc-sync"
else
  echo "Keeping /etc/nc-sync"
fi

echo "==> Uninstall complete"
