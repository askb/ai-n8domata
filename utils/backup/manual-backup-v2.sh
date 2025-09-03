#!/bin/bash

# Manual N8N Backup Script
# Usage: ./backup.sh

set -e

echo "=== N8N Manual Backup Started at $(date) ==="

# Configuration
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./manual-backups"
ARCHIVE_FILE="$BACKUP_DIR/n8n-manual-backup-$BACKUP_DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Load environment variables
if [ -f .env ]; then
    # Better way to load env file, avoiding comments and empty lines
    set -a  # automatically export all variables
    source <(grep -v '^#' .env | grep -v '^[[:space:]]*$')
    set +a  # disable automatic export
fi

echo "Creating database dump..."
# Create temporary dump
TEMP_DUMP="/tmp/n8n-dump-$BACKUP_DATE.sql"
docker exec $(docker-compose ps -q postgres) pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$TEMP_DUMP"

echo "Creating archive..."
# Create archive with all data
tar -czf "$ARCHIVE_FILE" \
    -C ./backups n8n-credentials n8n-workflows n8n-data \
    -C /tmp "n8n-dump-$BACKUP_DATE.sql"

# Cleanup temp file
rm "$TEMP_DUMP"

echo "Backup created: $ARCHIVE_FILE"
echo "Archive size: $(du -h "$ARCHIVE_FILE" | cut -f1)"

# List contents
echo "Archive contents:"
tar -tzf "$ARCHIVE_FILE"

echo "=== Backup Completed Successfully ==="
