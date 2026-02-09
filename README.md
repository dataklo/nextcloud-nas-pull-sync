# nextcloud-nas-pull-sync

Pull-Synchronisation (Cloud ➜ NAS) für Nextcloud per **rclone (WebDAV)** mit:

- **3 Benutzer-Accounts** (konfigurierbar)
- **Mirror-Verhalten**: Löschungen in der Cloud werden **lokal ebenfalls gelöscht** (`rclone sync`)
- Ziel auf NAS: **Klartext-Dateien** (sofern keine Nextcloud **E2EE**-Ordner verwendet werden)
- **ClamAV Daily Fullscan** + **Quarantäne**
- **Telegram Alerts** bei:
  - rclone Fehlern (inkl. Dateipfad soweit verfügbar)
  - Virenfunden (inkl. Dateipfade + Quarantäne-Pfad)
  - zu wenig freiem Speicher (Standard: **< 20 GiB**) 
- **systemd Timer** für regelmäßige Jobs

> Getestet/ausgelegt für **Ubuntu 24.04 minimal** in einer VM.

---

## Architektur

```
Nextcloud (WebDAV)  ->  Ubuntu VM (rclone + ClamAV)  ->  Synology NAS (NFS-Mount)
```

- Datenfluss ist **Pull**: Cloud ➜ NAS.
- Lokales NAS ist „Source of Truth“ für nachgelagerte Backups (z.B. Borg in separater VM).

---

## Voraussetzungen

1. **Synology DSM**
   - NFS aktivieren (NFSv4.1 empfohlen)
   - Shared Folder (z.B. `nc-sync`) exportieren
   - NFS-Berechtigung: IP deiner **Ubuntu-VM** erlauben (oder dein /24)
   - RW erlauben

2. **Nextcloud**
   - Pro User ein **App-Passwort** erstellen (Einstellungen → Sicherheit → App-Passwörter)
   - **Keine E2EE-Ordner** für die Daten, wenn du Klartext auf dem NAS willst.

3. **Telegram**
   - Bot via @BotFather erstellen
   - `TG_TOKEN` + `TG_CHAT_ID` ermitteln (Privatchat oder Gruppe)

---

## Repository Inhalt

- `install.sh`  – installiert Pakete, richtet NFS-Mount, rclone Remotes, systemd Units/Timer, ClamAV, Logrotate ein
- `update.sh`   – aktualisiert installierte Dateien/Units aus dem Repo-Stand
- `uninstall.sh` – deaktiviert Timer/Units und entfernt Dateien (optional inkl. Config)
- `scripts/*` und `systemd/*` – die installierten Komponenten

---

## Quickstart

### 1) Repo klonen
```bash
git clone https://github.com/dataklo/nextcloud-nas-pull-sync.git
cd nextcloud-nas-pull-sync
```

### 2) Installieren (als root / mit sudo)
```bash
sudo bash install.sh
```

Das Setup fragt interaktiv nach:
- NAS-IP (z.B. `192.168.1.61`)
- NFS Export Path (z.B. `/volume1/nc-sync`)
- Mountpoint (Standard: `/mnt/nas`)
- Telegram Bot Token + Chat-ID
- Nextcloud Base URL (Standard: `https://cloud.dataklo.de`)
- Nextcloud Usernames + lokale Zielordner
- App-Passwörter (werden per `rclone obscure` gespeichert)

### 3) Status prüfen
```bash
systemctl list-timers | grep nc-

# Beispiel: letzten Lauf ansehen
journalctl -u nc-pull@tj-doeren.service -n 100 --no-pager
```

### 4) Manuell einen Pull starten
```bash
sudo systemctl start nc-pull@tj-doeren.service
```

---

## Standard-Timer

- Pull pro User: alle **2 Stunden** (+ Random Delay)
- Disk Space Check: alle **15 Minuten**
- ClamAV Fullscan: täglich um **03:15**

Timer können in `/etc/systemd/system/*.timer` angepasst werden.

---

## Konfiguration

Nach Installation liegen Konfigurationen hier:

- `/etc/nc-sync/config.env`  – allgemeine Settings (Mountpoints, Limits, Targets)
- `/etc/nc-sync/telegram.env` – Telegram Zugangsdaten

Logs:
- `/var/log/nc-sync/` (rclone JSON Logs, Error-Extrakte, ClamAV Logs)

Quarantäne:
- `${QUAR_DIR}/YYYY-MM-DD/<relativer_pfad>`

---

## Sicherheitshinweise

- Das Setup nutzt `rclone sync` (Mirror). Mit `--max-delete` wird Mass-Delete begrenzt.
- Bei zu wenig freiem Speicher (< `MIN_FREE_GIB`) wird der Pull **abgebrochen** und Telegram informiert.
- App-Passwörter werden in rclone **obfuscated** gespeichert (nicht Klartext, aber auch kein starker Kryptoschutz).

---

## Update
```bash
cd nextcloud-nas-pull-sync
sudo bash update.sh
```

---

## Uninstall
```bash
cd nextcloud-nas-pull-sync
sudo bash uninstall.sh
```

---

## Lizenz
MIT – siehe `LICENSE`.
