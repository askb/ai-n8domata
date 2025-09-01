#!/bin/bash

# Simple N8N Backup Script
set -e

echo "=== N8N Simple Backup Started at $(date) ==="

# Configuration
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./manual-backups"
FINAL_ARCHIVE="${BACKUP_DIR}/n8n-backup-${BACKUP_DATE}.tar.gz"

# Load environment (safe method)
if [ -f .env ]; then
    set -a  # automatically export all variables
    source <(grep -v '^#' .env | grep -v '^[[:space:]]*

# Create backup directory
mkdir -p "${BACKUP_DIR}"
echo "✅ Created backup directory: ${BACKUP_DIR}"

# Check if postgres is running
if ! docker compose ps | grep -q "postgres.*running"; then
    echo "❌ PostgreSQL is not running! Starting services..."
    docker compose up -d
    echo "⏳ Waiting for services to start..."
    sleep 20
fi

# Test database connection
echo "🔍 Testing database connection..."
if ! docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT 1;'" > /dev/null 2>&1; then
    echo "❌ Cannot connect to database!"
    exit 1
fi
echo "✅ Database connection successful"

# Create database dump
echo "💾 Creating database dump..."
DB_DUMP="${BACKUP_DIR}/database-${BACKUP_DATE}.sql"
if docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB}" > "${DB_DUMP}"; then
    DB_SIZE=$(du -sh "${DB_DUMP}" | cut -f1)
    echo "✅ Database dump created: ${DB_SIZE}"
else
    echo "❌ Database dump failed!"
    exit 1
fi

# Get database stats
echo "📊 Getting database statistics..."
STATS_FILE="${BACKUP_DIR}/stats-${BACKUP_DATE}.txt"
echo "N8N Database Statistics - $(date)" > "${STATS_FILE}"
echo "======================================" >> "${STATS_FILE}"

docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as workflows FROM workflow_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as credentials FROM credentials_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as executions FROM execution_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as users FROM \"user\";'" >> "${STATS_FILE}"

echo "✅ Statistics saved"

# Create archive with database dump + n8n files + stats
echo "📦 Creating backup archive..."
tar -czf "${FINAL_ARCHIVE}" \
  -C "${BACKUP_DIR}" "$(basename ${DB_DUMP})" "$(basename ${STATS_FILE})" \
  -C . backups/n8n-data backups/n8n-workflows backups/n8n-credentials 2>/dev/null || \
tar -czf "${FINAL_ARCHIVE}" \
  -C "${BACKUP_DIR}" "$(basename ${DB_DUMP})" "$(basename ${STATS_FILE})" 2>/dev/null

if [ -f "${FINAL_ARCHIVE}" ]; then
    ARCHIVE_SIZE=$(du -sh "${FINAL_ARCHIVE}" | cut -f1)
    echo "✅ Archive created: ${ARCHIVE_SIZE}"
    echo "📁 Location: ${FINAL_ARCHIVE}"
else
    echo "❌ Archive creation failed!"
    exit 1
fi

# Cleanup individual files
rm -f "${DB_DUMP}" "${STATS_FILE}"

# Clean old backups (keep last 5)
echo "🧹 Cleaning old backups..."
find "${BACKUP_DIR}" -name "n8n-backup-*.tar.gz" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true

echo ""
echo "=== Backup Completed Successfully ==="
echo "📦 Archive: ${FINAL_ARCHIVE}"
echo "📏 Size: $(du -sh "${FINAL_ARCHIVE}" | cut -f1)"
echo "📅 Date: $(date)"
echo ""
echo "To restore:"
echo "1. tar -xzf ${FINAL_ARCHIVE}"
echo "2. docker exec -i \$(docker compose ps -q postgres) psql -U postgres -d n8n < database-${BACKUP_DATE}.sql" | sed 's/#.*$//' | grep '=')
    set +a  # disable automatic export
    echo "✅ Environment loaded"
else
    echo "❌ .env file not found!"
    exit 1
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"
echo "✅ Created backup directory: ${BACKUP_DIR}"

# Check if postgres is running
if ! docker compose ps | grep -q "postgres.*running"; then
    echo "❌ PostgreSQL is not running! Starting services..."
    docker compose up -d
    echo "⏳ Waiting for services to start..."
    sleep 20
fi

# Test database connection
echo "🔍 Testing database connection..."
if ! docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT 1;'" > /dev/null 2>&1; then
    echo "❌ Cannot connect to database!"
    exit 1
fi
echo "✅ Database connection successful"

# Create database dump
echo "💾 Creating database dump..."
DB_DUMP="${BACKUP_DIR}/database-${BACKUP_DATE}.sql"
if docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB}" > "${DB_DUMP}"; then
    DB_SIZE=$(du -sh "${DB_DUMP}" | cut -f1)
    echo "✅ Database dump created: ${DB_SIZE}"
else
    echo "❌ Database dump failed!"
    exit 1
fi

# Get database stats
echo "📊 Getting database statistics..."
STATS_FILE="${BACKUP_DIR}/stats-${BACKUP_DATE}.txt"
echo "N8N Database Statistics - $(date)" > "${STATS_FILE}"
echo "======================================" >> "${STATS_FILE}"

docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as workflows FROM workflow_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as credentials FROM credentials_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as executions FROM execution_entity;'" >> "${STATS_FILE}"
docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(\*) as users FROM \"user\";'" >> "${STATS_FILE}"

echo "✅ Statistics saved"

# Create archive with database dump + n8n files + stats
echo "📦 Creating backup archive..."
tar -czf "${FINAL_ARCHIVE}" \
  -C "${BACKUP_DIR}" "$(basename ${DB_DUMP})" "$(basename ${STATS_FILE})" \
  -C . backups/n8n-data backups/n8n-workflows backups/n8n-credentials 2>/dev/null || \
tar -czf "${FINAL_ARCHIVE}" \
  -C "${BACKUP_DIR}" "$(basename ${DB_DUMP})" "$(basename ${STATS_FILE})" 2>/dev/null

if [ -f "${FINAL_ARCHIVE}" ]; then
    ARCHIVE_SIZE=$(du -sh "${FINAL_ARCHIVE}" | cut -f1)
    echo "✅ Archive created: ${ARCHIVE_SIZE}"
    echo "📁 Location: ${FINAL_ARCHIVE}"
else
    echo "❌ Archive creation failed!"
    exit 1
fi

# Cleanup individual files
rm -f "${DB_DUMP}" "${STATS_FILE}"

# Clean old backups (keep last 5)
echo "🧹 Cleaning old backups..."
find "${BACKUP_DIR}" -name "n8n-backup-*.tar.gz" -type f | sort | head -n -5 | xargs rm -f 2>/dev/null || true

echo ""
echo "=== Backup Completed Successfully ==="
echo "📦 Archive: ${FINAL_ARCHIVE}"
echo "📏 Size: $(du -sh "${FINAL_ARCHIVE}" | cut -f1)"
echo "📅 Date: $(date)"
echo ""
echo "To restore:"
echo "1. tar -xzf ${FINAL_ARCHIVE}"
echo "2. docker exec -i \$(docker compose ps -q postgres) psql -U postgres -d n8n < database-${BACKUP_DATE}.sql"
