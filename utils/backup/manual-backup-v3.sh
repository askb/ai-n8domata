#!/bin/sh

echo "Installing required packages..."
apk add --no-cache tar gzip findutils coreutils postgresql-client

echo "Starting optimized backup service..."
echo "Waiting 60 seconds before first backup..."
sleep 60

while true; do
  echo "=== Starting backup at: $(date) ==="
  BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
  TEMP_DIR="/tmp/backup-${BACKUP_DATE}"
  FINAL_ARCHIVE="/backups/n8n-backup-${BACKUP_DATE}.tar.gz"

  # Create temp directory
  mkdir -p "${TEMP_DIR}"

  # Test database connection
  echo "Testing database connection..."
  export PGPASSWORD="${POSTGRES_PASSWORD}"
  if ! pg_isready -h postgres -U "${POSTGRES_USER}" -d "${POSTGRES_DB}"; then
    echo "Database not ready, retrying in 5 minutes..."
    rm -rf "${TEMP_DIR}"
    sleep 300
    continue
  fi

  # Create SQL dump (much smaller than raw files)
  echo "Creating SQL dump..."
  if pg_dump -h postgres -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -f "${TEMP_DIR}/database.sql"; then
    echo "SQL dump successful: $(du -sh ${TEMP_DIR}/database.sql | cut -f1)"

    # Create manifest file
    echo "Backup created: $(date)" > "${TEMP_DIR}/backup-info.txt"
    echo "Database: ${POSTGRES_DB}" >> "${TEMP_DIR}/backup-info.txt"
    echo "SQL dump size: $(du -sh ${TEMP_DIR}/database.sql | cut -f1)" >> "${TEMP_DIR}/backup-info.txt"

    # Count files being backed up
    N8N_WORKFLOWS=$(find /source/n8n-workflows -name "*.json" 2>/dev/null | wc -l || echo "0")
    N8N_CREDS=$(ls /source/n8n-credentials 2>/dev/null | wc -l || echo "0")
    echo "N8N Workflows: ${N8N_WORKFLOWS} files" >> "${TEMP_DIR}/backup-info.txt"
    echo "N8N Credentials: ${N8N_CREDS} files" >> "${TEMP_DIR}/backup-info.txt"

    # Create compressed archive with only essential files
    echo "Creating optimized archive..."
    tar -czf "${FINAL_ARCHIVE}" \
      -C /source n8n-workflows n8n-credentials n8n-data \
      -C "${TEMP_DIR}" database.sql backup-info.txt 2>/dev/null

    if [ $? -eq 0 ]; then
      ARCHIVE_SIZE=$(du -sh "${FINAL_ARCHIVE}" | cut -f1)
      echo "✅ Backup completed successfully: ${ARCHIVE_SIZE}"
      echo "Archive: ${FINAL_ARCHIVE}"
    else
      echo "❌ Archive creation failed"
    fi
  else
    echo "❌ SQL dump failed"
  fi

  # Cleanup temp files
  rm -rf "${TEMP_DIR}"

  # Clean old backups (keep last 7 days)
  echo "Cleaning old backups..."
  find /backups -name "n8n-backup-*.tar.gz" -mtime +7 -delete

  echo "Next backup in 24 hours"
  echo "=== Backup cycle finished ==="
  sleep 86400
done
