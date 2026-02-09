#!/usr/bin/env bash
set -euo pipefail

# Update/reinstall scripts + systemd units from this repo checkout.

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo ./update.sh)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f /etc/nc-sync/config.env ]]; then
  echo "Missing /etc/nc-sync/config.env - run ./install.sh first" >&2
  exit 1
fi
# shellcheck disable=SC1091
source /etc/nc-sync/config.env

echo "==> Copying scripts"
install -m 0755 "$ROOT_DIR/scripts/tg_send" /usr/local/bin/tg_send
install -m 0755 "$ROOT_DIR/scripts/nc_check_space" /usr/local/bin/nc_check_space
install -m 0755 "$ROOT_DIR/scripts/nc_pull" /usr/local/bin/nc_pull
install -m 0755 "$ROOT_DIR/scripts/nc_fullscan" /usr/local/bin/nc_fullscan

# Regenerate timers from current config values
PULL_INTERVAL="${PULL_INTERVAL:-2h}"
PULL_RANDOM_DELAY="${PULL_RANDOM_DELAY:-5min}"
CLAMAV_ONCALENDAR="${CLAMAV_ONCALENDAR:-*-*-* 03:15:00}"
SPACECHECK_INTERVAL="${SPACECHECK_INTERVAL:-15min}"

install -m 0644 "$ROOT_DIR/systemd/nc-pull@.service" /etc/systemd/system/nc-pull@.service
cat >/etc/systemd/system/nc-pull@.timer <<EOT
[Unit]
Description=Run Nextcloud Pull for %i regularly

[Timer]
OnBootSec=5min
OnUnitActiveSec=${PULL_INTERVAL}
RandomizedDelaySec=${PULL_RANDOM_DELAY}
Persistent=true

[Install]
WantedBy=timers.target
EOT

install -m 0644 "$ROOT_DIR/systemd/nc-fullscan.service" /etc/systemd/system/nc-fullscan.service
cat >/etc/systemd/system/nc-fullscan.timer <<EOT
[Unit]
Description=Run daily ClamAV scan

[Timer]
OnCalendar=${CLAMAV_ONCALENDAR}
Persistent=true

[Install]
WantedBy=timers.target
EOT

install -m 0644 "$ROOT_DIR/systemd/nc-spacecheck.service" /etc/systemd/system/nc-spacecheck.service
cat >/etc/systemd/system/nc-spacecheck.timer <<EOT
[Unit]
Description=Run disk space check regularly

[Timer]
OnBootSec=2min
OnUnitActiveSec=${SPACECHECK_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOT

systemctl daemon-reload

# Restart timers
systemctl restart nc-fullscan.timer nc-spacecheck.timer || true

# Ensure per-instance timers enabled
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^# ]] && continue
  IFS='|' read -r inst _ _ _ <<<"$line"
  [[ -z "$inst" ]] && continue
  systemctl enable --now "nc-pull@${inst}.timer" || true
  systemctl restart "nc-pull@${inst}.timer" || true

done < <(printf "%s\n" "$SYNC_TARGETS")

/usr/local/bin/tg_send "♻️ nextcloud-nas-pull-sync updated." || true

echo "==> Update complete"
