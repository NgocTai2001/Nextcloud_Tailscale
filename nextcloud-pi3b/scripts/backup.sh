#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_DIR/backups"
TMP_DIR="$(mktemp -d)"
BACKUP_FILE="$BACKUP_DIR/nextcloud-pi3b-${TIMESTAMP}.tar.gz"

if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi
BACKUP_OWNER="$(id -u):$(id -g)"

cleanup() {
  docker compose exec -T -u www-data nextcloud php occ maintenance:mode --off >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"

echo "==> Enabling Nextcloud maintenance mode..."
docker compose exec -T -u www-data nextcloud php occ maintenance:mode --on || true

echo "==> Dumping MariaDB database..."
docker compose exec -T mariadb sh -c 'mariadb-dump --single-transaction --quick --lock-tables=false -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' > "$TMP_DIR/db.sql"

cat > "$TMP_DIR/manifest.txt" <<EOF
created_at=${TIMESTAMP}
project=nextcloud-pi3b
contains=db.sql,nextcloud/data,nextcloud/config,nextcloud/custom_apps,nextcloud/themes
note=.env is not included; keep your .env file backed up separately.
EOF

echo "==> Creating compressed backup from database dump and data/nextcloud..."
$SUDO tar -czf "$BACKUP_FILE" \
  -C "$TMP_DIR" db.sql manifest.txt \
  -C "$PROJECT_DIR/data" nextcloud/data nextcloud/config nextcloud/custom_apps nextcloud/themes
if [ -n "$SUDO" ]; then
  $SUDO chown "$BACKUP_OWNER" "$BACKUP_FILE"
fi

echo "Backup created:"
echo "  $BACKUP_FILE"
