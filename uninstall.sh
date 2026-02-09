#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen (sudo)." >&2
  exit 1
fi

echo "== owncloud-nas-pull-sync Uninstall =="

ACCOUNTS="/etc/nc-sync/accounts.conf"

if [[ -f "$ACCOUNTS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue
    inst="${line%%|*}"
    systemctl disable --now "nc-pull@${inst}.timer" >/dev/null 2>&1 || true
  done <"$ACCOUNTS"
fi

systemctl disable --now nc-spacecheck.timer >/dev/null 2>&1 || true
systemctl disable --now nc-fullscan.timer >/dev/null 2>&1 || true

rm -f /etc/systemd/system/nc-pull@.service
rm -f /etc/systemd/system/nc-pull@.timer
rm -f /etc/systemd/system/nc-spacecheck.service
rm -f /etc/systemd/system/nc-spacecheck.timer
rm -f /etc/systemd/system/nc-fullscan.service
rm -f /etc/systemd/system/nc-fullscan.timer

systemctl daemon-reload

rm -f /usr/local/bin/tg_send
rm -f /usr/local/bin/nc_check_space
rm -f /usr/local/bin/nc_pull
rm -f /usr/local/bin/nc_fullscan

rm -f /etc/logrotate.d/nc-sync

echo
read -r -p "Configs unter /etc/nc-sync löschen? (y/N): " ans || true
if [[ "${ans:-}" =~ ^[Yy]$ ]]; then
  rm -rf /etc/nc-sync
  echo "Configs gelöscht."
else
  echo "Configs behalten."
fi

echo "Uninstall fertig."
