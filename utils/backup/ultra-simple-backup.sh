#!/bin/bash

# Load environment variables
# shellcheck source=/dev/null
source .env 2>/dev/null || echo "Warning: .env file not found"

echo "=== N8N Ultra-Simple Backup Started at $(date) ==="

# Configuration (hardcoded)
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./manual-backups"
DB_PASSWORD="${POSTGRES_PASSWORD}"  # From .env file

# Create backup directory
mkdir -p "${BACKUP_DIR}"
echo "✅ Created backup directory: ${BACKUP_DIR}"

# Start services if needed
echo "🚀 Starting services..."
#docker compose -f docker-compose.yml --env-file .env up -d
#sleep 15

# Check postgres
#if docker compose ps | grep -q "postgres.*running"; then
#    echo "✅ PostgreSQL is running"
#else
#    echo "❌ PostgreSQL not running!"
#    exit 1
#fi

# Create database dump
echo "💾 Creating database dump..."
DB_DUMP="${BACKUP_DIR}/n8n-backup-${BACKUP_DATE}.sql"

if docker exec "$(docker compose ps -q postgres)" bash -c "PGPASSWORD='${DB_PASSWORD}' pg_dump -U postgres -d n8n" > "${DB_DUMP}"; then
    DB_SIZE=$(du -sh "${DB_DUMP}" | cut -f1)
    echo "✅ Database dump created: ${DB_SIZE}"
    echo "📁 Location: ${DB_DUMP}"
else
    echo "❌ Database dump failed!"
    exit 1
fi

# Get quick stats
echo "📊 Database contains:"
docker exec "$(docker compose ps -q postgres)" bash -c "PGPASSWORD='${DB_PASSWORD}' psql -U postgres -d n8n -t -c 'SELECT COUNT(*) FROM workflow_entity;'" | xargs echo "Workflows:"
docker exec "$(docker compose ps -q postgres)" bash -c "PGPASSWORD='${DB_PASSWORD}' psql -U postgres -d n8n -t -c 'SELECT COUNT(*) FROM credentials_entity;'" | xargs echo "Credentials:"

echo ""
echo "=== Backup Completed Successfully ==="
echo "📦 File: ${DB_DUMP}"
echo "📏 Size: $(du -sh "${DB_DUMP}" | cut -f1)"
echo ""
echo "To restore: docker exec -i \$(docker compose ps -q postgres) psql -U postgres -d n8n < ${DB_DUMP}"
