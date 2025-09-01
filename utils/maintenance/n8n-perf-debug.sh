#!/bin/bash

echo "=== N8N Performance Debug Script ==="
echo "Timestamp: $(date)"
echo

# 1. Check container health and resource usage
echo "1. Container Health Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

# 2. Check n8n specific containers memory and CPU
echo "2. N8N Container Resources:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | grep n8n
echo

# 3. Check Redis queue status
echo "3. Redis Queue Status:"
docker exec n8n-autoscaling-ag15-redis-1 redis-cli INFO memory
echo
docker exec n8n-autoscaling-ag15-redis-1 redis-cli INFO stats
echo
echo "Queue lengths:"
docker exec n8n-autoscaling-ag15-redis-1 redis-cli LLEN bull:main:waiting
docker exec n8n-autoscaling-ag15-redis-1 redis-cli LLEN bull:main:active
docker exec n8n-autoscaling-ag15-redis-1 redis-cli LLEN bull:main:failed
echo

# 4. Check PostgreSQL performance
echo "4. PostgreSQL Status:"
docker exec n8n-autoscaling-ag15-postgres-1 psql -U postgres -d n8n -c "
SELECT
    schemaname,
    tablename,
    attname,
    n_distinct,
    correlation
FROM pg_stats
WHERE schemaname = 'public'
ORDER BY tablename, attname;"

echo
echo "Active connections:"
docker exec n8n-autoscaling-ag15-postgres-1 psql -U postgres -d n8n -c "
SELECT count(*) as active_connections
FROM pg_stat_activity
WHERE state = 'active';"

echo
echo "Long running queries:"
docker exec n8n-autoscaling-ag15-postgres-1 psql -U postgres -d n8n -c "
SELECT
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
ORDER BY duration DESC;"

echo

# 5. Check n8n logs for errors
echo "5. Recent N8N Logs (last 50 lines):"
docker logs --tail 50 n8n-autoscaling-ag15-n8n-1 2>&1 | grep -E "(ERROR|WARN|timeout|slow|fail)"
echo

# 6. Check worker logs
echo "6. N8N Worker Logs (last 30 lines):"
docker logs --tail 30 n8n-autoscaling-ag15-n8n-worker-1 2>&1 | grep -E "(ERROR|WARN|timeout|slow|fail)"
echo

# 7. Check system resources
echo "7. System Resources:"
echo "Memory usage:"
free -h
echo
echo "CPU usage:"
top -bn1 | grep "Cpu(s)"
echo
echo "Disk usage:"
df -h | grep -E "(/$|/var)"
echo

# 8. Check network connectivity between containers
echo "8. Network Connectivity Test:"
echo "N8N to Redis:"
docker exec n8n-autoscaling-ag15-n8n-1 ping -c 2 redis 2>/dev/null && echo "✅ OK" || echo "❌ FAILED"
echo "N8N to Postgres:"
docker exec n8n-autoscaling-ag15-n8n-1 ping -c 2 postgres 2>/dev/null && echo "✅ OK" || echo "❌ FAILED"
echo

echo "=== Debug Complete ==="
echo "Save this output and check for:"
echo "- High memory usage (>80%)"
echo "- Redis queue buildup"
echo "- Long-running PostgreSQL queries"
echo "- Error messages in logs"
echo "- Network connectivity issues"
