#!/bin/bash

# Load environment variables
source .env 2>/dev/null || echo "Warning: .env file not found"

echo "=== Space-Efficient N8N Backup ==="
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p manual-backups

# Create compressed backup directly
echo "💾 Creating compressed database backup..."
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -U postgres -d n8n" | gzip > "manual-backups/n8n-${BACKUP_DATE}.sql.gz"

if [ -f "manual-backups/n8n-${BACKUP_DATE}.sql.gz" ]; then
    SIZE=$(du -sh "manual-backups/n8n-${BACKUP_DATE}.sql.gz" | cut -f1)
    echo "✅ Compressed backup created: ${SIZE}"
    echo "📁 Location: manual-backups/n8n-${BACKUP_DATE}.sql.gz"

    # Show quick stats
    echo "📊 To restore: gunzip manual-backups/n8n-${BACKUP_DATE}.sql.gz && docker exec -i \$(docker compose ps -q postgres) psql -U postgres -d n8n < manual-backups/n8n-${BACKUP_DATE}.sql"
else
    echo "❌ Backup failed!"
fi
