#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen (sudo)." >&2
  exit 1
fi

echo "== owncloud-nas-pull-sync Installer =="

apt update
apt install -y rclone jq curl util-linux logrotate clamav clamav-daemon

systemctl enable --now clamav-freshclam clamav-daemon >/dev/null 2>&1 || true

mkdir -p /etc/nc-sync /var/log/nc-sync /var/lib/nc-sync /var/lock

SETTINGS="/etc/nc-sync/settings.conf"
if [[ ! -f "$SETTINGS" ]]; then
  cp -n "./config/settings.conf.example" "$SETTINGS"
fi

# shellcheck disable=SC1090
source "$SETTINGS" || true
: "${MOUNT_PATH:=/mnt/nas}"
: "${MIN_FREE_GIB:=20}"
: "${SYNC_INTERVAL:=2h}"
: "${SPACE_CHECK_INTERVAL:=15min}"
: "${SPACE_ALERT_COOLDOWN:=6h}"
: "${MAX_DELETE:=50}"
: "${RCLONE_TRANSFERS:=4}"
: "${RCLONE_CHECKERS:=8}"
: "${RCLONE_TIMEOUT:=5m}"
: "${RCLONE_CONTIMEOUT:=15s}"

echo
read -r -p "NAS Mount Pfad? [${MOUNT_PATH}]: " inp || true
if [[ -n "${inp:-}" ]]; then MOUNT_PATH="$inp"; fi

read -r -p "Minimum Free Space in GiB? [${MIN_FREE_GIB}]: " inp || true
if [[ -n "${inp:-}" ]]; then MIN_FREE_GIB="$inp"; fi

read -r -p "Sync Intervall (systemd timespan, z.B. 30min, 1h, 2h)? [${SYNC_INTERVAL}]: " inp || true
if [[ -n "${inp:-}" ]]; then SYNC_INTERVAL="$inp"; fi

read -r -p "Space-Check Intervall? [${SPACE_CHECK_INTERVAL}]: " inp || true
if [[ -n "${inp:-}" ]]; then SPACE_CHECK_INTERVAL="$inp"; fi

read -r -p "Space-Alert Cooldown (z.B. 6h, 1h)? [${SPACE_ALERT_COOLDOWN}]: " inp || true
if [[ -n "${inp:-}" ]]; then SPACE_ALERT_COOLDOWN="$inp"; fi

read -r -p "Max Delete Prozent pro Bi-Sync (Schutz) ? [${MAX_DELETE}]: " inp || true
if [[ -n "${inp:-}" ]]; then MAX_DELETE="$inp"; fi

cat >"$SETTINGS" <<EOF
MOUNT_PATH=${MOUNT_PATH}
MIN_FREE_GIB=${MIN_FREE_GIB}
SYNC_INTERVAL=${SYNC_INTERVAL}
SPACE_CHECK_INTERVAL=${SPACE_CHECK_INTERVAL}
SPACE_ALERT_COOLDOWN=${SPACE_ALERT_COOLDOWN}
MAX_DELETE=${MAX_DELETE}
RCLONE_TRANSFERS=${RCLONE_TRANSFERS}
RCLONE_CHECKERS=${RCLONE_CHECKERS}
RCLONE_TIMEOUT=${RCLONE_TIMEOUT}
RCLONE_CONTIMEOUT=${RCLONE_CONTIMEOUT}
EOF
chmod 600 "$SETTINGS"

mkdir -p "${MOUNT_PATH}/daten" "${MOUNT_PATH}/quarantine"

TG_ENV="/etc/nc-sync/telegram.env"
if [[ ! -f "$TG_ENV" ]]; then
  echo
  echo "Telegram Setup:"
  read -r -p "Bot Token (TG_TOKEN): " tg_token
  read -r -p "Chat ID (TG_CHAT_ID): " tg_chat

  cat >"$TG_ENV" <<EOF
TG_TOKEN="${tg_token}"
TG_CHAT_ID="${tg_chat}"
EOF
  chmod 600 "$TG_ENV"
fi

install -m 0755 ./scripts/tg_send.sh /usr/local/bin/tg_send
install -m 0755 ./scripts/nc_check_space.sh /usr/local/bin/nc_check_space
install -m 0755 ./scripts/nc_pull.sh /usr/local/bin/nc_pull
install -m 0755 ./scripts/nc_fullscan.sh /usr/local/bin/nc_fullscan

ACCOUNTS="/etc/nc-sync/accounts.conf"
if [[ ! -f "$ACCOUNTS" ]]; then
  cp -n ./config/accounts.conf.example "$ACCOUNTS"
  echo
  echo "Accounts Datei erstellt: $ACCOUNTS"
  echo "Bitte anpassen (INSTANZ|REMOTE|ZIELPFAD)."
fi
chmod 600 "$ACCOUNTS"

echo
read -r -p "Möchtest du rclone Remotes jetzt anlegen? (y/N): " ans || true
if [[ "${ans:-}" =~ ^[Yy]$ ]]; then
  echo "Remotes anlegen (WebDAV). Tipp: ownCloud meistens https://host/remote.php/webdav/"
  while true; do
    read -r -p "Remote Name (z.B. oc1) [leer zum Beenden]: " rname || true
    [[ -z "${rname:-}" ]] && break
    read -r -p "Vendor (owncloud|nextcloud|other) [owncloud]: " vendor || true
    vendor="${vendor:-owncloud}"
    read -r -p "WebDAV URL: " url
    read -r -p "Username: " user
    read -s -p "App-Passwort: " pass; echo
    obs="$(rclone obscure "$pass")"
    unset pass
    rclone config create "$rname" webdav url "$url" vendor "$vendor" user "$user" pass "$obs"
    unset obs
    echo "Remote '$rname' angelegt."
  done
fi

install -m 0644 ./systemd/nc-pull@.service /etc/systemd/system/nc-pull@.service

cat >/etc/systemd/system/nc-pull@.timer <<EOF
[Unit]
Description=Run Cloud Bi-Sync for %i regularly

[Timer]
OnBootSec=5min
OnUnitActiveSec=${SYNC_INTERVAL}
RandomizedDelaySec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

install -m 0644 ./systemd/nc-fullscan.service /etc/systemd/system/nc-fullscan.service
install -m 0644 ./systemd/nc-fullscan.timer /etc/systemd/system/nc-fullscan.timer

install -m 0644 ./systemd/nc-spacecheck.service /etc/systemd/system/nc-spacecheck.service
cat >/etc/systemd/system/nc-spacecheck.timer <<EOF
[Unit]
Description=Run disk space check regularly

[Timer]
OnBootSec=2min
OnUnitActiveSec=${SPACE_CHECK_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

install -m 0644 ./systemd/logrotate-nc-sync /etc/logrotate.d/nc-sync

systemctl daemon-reload

systemctl enable --now nc-spacecheck.timer
systemctl enable --now nc-fullscan.timer

echo
echo "Aktiviere Bi-Sync-Timer für Instanzen aus $ACCOUNTS ..."
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^# ]] && continue
  inst="${line%%|*}"
  systemctl enable --now "nc-pull@${inst}.timer"
done <"$ACCOUNTS"

# Test telegram
/usr/local/bin/tg_send "✅ owncloud-nas-pull-sync installiert. Mount: ${MOUNT_PATH}"

echo
echo "Fertig."
echo "Timer anzeigen: systemctl list-timers | grep nc-"
