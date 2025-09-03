#!/bin/bash

echo "🚨 AI AGENT MEMORY ISSUE FIX"
echo "============================"

echo "PROBLEM IDENTIFIED: ai-agent-cpu using 13.7GB / 16GB (85.52%)"
echo "This is causing system-wide performance degradation!"
echo ""

echo "1. CHECKING AI AGENT STATUS..."
echo "============================="

echo "Current AI agent resource usage:"
docker stats --no-stream ai-agent-cpu

echo ""
echo "AI agent logs (checking for memory issues):"
docker logs --tail 20 ai-agent-cpu 2>&1 | grep -i -E "(memory|oom|killed|error|warning)"

echo ""
echo "2. IMMEDIATE SOLUTIONS..."
echo "========================"
echo ""
echo "A. RESTART AI agent (clears memory leaks)"
echo "B. REDUCE AI agent memory limit"
echo "C. STOP AI agent temporarily"
echo "D. SHOW MORE DIAGNOSTICS"
echo ""

read -r -p "Choose option (A/B/C/D): " ai_fix_choice

case $ai_fix_choice in
    A|a)
        echo "🔄 RESTARTING AI agent to clear memory..."

        docker compose restart ai-agent-cpu

        echo "Waiting for restart (30 seconds)..."
        sleep 30

        echo "Checking memory usage after restart:"
        docker stats --no-stream ai-agent-cpu
        ;;

    B|b)
        echo "📉 REDUCING AI agent memory limit..."

        echo ""
        echo "Current limit: 16GB"
        echo "Suggested new limit: 8GB"
        echo ""
        read -r -p "Enter new memory limit (e.g., 8G): " new_limit

        echo "Stopping AI agent..."
        docker compose stop ai-agent-cpu

        echo ""
        echo "Add this to your docker-compose.yml under ai-agent-cpu service:"
        echo "deploy:"
        echo "  resources:"
        echo "    limits:"
        echo "      memory: $new_limit"
        echo "      cpus: \"4.0\""
        echo ""
        echo "Then restart with: docker compose up -d ai-agent-cpu"
        ;;

    C|c)
        echo "⏹️ STOPPING AI agent temporarily..."

        docker compose stop ai-agent-cpu

        echo "✅ AI agent stopped!"
        echo ""
        echo "System memory after stopping AI agent:"
        free -h | grep "Mem:"

        echo ""
        echo "Test N8N performance now. If it's fast, the AI agent was the problem."
        echo "To restart AI agent later: docker compose up -d ai-agent-cpu"
        ;;

    D|d)
        echo "🔍 MORE DIAGNOSTICS..."

        echo ""
        echo "AI agent container detailed info:"
        docker exec ai-agent-cpu ps aux | head -10

        echo ""
        echo "AI agent environment variables:"
        docker exec ai-agent-cpu env | grep -E "(MEMORY|CUDA|TORCH|MODEL)" | head -10

        echo ""
        echo "System memory breakdown:"
        free -h

        echo ""
        echo "Process memory usage inside ai-agent:"
        docker exec ai-agent-cpu sh -c "cat /proc/meminfo | grep -E '(MemTotal|MemFree|MemAvailable)'" 2>/dev/null || echo "Cannot access memory info"
        ;;
esac

if [[ $ai_fix_choice =~ ^[AC]$ ]]; then
    echo ""
    echo "3. TESTING N8N PERFORMANCE AFTER AI AGENT FIX..."
    echo "================================================"

    echo "Testing N8N response time:"
    start_time=$(date +%s%N)
    if curl -f -s http://localhost:5678/ > /dev/null 2>&1; then
        end_time=$(date +%s%N)
        response_time=$(((end_time - start_time) / 1000000))
        echo "✅ N8N response time: ${response_time}ms"

        if [ $response_time -lt 1000 ]; then
            echo "🚀 EXCELLENT! N8N is now fast!"
        elif [ $response_time -lt 3000 ]; then
            echo "✅ Much better performance"
        else
            echo "⚠️ Still slow - may need more fixes"
        fi
    else
        echo "❌ N8N not responding"
    fi

    echo ""
    echo "System memory after AI agent fix:"
    free -h | grep "Mem:"

    echo ""
    echo "Container resource usage (top 10):"
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -10
fi

echo ""
echo "💡 AI AGENT MEMORY OPTIMIZATION TIPS:"
echo "===================================="
echo ""
echo "The AI agent likely has:"
echo "• Memory leaks in ML model loading"
echo "• Large language models cached in memory"
echo "• Poor garbage collection"
echo "• Model weights not being freed"
echo ""
echo "🔧 PERMANENT FIXES:"
echo "=================="
echo ""
echo "1. Add to docker-compose.yml under ai-agent-cpu:"
echo "   deploy:"
echo "     resources:"
echo "       limits:"
echo "         memory: 8G"
echo "         cpus: \"4.0\""
echo ""
echo "2. Add environment variables:"
echo "   - PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128"
echo "   - OMP_NUM_THREADS=4"
echo "   - PYTORCH_DISABLE_CUDA=1"
echo ""
echo "3. Regular restart schedule:"
echo "   restart: unless-stopped"
echo "   # Add a cron job to restart daily"
echo ""

echo ""
echo "🎯 NEXT STEPS:"
echo "============="
echo "1. Test N8N performance now"
echo "2. If fast → AI agent was the problem"
echo "3. Apply permanent memory limits"
echo "4. Monitor AI agent memory usage"
echo "5. Consider switching to lighter AI models"
