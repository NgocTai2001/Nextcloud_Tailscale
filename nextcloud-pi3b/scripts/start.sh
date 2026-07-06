#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

get_lan_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

get_tailscale_ip() {
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | head -n 1
  fi
}

generate_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
  fi
}

replace_env_value() {
  local key="$1"
  local value="$2"
  sed -i "s|^${key}=.*|${key}=${value}|" .env
}

LAN_IP="$(get_lan_ip || true)"
TAILSCALE_IP="$(get_tailscale_ip || true)"

if [ ! -f .env ]; then
  echo "==> .env not found. Creating it from .env.example..."
  cp .env.example .env

  replace_env_value "MYSQL_ROOT_PASSWORD" "$(generate_secret)"
  replace_env_value "MYSQL_PASSWORD" "$(generate_secret)"
  replace_env_value "NEXTCLOUD_ADMIN_PASSWORD" "$(generate_secret)"

  TRUSTED_DOMAINS="localhost 127.0.0.1"
  if [ -n "$LAN_IP" ]; then
    TRUSTED_DOMAINS="$LAN_IP $TRUSTED_DOMAINS"
  fi
  if [ -n "$TAILSCALE_IP" ]; then
    TRUSTED_DOMAINS="$TRUSTED_DOMAINS $TAILSCALE_IP"
  fi
  replace_env_value "NEXTCLOUD_TRUSTED_DOMAINS" "$TRUSTED_DOMAINS"

  echo "==> Generated random passwords in .env."
  echo "==> Review .env now if you want to change the admin user, trusted domains, or timezone."
fi

if grep -Eq '=(change-me|change-me-|changeme)' .env; then
  echo "ERROR: .env still contains placeholder password values."
  echo "Please edit .env before starting Nextcloud."
  exit 1
fi

HTTP_PORT="$(grep -E '^NEXTCLOUD_HTTP_PORT=' .env | cut -d '=' -f 2- || true)"
HTTP_PORT="${HTTP_PORT:-8080}"

mkdir -p data/nextcloud/data data/nextcloud/config data/nextcloud/custom_apps data/nextcloud/themes data/db data/redis backups

echo "==> Starting Nextcloud stack..."
docker compose up -d

LAN_IP="$(get_lan_ip || true)"
TAILSCALE_IP="$(get_tailscale_ip || true)"

cat <<EOF

Nextcloud is starting. The first boot on Raspberry Pi 3B can take a few minutes.

Local LAN URL:
  http://${LAN_IP:-<IP-LAN>}:${HTTP_PORT}

Tailscale URL:
  http://${TAILSCALE_IP:-<TAILSCALE-IP>}:${HTTP_PORT}

Check containers:
  docker compose ps

View logs:
  docker compose logs -f nextcloud

EOF
