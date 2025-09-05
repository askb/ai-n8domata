#!/bin/bash
# Health Check Script for AI-Automata Services

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏥 AI-Automata Services Health Check${NC}"
echo "======================================"

check_service() {
    local service_name=$1
    local url=$2
    local expected_response=${3:-"200"}

    echo -n "Checking $service_name... "

    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null | grep -q "$expected_response"; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

check_docker_service() {
    local service_name=$1
    local container_name=$2

    echo -n "Checking $service_name container... "

    if docker ps --format "table {{.Names}}" | grep -q "$container_name"; then
        echo -e "${GREEN}✅ RUNNING${NC}"
        return 0
    else
        echo -e "${RED}❌ NOT RUNNING${NC}"
        return 1
    fi
}

check_redis() {
    echo -n "Checking Redis... "
    if docker exec $(docker compose ps -q redis 2>/dev/null) redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

check_postgres() {
    echo -n "Checking PostgreSQL... "
    if docker exec $(docker compose ps -q postgres 2>/dev/null) pg_isready -q 2>/dev/null; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

test_docker_builds() {
    echo -e "\n${BLUE}🐳 Testing Docker Builds${NC}"
    echo "========================="

    # Test queue-metrics build
    echo -n "Building queue-metrics... "
    if docker build -f queue-metrics/Dockerfile.queue-metrics -t test-queue-metrics:health . >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi

    # Test dynamic-scaler build
    echo -n "Building dynamic-scaler... "
    if docker build -f dynamic-scaler/Dockerfile.dynamic-scaler -t test-dynamic-scaler:health . >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi

    # Test n8n build if Dockerfile exists
    if [[ -f "Dockerfile" ]]; then
        echo -n "Building n8n... "
        if docker build -f Dockerfile -t test-n8n:health . >/dev/null 2>&1; then
            echo -e "${GREEN}✅ SUCCESS${NC}"
        else
            echo -e "${RED}❌ FAILED${NC}"
        fi
    fi
}

test_python_imports() {
    echo -e "\n${BLUE}🐍 Testing Python Imports${NC}"
    echo "=========================="

    # Test queue-metrics imports
    echo -n "Queue-metrics imports... "
    cd queue-metrics
    if python -c "from config import Config; from redis_client import RedisClient; from monitor import QueueMonitor" 2>/dev/null; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
    cd ..

    # Test dynamic-scaler imports
    echo -n "Dynamic-scaler imports... "
    cd dynamic-scaler
    if PYTHONPATH=. python -c "from config import Config; from redis_client import RedisClient; from docker_manager import DockerManager; from scaler import DynamicScaler" 2>/dev/null; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
    else
        echo -e "${RED}❌ FAILED${NC}"
    fi
    cd ..
}

# Main health checks
echo -e "\n${BLUE}📋 Service Status Check${NC}"
echo "======================="

# Check if docker-compose.yml exists
if [[ ! -f "docker-compose.yml" ]]; then
    echo -e "${YELLOW}⚠️ docker-compose.yml not found, skipping service checks${NC}"
else
    # Check basic services
    check_redis || true
    check_postgres || true

    # Check web services
    check_service "N8N Web" "http://localhost:5678/healthz" "200|302" || true
    check_service "Queue Metrics" "http://localhost:8080/health" "200" || true
    check_service "Dynamic Scaler" "http://localhost:8081/health" "200" || true

    # Check Prometheus & Grafana if running
    if docker compose ps 2>/dev/null | grep -q prometheus; then
        check_service "Prometheus" "http://localhost:9090/-/healthy" || true
    fi

    if docker compose ps 2>/dev/null | grep -q grafana; then
        check_service "Grafana" "http://localhost:3000/api/health" || true
    fi
fi

# Run build tests
test_docker_builds

# Run import tests
test_python_imports

echo ""
echo -e "${BLUE}🎯 Health check completed!${NC}"
echo "Use 'docker compose up -d' to start services"
echo "Use 'docker compose ps' to check running containers"
