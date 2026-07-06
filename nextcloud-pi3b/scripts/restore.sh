#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/nextcloud-pi3b-YYYYmmdd-HHMMSS.tar.gz"
  exit 1
fi

INPUT_BACKUP_FILE="$1"
if [ ! -f "$INPUT_BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $INPUT_BACKUP_FILE"
  exit 1
fi
BACKUP_FILE="$(cd "$(dirname "$INPUT_BACKUP_FILE")" && pwd)/$(basename "$INPUT_BACKUP_FILE")"

cd "$PROJECT_DIR"

cat <<EOF
WARNING: This restore will overwrite:

  $PROJECT_DIR/data/nextcloud
  MariaDB database configured in .env

Make sure you are restoring the correct backup file:

  $BACKUP_FILE

Type RESTORE to continue.
EOF

read -r CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
  echo "Restore cancelled."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "==> Extracting backup..."
tar -xzf "$BACKUP_FILE" -C "$TMP_DIR" db.sql manifest.txt 2>/dev/null || tar -xzf "$BACKUP_FILE" -C "$TMP_DIR" db.sql

if [ ! -f "$TMP_DIR/db.sql" ] || ! tar -tzf "$BACKUP_FILE" | grep -q '^nextcloud/'; then
  echo "ERROR: Backup archive is missing db.sql or nextcloud/."
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Stopping Nextcloud app container..."
docker compose stop nextcloud || true

echo "==> Starting database and Redis..."
docker compose up -d mariadb redis

echo "==> Waiting for MariaDB..."
for attempt in $(seq 1 30); do
  if docker compose exec -T mariadb sh -c 'mariadb-admin ping -h localhost -uroot -p"$MYSQL_ROOT_PASSWORD"' >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "ERROR: MariaDB did not become ready in time."
    exit 1
  fi
  sleep 5
done

echo "==> Replacing Nextcloud files..."
$SUDO rm -rf "$PROJECT_DIR/data/nextcloud"
$SUDO mkdir -p "$PROJECT_DIR/data"
$SUDO tar -xzf "$BACKUP_FILE" -C "$PROJECT_DIR/data" nextcloud
$SUDO chown -R 33:33 "$PROJECT_DIR/data/nextcloud"

echo "==> Recreating and importing MariaDB database..."
docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS \`$MYSQL_DATABASE\`; CREATE DATABASE \`$MYSQL_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci; GRANT ALL PRIVILEGES ON \`$MYSQL_DATABASE\`.* TO '\''$MYSQL_USER'\''@'\''%'\''; FLUSH PRIVILEGES;"'
docker compose exec -T mariadb sh -c 'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' < "$TMP_DIR/db.sql"

echo "==> Starting full stack..."
docker compose up -d

echo "==> Disabling maintenance mode and scanning files..."
docker compose exec -T -u www-data nextcloud php occ maintenance:mode --off || true
docker compose exec -T -u www-data nextcloud php occ files:scan --all || true

echo "Restore finished."
