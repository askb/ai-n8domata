#!/bin/bash

# N8N Manual Backup Script
# Creates optimized backups with SQL dumps instead of raw PostgreSQL files

set -e

echo "=== N8N Manual Backup Started at $(date) ==="

# Configuration
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="./manual-backups"
TEMP_DIR="/tmp/n8n-backup-${BACKUP_DATE}"
FINAL_ARCHIVE="${BACKUP_DIR}/n8n-backup-${BACKUP_DATE}.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load environment variables safely
load_env() {
    if [ -f .env ]; then
        log_info "Loading environment variables from .env..."
        # Export variables, filtering out comments and empty lines
        set -a
        source <(grep -v '^#' .env | grep -v '^[[:space:]]*$' | sed 's/#.*$//')
        set +a
        log_info "Environment loaded successfully"
    else
        log_error ".env file not found!"
        exit 1
    fi
}

# Check if services are running
check_services() {
    log_info "Checking if services are running..."

    if ! docker compose ps | grep -q "postgres.*running"; then
        log_error "PostgreSQL is not running!"
        exit 1
    fi

    if ! docker compose ps | grep -q "n8n.*running"; then
        log_warn "N8N is not running - backup will continue"
    fi

    log_info "Services check completed"
}

# Create backup directories
create_directories() {
    log_info "Creating backup directories..."
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${TEMP_DIR}"
    log_info "Directories created: ${BACKUP_DIR}, ${TEMP_DIR}"
}

# Test database connection
test_database() {
    log_info "Testing database connection..."

    if docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT version();'" > /dev/null 2>&1; then
        log_info "Database connection successful"
    else
        log_error "Cannot connect to database!"
        exit 1
    fi
}

# Create database dump
create_database_dump() {
    log_info "Creating database dump..."

    DUMP_FILE="${TEMP_DIR}/database.sql"

    if docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -U ${POSTGRES_USER} -d ${POSTGRES_DB}" > "${DUMP_FILE}"; then
        DUMP_SIZE=$(du -sh "${DUMP_FILE}" | cut -f1)
        log_info "Database dump created successfully: ${DUMP_SIZE}"
    else
        log_error "Database dump failed!"
        exit 1
    fi
}

# Create database statistics
create_database_stats() {
    log_info "Gathering database statistics..."

    STATS_FILE="${TEMP_DIR}/database-stats.txt"

    cat > "${STATS_FILE}" << EOF
N8N Database Statistics
Backup Date: $(date)
Database: ${POSTGRES_DB}

EOF

    # Get counts of main entities
    docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(*) as workflows FROM workflow_entity;'" >> "${STATS_FILE}"
    docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(*) as credentials FROM credentials_entity;'" >> "${STATS_FILE}"
    docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(*) as executions FROM execution_entity;'" >> "${STATS_FILE}"
    docker exec $(docker compose ps -q postgres) bash -c "PGPASSWORD='${POSTGRES_PASSWORD}' psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT COUNT(*) as users FROM \"user\";'" >> "${STATS_FILE}"

    log_info "Database statistics saved"
}

# Copy N8N files
copy_n8n_files() {
    log_info "Copying N8N files..."

    # Copy N8N data directories if they exist
    for dir in n8n-workflows n8n-credentials n8n-data; do
        if [ -d "./backups/${dir}" ]; then
            cp -r "./backups/${dir}" "${TEMP_DIR}/"
            SIZE=$(du -sh "${TEMP_DIR}/${dir}" | cut -f1)
            log_info "Copied ${dir}: ${SIZE}"
        else
            log_warn "Directory ./backups/${dir} not found"
        fi
    done

    # Copy Redis data if it exists and is small
    if [ -f "./backups/redis/dump.rdb" ]; then
        REDIS_SIZE=$(stat -f%z "./backups/redis/dump.rdb" 2>/dev/null || stat -c%s "./backups/redis/dump.rdb" 2>/dev/null || echo "0")
        if [ "$REDIS_SIZE" -lt 10000000 ]; then  # Less than 10MB
            mkdir -p "${TEMP_DIR}/redis"
            cp "./backups/redis/dump.rdb" "${TEMP_DIR}/redis/"
            log_info "Copied Redis dump: $(du -sh ${TEMP_DIR}/redis/dump.rdb | cut -f1)"
        else
            log_warn "Redis dump too large ($(du -sh ./backups/redis/dump.rdb | cut -f1)), skipping"
        fi
    fi
}

# Create backup manifest
create_manifest() {
    log_info "Creating backup manifest..."

    MANIFEST_FILE="${TEMP_DIR}/backup-manifest.txt"

    cat > "${MANIFEST_FILE}" << EOF
N8N Backup Manifest
==================
Backup Date: $(date)
Backup ID: ${BACKUP_DATE}
Created By: Manual backup script
Database: ${POSTGRES_DB}

Contents:
EOF

    # List all files in backup
    find "${TEMP_DIR}" -type f -exec basename {} \; | sort >> "${MANIFEST_FILE}"

    echo "" >> "${MANIFEST_FILE}"
    echo "File Sizes:" >> "${MANIFEST_FILE}"
    du -sh "${TEMP_DIR}"/* >> "${MANIFEST_FILE}"

    log_info "Backup manifest created"
}

# Create final archive
create_archive() {
    log_info "Creating compressed archive..."

    if tar -czf "${FINAL_ARCHIVE}" -C "$(dirname ${TEMP_DIR})" "$(basename ${TEMP_DIR})"; then
        ARCHIVE_SIZE=$(du -sh "${FINAL_ARCHIVE}" | cut -f1)
        log_info "Archive created successfully: ${ARCHIVE_SIZE}"
        log_info "Archive location: ${FINAL_ARCHIVE}"
    else
        log_error "Archive creation failed!"
        exit 1
    fi
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    log_info "Cleanup completed"
}

# Verify backup
verify_backup() {
    log_info "Verifying backup archive..."

    if tar -tzf "${FINAL_ARCHIVE}" > /dev/null 2>&1; then
        log_info "Backup verification successful"

        echo ""
        echo "=== Backup Contents ==="
        tar -tzf "${FINAL_ARCHIVE}" | head -20

        if [ $(tar -tzf "${FINAL_ARCHIVE}" | wc -l) -gt 20 ]; then
            echo "... and $(( $(tar -tzf "${FINAL_ARCHIVE}" | wc -l) - 20 )) more files"
        fi
    else
        log_error "Backup verification failed!"
        exit 1
    fi
}

# Clean old backups
clean_old_backups() {
    log_info "Cleaning old backups (keeping last 7 days)..."

    if [ -d "${BACKUP_DIR}" ]; then
        find "${BACKUP_DIR}" -name "n8n-backup-*.tar.gz" -mtime +7 -delete 2>/dev/null || true
        REMAINING=$(find "${BACKUP_DIR}" -name "n8n-backup-*.tar.gz" | wc -l)
        log_info "Cleanup completed. ${REMAINING} backups remaining."
    fi
}

# Main execution
main() {
    load_env
    check_services
    create_directories
    test_database
    create_database_dump
    create_database_stats
    copy_n8n_files
    create_manifest
    create_archive
    cleanup
    verify_backup
    clean_old_backups

    echo ""
    echo "=== Backup Completed Successfully ==="
    echo "Archive: ${FINAL_ARCHIVE}"
    echo "Size: $(du -sh "${FINAL_ARCHIVE}" | cut -f1)"
    echo "Date: $(date)"
    echo ""
    echo "To restore this backup:"
    echo "1. Extract: tar -xzf ${FINAL_ARCHIVE}"
    echo "2. Restore database: docker exec -i \$(docker compose ps -q postgres) psql -U postgres -d n8n < database.sql"
    echo "3. Copy N8N files back to ./backups/"
}

# Error handling
trap 'log_error "Backup failed at line $LINENO. Cleaning up..."; cleanup; exit 1' ERR

# Run main function
main "$@"
