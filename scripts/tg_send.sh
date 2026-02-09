#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/nc-sync/telegram.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 2
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

msg="${1:-}"
if [[ -z "$msg" ]]; then
  echo "Usage: tg_send <message>" >&2
  exit 2
fi

curl -sS -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
  -d "chat_id=${TG_CHAT_ID}" \
  --data-urlencode "text=${msg}" \
  -d "disable_web_page_preview=true" >/dev/null
