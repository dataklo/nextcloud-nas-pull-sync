#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen (sudo)." >&2
  exit 1
fi

echo "== owncloud-nas-pull-sync Update =="

install -m 0755 ./scripts/tg_send.sh /usr/local/bin/tg_send
install -m 0755 ./scripts/nc_check_space.sh /usr/local/bin/nc_check_space
install -m 0755 ./scripts/nc_pull.sh /usr/local/bin/nc_pull
install -m 0755 ./scripts/nc_fullscan.sh /usr/local/bin/nc_fullscan

install -m 0644 ./systemd/nc-pull@.service /etc/systemd/system/nc-pull@.service
install -m 0644 ./systemd/nc-fullscan.service /etc/systemd/system/nc-fullscan.service
install -m 0644 ./systemd/nc-fullscan.timer /etc/systemd/system/nc-fullscan.timer
install -m 0644 ./systemd/nc-spacecheck.service /etc/systemd/system/nc-spacecheck.service
install -m 0644 ./systemd/logrotate-nc-sync /etc/logrotate.d/nc-sync

systemctl daemon-reload

echo "Update eingespielt."
echo "Hinweis: Intervalle/Timer werden in install.sh aus /etc/nc-sync/settings.conf neu geschrieben."
