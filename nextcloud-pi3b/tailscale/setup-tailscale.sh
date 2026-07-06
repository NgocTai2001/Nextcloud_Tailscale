#!/usr/bin/env bash
set -e

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "==> Starting Tailscale login..."
$SUDO tailscale up

TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"

cat <<EOF

Tailscale is ready.

Tailscale IPv4:
  ${TAILSCALE_IP:-<TAILSCALE-IP>}

Use this URL after Nextcloud is running:
  http://${TAILSCALE_IP:-<TAILSCALE-IP>}:8080

Add the Tailscale IP or MagicDNS name to NEXTCLOUD_TRUSTED_DOMAINS in .env before the first start.

If Nextcloud is already installed, add it with occ, for example:

  cd /path/to/nextcloud-pi3b
  docker compose exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="${TAILSCALE_IP:-100.x.y.z}"

For MagicDNS, use the full name shown by:

  tailscale status

EOF
