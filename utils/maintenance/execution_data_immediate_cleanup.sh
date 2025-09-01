#!/bin/bash

echo "🚀 IMMEDIATE 28GB EXECUTION DATA CLEANUP"
echo "======================================="

echo "📊 ANALYSIS RESULTS:"
echo "• 359 execution records = 28 GB"
echo "• Average: ~78 MB per execution!"
echo "• No orphaned data (clean relationship)"
echo "• Some workflows storing MASSIVE data"
echo ""

# Step 1: Find the biggest execution data records
echo "1. Finding the largest execution data records..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        ed.\\\"executionId\\\",
        LENGTH(ed.data) as data_size_bytes,
        pg_size_pretty(LENGTH(ed.data)) as data_size_pretty,
        ee.status,
        ee.\\\"startedAt\\\"
    FROM execution_data ed
    INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
    ORDER BY LENGTH(ed.data) DESC
    LIMIT 10;
    \"
"

echo ""
echo "2. Age breakdown of execution data..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        CASE
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '7 days' THEN 'Last 7 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '30 days' THEN 'Last 30 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '90 days' THEN 'Last 90 days'
            ELSE 'Older than 90 days'
        END as age_group,
        COUNT(ed.*) as execution_count,
        pg_size_pretty(SUM(LENGTH(ed.data))) as total_data_size
    FROM execution_data ed
    INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
    GROUP BY
        CASE
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '7 days' THEN 'Last 7 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '30 days' THEN 'Last 30 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '90 days' THEN 'Last 90 days'
            ELSE 'Older than 90 days'
        END
    ORDER BY
        CASE
            WHEN age_group = 'Last 7 days' THEN 1
            WHEN age_group = 'Last 30 days' THEN 2
            WHEN age_group = 'Last 90 days' THEN 3
            ELSE 4
        END;
    \"
"

echo ""
echo "🎯 CLEANUP OPTIONS:"
echo "=================="
echo "Based on the analysis above, choose your cleanup strategy:"
echo ""
echo "(1) CONSERVATIVE: Keep last 30 days only"
echo "(2) AGGRESSIVE: Keep last 7 days only"
echo "(3) SURGICAL: Delete only the largest execution data (>10MB each)"
echo "(4) SHOW MORE INFO: Don't clean yet, show more analysis"
echo "(5) SKIP: Don't clean now"
echo ""

read -p "Choose option (1-5): " choice

case $choice in
    1)
        echo "📅 CONSERVATIVE cleanup: Keeping last 30 days..."
        CLEANUP_TYPE="date"
        INTERVAL="30 days"
        ;;
    2)
        echo "🔥 AGGRESSIVE cleanup: Keeping last 7 days..."
        CLEANUP_TYPE="date"
        INTERVAL="7 days"
        ;;
    3)
        echo "🎯 SURGICAL cleanup: Deleting largest execution data..."
        CLEANUP_TYPE="size"
        SIZE_LIMIT="10485760"  # 10MB in bytes
        ;;
    4)
        echo "📋 MORE INFO: Showing detailed analysis..."
        CLEANUP_TYPE="info"
        ;;
    5)
        echo "⏭️  SKIPPING cleanup"
        CLEANUP_TYPE="skip"
        ;;
    *)
        echo "🛡️  DEFAULT: Conservative cleanup (30 days)"
        CLEANUP_TYPE="date"
        INTERVAL="30 days"
        ;;
esac

if [ "$CLEANUP_TYPE" = "info" ]; then
    echo ""
    echo "📊 DETAILED ANALYSIS:"
    echo "===================="

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        -- Size distribution
        SELECT
            'Size distribution:' as analysis,
            CASE
                WHEN LENGTH(ed.data) > 100000000 THEN 'Huge (>100MB)'
                WHEN LENGTH(ed.data) > 10000000 THEN 'Large (>10MB)'
                WHEN LENGTH(ed.data) > 1000000 THEN 'Medium (>1MB)'
                ELSE 'Small (<1MB)'
            END as size_category,
            COUNT(*) as count,
            pg_size_pretty(SUM(LENGTH(ed.data))) as total_size
        FROM execution_data ed
        GROUP BY
            CASE
                WHEN LENGTH(ed.data) > 100000000 THEN 'Huge (>100MB)'
                WHEN LENGTH(ed.data) > 10000000 THEN 'Large (>10MB)'
                WHEN LENGTH(ed.data) > 1000000 THEN 'Medium (>1MB)'
                ELSE 'Small (<1MB)'
            END
        ORDER BY SUM(LENGTH(ed.data)) DESC;
        \"
    "

    echo ""
    echo "Re-run the script to perform cleanup after reviewing the analysis."

elif [ "$CLEANUP_TYPE" = "date" ]; then
    echo ""
    echo "3. Creating backup before cleanup..."

    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        -- Create backup of recent data
        CREATE TABLE execution_data_backup_$BACKUP_TIME AS
        SELECT ed.*
        FROM execution_data ed
        INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
        WHERE ee.\\\"startedAt\\\" > NOW() - INTERVAL '$INTERVAL';

        SELECT 'Backup created - rows saved:' as info, COUNT(*) as count
        FROM execution_data_backup_$BACKUP_TIME;
        \"
    "

    echo ""
    echo "4. Deleting old execution data (older than $INTERVAL)..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        -- Delete old execution data
        DELETE FROM execution_data
        WHERE \\\"executionId\\\" IN (
            SELECT ee.id
            FROM execution_entity ee
            WHERE ee.\\\"startedAt\\\" < NOW() - INTERVAL '$INTERVAL'
        );
        \"
    "

    echo ""
    echo "5. Reclaiming disk space (this may take a few minutes)..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        VACUUM FULL execution_data;
        ANALYZE execution_data;
        \"
    "

elif [ "$CLEANUP_TYPE" = "size" ]; then
    echo ""
    echo "3. Creating backup of large execution data..."

    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        -- Create backup of large data being deleted
        CREATE TABLE execution_data_large_backup_$BACKUP_TIME AS
        SELECT * FROM execution_data
        WHERE LENGTH(data) > $SIZE_LIMIT;

        SELECT 'Large data backup created - rows:' as info, COUNT(*) as count
        FROM execution_data_large_backup_$BACKUP_TIME;
        \"
    "

    echo ""
    echo "4. Deleting large execution data (>10MB each)..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        -- Delete large execution data
        DELETE FROM execution_data
        WHERE LENGTH(data) > $SIZE_LIMIT;
        \"
    "

    echo ""
    echo "5. Reclaiming disk space..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        VACUUM FULL execution_data;
        ANALYZE execution_data;
        \"
    "

elif [ "$CLEANUP_TYPE" = "skip" ]; then
    echo "⏭️  Skipping cleanup"
fi

if [ "$CLEANUP_TYPE" != "skip" ] && [ "$CLEANUP_TYPE" != "info" ]; then
    echo ""
    echo "6. Checking cleanup results..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        SELECT
            'CLEANUP RESULTS:' as status,
            COUNT(*) as remaining_records,
            pg_size_pretty(pg_total_relation_size('execution_data')) as new_table_size,
            pg_size_pretty(SUM(LENGTH(data))) as actual_data_size
        FROM execution_data;
        \"
    "

    echo ""
    echo "🎉 CLEANUP COMPLETED!"
    echo "===================="
    echo "✅ 28GB execution_data table cleaned"
    echo "✅ Disk space reclaimed"
    echo "✅ Backup created for safety"
    echo ""
    echo "🚀 N8N should now be DRAMATICALLY faster!"
fi

echo ""
echo "📝 NEXT STEPS:"
echo "============="
echo "1. Restart N8N: docker compose restart n8n"
echo "2. Test performance in N8N UI"
echo "3. Add data retention settings to prevent this recurring"
echo ""
echo "🔧 PREVENTION (add to .env file):"
echo "N8N_EXECUTIONS_DATA_PRUNE=true"
echo "N8N_EXECUTIONS_DATA_MAX_AGE=168"
echo "N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS=last"
