#!/bin/bash

echo "🔧 MANUAL VACUUM & DETAILED ANALYSIS"
echo "==================================="

echo "1. Running manual VACUUM to reclaim disk space..."

# Run VACUUM outside of transaction block
docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c 'VACUUM FULL execution_data;'
"

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c 'ANALYZE execution_data;'
"

echo ""
echo "2. Checking table size after VACUUM..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        'After VACUUM:' as status,
        COUNT(*) as records,
        pg_size_pretty(pg_total_relation_size('execution_data')) as table_size,
        pg_size_pretty(SUM(LENGTH(data::text))) as actual_data_size
    FROM execution_data;
    \"
"

echo ""
echo "3. Finding the TOP 10 largest execution records..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        ed.\\\"executionId\\\",
        CAST(LENGTH(ed.data::text) AS bigint) as data_size_bytes,
        CASE
            WHEN LENGTH(ed.data::text) > 100000000 THEN 'HUGE (>100MB)'
            WHEN LENGTH(ed.data::text) > 10000000 THEN 'Large (>10MB)'
            WHEN LENGTH(ed.data::text) > 1000000 THEN 'Medium (>1MB)'
            ELSE 'Small (<1MB)'
        END as size_category,
        ee.status,
        ee.\\\"startedAt\\\"
    FROM execution_data ed
    INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
    ORDER BY LENGTH(ed.data::text) DESC
    LIMIT 10;
    \"
"

echo ""
echo "4. Size distribution analysis..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        CASE
            WHEN LENGTH(ed.data::text) > 100000000 THEN 'HUGE (>100MB)'
            WHEN LENGTH(ed.data::text) > 10000000 THEN 'Large (10-100MB)'
            WHEN LENGTH(ed.data::text) > 1000000 THEN 'Medium (1-10MB)'
            WHEN LENGTH(ed.data::text) > 100000 THEN 'Small (100KB-1MB)'
            ELSE 'Tiny (<100KB)'
        END as size_category,
        COUNT(*) as record_count,
        ROUND(AVG(LENGTH(ed.data::text))/1024/1024, 2) as avg_size_mb,
        pg_size_pretty(SUM(LENGTH(ed.data::text))) as total_size
    FROM execution_data ed
    GROUP BY
        CASE
            WHEN LENGTH(ed.data::text) > 100000000 THEN 'HUGE (>100MB)'
            WHEN LENGTH(ed.data::text) > 10000000 THEN 'Large (10-100MB)'
            WHEN LENGTH(ed.data::text) > 1000000 THEN 'Medium (1-10MB)'
            WHEN LENGTH(ed.data::text) > 100000 THEN 'Small (100KB-1MB)'
            ELSE 'Tiny (<100KB)'
        END
    ORDER BY SUM(LENGTH(ed.data::text)) DESC;
    \"
"

echo ""
echo "5. Recent executions (last 7 days) analysis..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        DATE(ee.\\\"startedAt\\\") as execution_date,
        COUNT(*) as executions_count,
        pg_size_pretty(SUM(LENGTH(ed.data::text))) as total_data_size,
        ROUND(AVG(LENGTH(ed.data::text))/1024/1024, 2) as avg_size_mb
    FROM execution_data ed
    INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
    WHERE ee.\\\"startedAt\\\" > NOW() - INTERVAL '7 days'
    GROUP BY DATE(ee.\\\"startedAt\\\")
    ORDER BY DATE(ee.\\\"startedAt\\\") DESC;
    \"
"

echo ""
echo "📊 ANALYSIS COMPLETE!"
echo "===================="
echo ""
echo "🎯 SURGICAL CLEANUP OPTIONS:"
echo "============================"
echo ""
echo "Based on the analysis above, you can:"
echo ""
echo "Option A: Delete HUGE records (>100MB each)"
echo "Option B: Delete Large + Huge records (>10MB each)"
echo "Option C: Keep only last 7 days (more aggressive)"
echo "Option D: Manual cleanup - pick specific execution IDs"
echo "Option E: No further cleanup"
echo ""

read -p "Choose option (A/B/C/D/E): " surgical_choice

case $surgical_choice in
    A|a)
        echo "🎯 Deleting HUGE execution records (>100MB each)..."
        SIZE_LIMIT=100000000
        ;;
    B|b)
        echo "🔥 Deleting Large + Huge execution records (>10MB each)..."
        SIZE_LIMIT=10000000
        ;;
    C|c)
        echo "📅 Keeping only last 7 days..."
        SIZE_LIMIT=0
        DAYS=7
        ;;
    D|d)
        echo "🔧 Manual cleanup mode..."
        echo "Review the execution IDs above and run manual deletions"
        echo "Example: DELETE FROM execution_data WHERE \"executionId\" = 123;"
        SIZE_LIMIT=-1
        ;;
    *)
        echo "⏭️  No further cleanup"
        SIZE_LIMIT=-1
        ;;
esac

if [ "$SIZE_LIMIT" -gt 0 ]; then
    echo ""
    echo "Creating backup before surgical cleanup..."

    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        CREATE TABLE execution_data_large_backup_$BACKUP_TIME AS
        SELECT * FROM execution_data
        WHERE LENGTH(data::text) > $SIZE_LIMIT;
        \"
    "

    echo "Deleting large execution records..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        DELETE FROM execution_data
        WHERE LENGTH(data::text) > $SIZE_LIMIT;
        \"
    "

    echo "Running final VACUUM..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c 'VACUUM FULL execution_data;'
    "

elif [ "$DAYS" = "7" ]; then
    echo ""
    echo "Keeping only last 7 days..."

    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        CREATE TABLE execution_data_7days_backup_$BACKUP_TIME AS
        SELECT ed.*
        FROM execution_data ed
        INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
        WHERE ee.\\\"startedAt\\\" <= NOW() - INTERVAL '7 days';
        \"
    "

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        DELETE FROM execution_data
        WHERE \\\"executionId\\\" IN (
            SELECT ee.id
            FROM execution_entity ee
            WHERE ee.\\\"startedAt\\\" < NOW() - INTERVAL '7 days'
        );
        \"
    "

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c 'VACUUM FULL execution_data;'
    "
fi

if [ "$SIZE_LIMIT" -ge 0 ] || [ "$DAYS" = "7" ]; then
    echo ""
    echo "Final results after surgical cleanup..."

    docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
        export PGPASSWORD='${POSTGRES_PASSWORD}'
        psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
        SELECT
            'FINAL RESULTS:' as status,
            COUNT(*) as remaining_records,
            pg_size_pretty(pg_total_relation_size('execution_data')) as table_size,
            pg_size_pretty(SUM(LENGTH(data::text))) as actual_data_size
        FROM execution_data;
        \"
    "
fi

echo ""
echo "🎉 VACUUM AND ANALYSIS COMPLETE!"
echo "==============================="
echo ""
echo "🚀 Next step: Restart N8N to see the performance improvement!"
echo "   docker compose restart n8n"
