#!/bin/bash

echo "🔍 EXECUTION DATA ANALYSIS - Fixed Schema Version"
echo "================================================="

echo "1. First, let's check the actual execution_data table structure..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        column_name,
        data_type,
        is_nullable
    FROM information_schema.columns
    WHERE table_name = 'execution_data'
    ORDER BY ordinal_position;
    \"
"

echo ""
echo "2. Checking total execution_data count and size..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        'Total execution_data records:' as info,
        COUNT(*) as count,
        pg_size_pretty(pg_total_relation_size('execution_data')) as table_size
    FROM execution_data;
    \"
"

echo ""
echo "3. Checking relationship between execution_data and execution_entity..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    -- Check if execution_data has executionId to link to execution_entity
    SELECT
        column_name,
        data_type
    FROM information_schema.columns
    WHERE table_name = 'execution_data'
      AND column_name LIKE '%execution%';
    \"
"

echo ""
echo "4. Analyzing execution_data by linking to execution_entity dates..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    -- Try to analyze execution_data by joining with execution_entity for dates
    SELECT
        CASE
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '7 days' THEN 'Last 7 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '30 days' THEN 'Last 30 days'
            WHEN ee.\\\"startedAt\\\" > NOW() - INTERVAL '90 days' THEN 'Last 90 days'
            ELSE 'Older than 90 days'
        END as age_group,
        COUNT(ed.*) as execution_data_count
    FROM execution_data ed
    LEFT JOIN execution_entity ee ON CAST(ed.\\\"executionId\\\" AS varchar) = CAST(ee.id AS varchar)
    WHERE ee.\\\"startedAt\\\" IS NOT NULL
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
echo "5. Checking for orphaned execution_data (data without corresponding execution_entity)..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        'Orphaned execution_data records (no matching execution):' as info,
        COUNT(*) as count
    FROM execution_data ed
    LEFT JOIN execution_entity ee ON CAST(ed.\\\"executionId\\\" AS varchar) = CAST(ee.id AS varchar)
    WHERE ee.id IS NULL;
    \"
"

echo ""
echo "6. Sample of execution_data records (first 5)..."

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        \\\"executionId\\\",
        LEFT(\\\"workflowId\\\", 50) as workflow_id_preview,
        LENGTH(\\\"data\\\") as data_size_bytes,
        pg_size_pretty(LENGTH(\\\"data\\\")) as data_size_pretty
    FROM execution_data
    ORDER BY LENGTH(\\\"data\\\") DESC
    LIMIT 5;
    \"
"

echo ""
echo "✅ EXECUTION DATA ANALYSIS COMPLETE"
echo "=================================="
echo ""
echo "🎯 KEY FINDINGS TO LOOK FOR:"
echo "• Total execution_data count vs execution_entity count (359)"
echo "• Size breakdown by age groups"
echo "• Orphaned records (data without executions)"
echo "• Large individual execution data sizes"
echo ""
echo "💡 LIKELY ISSUES:"
echo "• Execution data not being cleaned up automatically"
echo "• Large workflow outputs being stored"
echo "• Orphaned execution data from deleted executions"
