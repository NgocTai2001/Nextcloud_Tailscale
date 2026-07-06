#!/usr/bin/env bash
set -e

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Updating Raspberry Pi OS packages..."
$SUDO apt-get update
$SUDO apt-get upgrade -y

echo "==> Installing Docker prerequisites..."
$SUDO apt-get install -y ca-certificates curl gnupg

if command -v docker >/dev/null 2>&1; then
  echo "==> Docker is already installed."
else
  echo "==> Installing Docker Engine from the official Docker script..."
  curl -fsSL https://get.docker.com | $SUDO sh
fi

echo "==> Installing Docker Compose plugin..."
$SUDO apt-get update
$SUDO apt-get install -y docker-compose-plugin

CURRENT_USER="${SUDO_USER:-$USER}"
if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
  echo "==> Adding user '$CURRENT_USER' to the docker group..."
  $SUDO usermod -aG docker "$CURRENT_USER"
fi

echo "==> Docker version:"
docker --version || $SUDO docker --version

echo "==> Docker Compose version:"
docker compose version || $SUDO docker compose version

cat <<EOF

Docker installation finished.

Please reboot or log out and log back in so the docker group permission takes effect:

  sudo reboot

After reboot, run:

  cd "$(pwd)"
  ./scripts/start.sh

EOF
