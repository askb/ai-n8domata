#!/bin/bash

echo "🔍 N8N BROWSER PERFORMANCE DEBUG"
echo "================================"

echo "Browser still struggling suggests multiple bottlenecks..."
echo ""

echo "1. FIRST: Restart N8N to clear cached data..."
echo "============================================="

# Restart N8N services to clear caches
echo "Restarting N8N services..."
docker compose restart n8n n8n-worker n8n-webhook

echo "Waiting for N8N to restart (30 seconds)..."
sleep 30

# Check if N8N is responding
echo ""
echo "Testing N8N response time..."
start_time=$(date +%s%N)
if curl -f -s http://localhost:5678/ > /dev/null 2>&1; then
    end_time=$(date +%s%N)
    response_time=$(((end_time - start_time) / 1000000))
    echo "✅ N8N base response: ${response_time}ms"

    if [ $response_time -gt 3000 ]; then
        echo "🚨 SLOW response time - server-side issues remain"
    fi
else
    echo "❌ N8N not responding after restart"
fi

echo ""
echo "2. CHECK: Current system resources..."
echo "====================================="

echo "Memory usage:"
free -h | grep "Mem:"

echo ""
echo "CPU usage:"
top -bn1 | grep "Cpu(s)" | head -1

echo ""
echo "Container resource usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10

echo ""
echo "3. CHECK: Execution data table current status..."
echo "==============================================="

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        'Current execution_data status:' as info,
        COUNT(*) as total_records,
        pg_size_pretty(pg_total_relation_size('execution_data')) as table_size,
        pg_size_pretty(AVG(LENGTH(data::text))) as avg_record_size,
        pg_size_pretty(MAX(LENGTH(data::text))) as largest_record_size
    FROM execution_data;
    \"
"

echo ""
echo "4. CHECK: Largest recent execution records..."
echo "============================================="

docker exec n8n-autoscaling-ag15-postgres-1 sh -c "
    export PGPASSWORD='${POSTGRES_PASSWORD}'
    psql -h localhost -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-n8n} -c \"
    SELECT
        ed.\\\"executionId\\\",
        ee.\\\"workflowId\\\",
        LENGTH(ed.data::text) as size_bytes,
        ROUND(LENGTH(ed.data::text)/1024.0/1024.0, 2) as size_mb,
        ee.status,
        ee.\\\"startedAt\\\"
    FROM execution_data ed
    INNER JOIN execution_entity ee ON ed.\\\"executionId\\\" = ee.id
    WHERE ee.\\\"startedAt\\\" > NOW() - INTERVAL '3 days'
    ORDER BY LENGTH(ed.data::text) DESC
    LIMIT 5;
    \"
"

echo ""
echo "5. CHECK: N8N log for performance issues..."
echo "==========================================="

echo "Recent N8N errors/warnings:"
docker logs --tail 20 n8n-autoscaling-ag15-n8n-1 2>&1 | grep -i -E "(error|warn|slow|timeout|memory|performance)"

echo ""
echo "6. BROWSER-SIDE PERFORMANCE FIXES..."
echo "===================================="

echo ""
echo "🌐 BROWSER TROUBLESHOOTING STEPS:"
echo "=================================="
echo ""
echo "A. Clear N8N browser data:"
echo "   1. Open browser Developer Tools (F12)"
echo "   2. Go to Application/Storage tab"
echo "   3. Clear all data for localhost:5678"
echo "   4. Hard refresh (Ctrl+Shift+R)"
echo ""
echo "B. Check browser memory usage:"
echo "   1. Open Task Manager/Activity Monitor"
echo "   2. Check if browser is using >4GB RAM"
echo "   3. Close other tabs and extensions"
echo ""
echo "C. Network inspection:"
echo "   1. Open Network tab in Developer Tools"
echo "   2. Refresh N8N page"
echo "   3. Look for large requests (>10MB)"
echo ""

echo ""
echo "🎯 IMMEDIATE PERFORMANCE FIXES:"
echo "==============================="
echo ""

read -p "Try these fixes? (y/N): " try_fixes

if [[ $try_fixes =~ ^[Yy]$ ]]; then
    echo ""
    echo "FIXING 1: Set N8N to show less execution data by default..."

    # Add performance environment variables
    echo "Adding performance settings to N8N..."

    docker exec n8n-autoscaling-ag15-n8n-1 sh -c "
        # These settings reduce the amount of data loaded in the UI
        export N8N_PAYLOAD_SIZE_MAX=1048576
        export N8N_EXECUTIONS_DATA_SAVE_ON_SUCCESS=last
        export N8N_EXECUTIONS_DATA_SAVE_ON_ERROR=all
        kill -USR2 1 2>/dev/null || echo 'Cannot reload config'
    " 2>/dev/null

    echo ""
    echo "FIXING 2: Clear any stuck browser connections..."

    # Restart with clean state
    docker compose stop n8n
    sleep 5
    docker compose up -d n8n

    echo "Waiting for clean restart..."
    sleep 20

    echo ""
    echo "FIXING 3: Test with minimal execution load..."

    # Test N8N response
    echo "Testing N8N performance..."
    for i in {1..3}; do
        start_time=$(date +%s%N)
        curl -f -s http://localhost:5678/ > /dev/null 2>&1
        end_time=$(date +%s%N)
        response_time=$(((end_time - start_time) / 1000000))
        echo "Test $i: ${response_time}ms"
        sleep 2
    done
fi

echo ""
echo "🚨 IF BROWSER STILL STRUGGLES:"
echo "=============================="
echo ""
echo "NUCLEAR OPTION - Delete large execution data records:"
echo ""
echo "1. Identify the largest execution records from above"
echo "2. Delete specific large executions manually:"
echo "   docker exec n8n-autoscaling-ag15-postgres-1 sh -c \\"
echo "     'export PGPASSWORD=... && psql ... -c \\"DELETE FROM execution_data WHERE \\\"executionId\\\" = [LARGE_ID];\\"'"
echo ""
echo "3. Alternative: Keep only tiny execution records:"
echo "   DELETE FROM execution_data WHERE LENGTH(data::text) > 1000000;"
echo ""

echo ""
echo "🔧 BROWSER-SPECIFIC SOLUTIONS:"
echo "=============================="
echo ""
echo "Chrome/Edge:"
echo "• Clear cache and storage for localhost:5678"
echo "• Disable extensions temporarily"
echo "• Try incognito mode"
echo "• Increase browser memory: --max-old-space-size=4096"
echo ""
echo "Firefox:"
echo "• about:memory -> Minimize memory usage"
echo "• about:config -> dom.max_script_run_time = 0"
echo ""
echo "Safari:"
echo "• Develop menu -> Empty Caches"
echo "• Disable extensions"
echo ""

echo ""
echo "📊 PERFORMANCE MONITORING:"
echo "========================="
echo ""
echo "Monitor these while using N8N:"
echo "• Browser memory usage (Task Manager)"
echo "• Network requests (Dev Tools)"
echo "• N8N container CPU/memory: docker stats n8n-autoscaling-ag15-n8n-1"
echo "• PostgreSQL activity: docker exec ... psql ... -c 'SELECT * FROM pg_stat_activity;'"
echo ""

echo "🎯 NEXT STEPS:"
echo "============="
echo "1. Try N8N in browser now (after restart)"
echo "2. If still slow, run the vacuum_and_analysis_fix.sh script"
echo "3. Consider the nuclear option if execution data is still massive"
echo "4. Check browser-specific solutions above"
