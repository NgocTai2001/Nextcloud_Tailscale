#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "==> Pulling latest container images..."
docker compose pull

echo "==> Recreating containers..."
docker compose up -d --remove-orphans

echo "==> Waiting for Nextcloud to respond to occ..."
for attempt in $(seq 1 30); do
  if docker compose exec -T -u www-data nextcloud php occ status >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "ERROR: Nextcloud did not become ready in time."
    exit 1
  fi
  sleep 10
done

echo "==> Running Nextcloud upgrade command..."
docker compose exec -T -u www-data nextcloud php occ upgrade
docker compose exec -T -u www-data nextcloud php occ maintenance:repair
docker compose exec -T -u www-data nextcloud php occ maintenance:mode --off

echo "Update finished."
