# owncloud-nas-pull-sync

Automatischer **Bi-Sync** von **ownCloud oder Nextcloud** auf ein lokales NAS (NFS/SMB), inkl.:

- **rclone bisync (Cloud ↔ NAS)** mit **Deletes** (Löschungen werden in beide Richtungen synchronisiert)
- **Remote gewinnt bei Konflikten**: Bei Datei-Konflikten wird die Cloud-Version bevorzugt und die lokale Konfliktversion verworfen.
- **3+ Accounts** (beliebig viele) über eine Konfig-Datei
- **Telegram Alerts** (Sync-Fehler inkl. betroffener Datei, Remote nicht erreichbar, Low Disk Space)
- **Low Disk Space Alarm** (Default: < 20 GiB frei)
- **ClamAV** täglicher Vollscan + **Quarantäne** (infizierte Dateien werden verschoben)
- **systemd Timer** (statt Cron)
- **Logrotate** für Logs

> Ziel: Datenfluss **Cloud ↔ NAS**. Lokale Änderungen werden zurück in die Cloud synchronisiert.

## Voraussetzungen

- Ubuntu 24.04 minimal (VM oder Bare Metal)
- NAS ist unter **`/mnt/nas`** gemountet
  - Daten: **`/mnt/nas/daten`**
  - Quarantäne: **`/mnt/nas/quarantine`**
- ownCloud/Nextcloud Zugangsdaten (am besten **App-Passwort**)
- Telegram Bot Token + Chat ID

## WebDAV URLs (ownCloud / Nextcloud)

Für ownCloud ist häufig diese URL korrekt:

- `https://<HOST>/remote.php/webdav/`

Alternativ / je nach Setup funktioniert auch:

- `https://<HOST>/remote.php/dav/files/<USERNAME>/`

**Tipp zum Testen (ohne rclone):**

```bash
curl -u USER:PASS -X PROPFIND "https://<HOST>/remote.php/dav/files/<USER>/" -sS -i | head
```

## Installation

Klonen des Repositories und Starten des Installers:

```bash
git clone https://github.com/dataklo/nextcloud-nas-pull-sync.git
cd nextcloud-nas-pull-sync
chmod +x install.sh update.sh uninstall.sh
sudo ./install.sh
```

Falls du stattdessen ein ZIP-Archiv verwendest:

```bash
unzip nextcloud-nas-pull-sync.zip
cd nextcloud-nas-pull-sync
sudo ./install.sh
```

Der Installer fragt dich interaktiv nach:

- Telegram Token & Chat ID
- Mount-Pfad (Default: `/mnt/nas`)
- Low-Space Threshold (Default: 20 GiB)
- Accounts (Instance Name, rclone remote, Zielpfad)
- optional: rclone Remotes anlegen (WebDAV URL, Vendor owncloud/nextcloud, User, App-Passwort)

Danach laufen die Timer automatisch.

### Status prüfen

```bash
systemctl list-timers | grep nc-
systemctl status nc-pull@<instance>.timer
journalctl -u nc-pull@<instance>.service -n 100 --no-pager
```

## Konfiguration

### `/etc/nc-sync/accounts.conf`

Format:

```
INSTANZ|RCLONE_REMOTE|ZIELPFAD
```

Beispiel:

```
oc-sync-1|oc1|/mnt/nas/daten/oc-sync-1
oc-sync-2|oc2|/mnt/nas/daten/oc-sync-2
oc-sync-3|oc3|/mnt/nas/daten/oc-sync-3
```

### `/etc/nc-sync/telegram.env`

```
TG_TOKEN="123456:ABC..."
TG_CHAT_ID="7174123807"
```

### `/etc/nc-sync/settings.conf`

Hier kannst du Intervalle/Thresholds ändern:

- `MIN_FREE_GIB` (Default 20)
- `SYNC_INTERVAL` (Default `2h`)
- `SPACE_CHECK_INTERVAL` (Default `15min`)
- `SPACE_ALERT_COOLDOWN` (Default `6h`)
- `MAX_DELETE` (Default `50`, Prozentgrenze für rclone bisync)
- `RCLONE_TRANSFERS`, `RCLONE_CHECKERS`, `RCLONE_TIMEOUT`, `RCLONE_CONTIMEOUT`


## Fehlerbehebung

### `Bisync aborted. Must run --resync to recover.`

Wenn rclone meldet, dass frühere Path-Listings fehlen, startet `nc_pull` automatisch einen zusätzlichen Recovery-Lauf mit `--resync --resync-mode path1`. Dabei gilt die Cloud-Seite (`REMOTE:` / Path1) als maßgeblich; lokale Abweichungen werden entsprechend überschrieben bzw. abgeglichen.

Du solltest trotzdem prüfen, warum der vorherige Lauf kritisch abgebrochen ist, z. B. Stromausfall, volles Dateisystem, unterbrochener Mount oder Remote-Ausfall. Die Logs liegen unter `/var/log/nc-sync/bisync-<instanz>-<zeit>.json`; der Recovery-Lauf schreibt zusätzlich `...-resync.json`.
