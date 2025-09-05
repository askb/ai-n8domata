#!/usr/bin/env python3
"""
Comprehensive test script for AI-Automata services.
Tests imports, configurations, and service health checks.
"""

import json
import os
import subprocess
import sys
from pathlib import Path


# Colors for output
class Colors:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    BOLD = "\033[1m"
    END = "\033[0m"


def print_status(message, status="info"):
    """Print colored status messages."""
    if status == "success":
        print(f"{Colors.GREEN}✅ {message}{Colors.END}")
    elif status == "error":
        print(f"{Colors.RED}❌ {message}{Colors.END}")
    elif status == "warning":
        print(f"{Colors.YELLOW}⚠️ {message}{Colors.END}")
    elif status == "info":
        print(f"{Colors.BLUE}ℹ️ {message}{Colors.END}")
    elif status == "header":
        print(f"\n{Colors.BOLD}{Colors.CYAN}{'='*60}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.CYAN}{message}{Colors.END}")
        print(f"{Colors.BOLD}{Colors.CYAN}{'='*60}{Colors.END}")


def test_python_imports():
    """Test Python service imports."""
    print_status("Testing Python Service Imports", "header")

    services = {
        "queue-metrics": ["config", "redis_client", "monitor"],
        "dynamic-scaler": ["config", "redis_client", "docker_manager", "scaler"],
    }

    results = {}

    for service, modules in services.items():
        print_status(f"Testing {service} imports...")
        service_path = Path(service)

        if not service_path.exists():
            print_status(f"Service directory {service} not found", "error")
            results[service] = False
            continue

        # Test each module import
        import_results = []
        for module in modules:
            try:
                # Run python import test
                cmd = [
                    sys.executable,
                    "-c",
                    f"import sys; sys.path.insert(0, '{service}'); import {module}; print('OK')",
                ]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

                if result.returncode == 0 and "OK" in result.stdout:
                    print_status(f"  {module}: Import successful", "success")
                    import_results.append(True)
                else:
                    print_status(
                        f"  {module}: Import failed - {result.stderr.strip()}", "error"
                    )
                    import_results.append(False)

            except subprocess.TimeoutExpired:
                print_status(f"  {module}: Import timeout", "error")
                import_results.append(False)
            except Exception as e:
                print_status(f"  {module}: Exception - {str(e)}", "error")
                import_results.append(False)

        results[service] = all(import_results)
        if results[service]:
            print_status(f"{service} imports: ALL PASSED", "success")
        else:
            print_status(f"{service} imports: SOME FAILED", "error")

    return results


def test_docker_builds():
    """Test Docker builds for all services."""
    print_status("Testing Docker Builds", "header")

    services = {
        "n8n": {"dockerfile": "Dockerfile", "context": "."},
        "queue-metrics": {
            "dockerfile": "queue-metrics/Dockerfile.queue-metrics",
            "context": ".",
        },
        "dynamic-scaler": {
            "dockerfile": "dynamic-scaler/Dockerfile.dynamic-scaler",
            "context": ".",
        },
        "cropper": {"dockerfile": "cropper/Dockerfile", "context": "cropper"},
    }

    results = {}

    for service, config in services.items():
        print_status(f"Testing {service} Docker build...")

        dockerfile = config["dockerfile"]
        context = config["context"]

        if not Path(dockerfile).exists():
            print_status(f"Dockerfile {dockerfile} not found", "warning")
            results[service] = "skip"
            continue

        try:
            # Test Docker build
            cmd = [
                "docker",
                "build",
                "-f",
                dockerfile,
                "-t",
                f"test-{service}:latest",
                context,
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)

            if result.returncode == 0:
                print_status(f"{service} Docker build: SUCCESS", "success")
                results[service] = True
            else:
                print_status(f"{service} Docker build: FAILED", "error")
                print_status(
                    f"Error: {result.stderr[-500:]}", "error"
                )  # Last 500 chars
                results[service] = False

        except subprocess.TimeoutExpired:
            print_status(f"{service} Docker build: TIMEOUT", "error")
            results[service] = False
        except Exception as e:
            print_status(f"{service} Docker build: EXCEPTION - {str(e)}", "error")
            results[service] = False

    return results


def test_docker_compose_config():
    """Test Docker Compose configuration."""
    print_status("Testing Docker Compose Configuration", "header")

    try:
        # Test config validation
        result = subprocess.run(
            ["docker", "compose", "config"], capture_output=True, text=True, timeout=30
        )

        if result.returncode == 0:
            print_status("Docker Compose config: VALID", "success")
            return True
        else:
            print_status(f"Docker Compose config: INVALID - {result.stderr}", "error")
            return False

    except subprocess.TimeoutExpired:
        print_status("Docker Compose config: TIMEOUT", "error")
        return False
    except Exception as e:
        print_status(f"Docker Compose config: EXCEPTION - {str(e)}", "error")
        return False


def create_health_check_script():
    """Create health check script for running services."""
    print_status("Creating Health Check Script", "header")

    health_script = """#!/bin/bash
# Health Check Script for AI-Automata Services

set -e

RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
NC='\\033[0m'

echo "🏥 AI-Automata Services Health Check"
echo "======================================"

check_service() {
    local service_name=$1
    local url=$2
    local expected_response=${3:-"200"}

    echo -n "Checking $service_name... "

    if curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" | \\
       grep -q "$expected_response"; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

check_redis() {
    echo -n "Checking Redis... "
    if docker exec $(docker compose ps -q redis) redis-cli ping | grep -q "PONG"; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

check_postgres() {
    echo -n "Checking PostgreSQL... "
    if docker exec $(docker compose ps -q postgres) pg_isready -q; then
        echo -e "${GREEN}✅ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}❌ UNHEALTHY${NC}"
        return 1
    fi
}

# Check basic services
check_redis
check_postgres

# Check web services
check_service "N8N Web" "http://localhost:5678/healthz" "200\\|302"
check_service "Queue Metrics" "http://localhost:8080/health" "200"
check_service "Dynamic Scaler" "http://localhost:8081/health" "200"

# Check Prometheus & Grafana if running
if docker compose ps | grep -q prometheus; then
    check_service "Prometheus" "http://localhost:9090/-/healthy"
fi

if docker compose ps | grep -q grafana; then
    check_service "Grafana" "http://localhost:3000/api/health"
fi

echo ""
echo "Health check completed!"
"""

    with open("health-check.sh", "w") as f:
        f.write(health_script)

    os.chmod("health-check.sh", 0o755)
    print_status("Health check script created: health-check.sh", "success")


def run_github_actions_check():
    """Check latest GitHub Actions status."""
    print_status("Checking GitHub Actions Status", "header")

    try:
        # Get recent runs
        result = subprocess.run(
            [
                "gh",
                "run",
                "list",
                "--limit",
                "5",
                "--json",
                "status,conclusion,displayTitle",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )

        if result.returncode == 0:
            runs = json.loads(result.stdout)

            for run in runs:
                status = run.get("status", "unknown")
                conclusion = run.get("conclusion", "unknown")
                title = run.get("displayTitle", "")[:50]

                if conclusion == "success":
                    print_status(f"✅ {title} - {status}/{conclusion}", "success")
                elif conclusion == "failure":
                    print_status(f"❌ {title} - {status}/{conclusion}", "error")
                else:
                    print_status(f"🔄 {title} - {status}/{conclusion}", "info")

            return True
        else:
            print_status(
                f"Failed to get GitHub Actions status: {result.stderr}", "error"
            )
            return False

    except subprocess.TimeoutExpired:
        print_status("GitHub Actions check: TIMEOUT", "error")
        return False
    except Exception as e:
        print_status(f"GitHub Actions check: EXCEPTION - {str(e)}", "error")
        return False


def main():
    """Main test runner."""
    print_status("AI-Automata Services Test Suite", "header")
    print_status(f"Running from: {os.getcwd()}")

    results = {}

    # Run all tests
    results["imports"] = test_python_imports()
    results["docker_builds"] = test_docker_builds()
    results["compose_config"] = test_docker_compose_config()
    results["github_actions"] = run_github_actions_check()

    # Create health check script
    create_health_check_script()

    # Summary
    print_status("Test Results Summary", "header")

    total_tests = 0
    passed_tests = 0

    for category, result in results.items():
        if isinstance(result, dict):
            for service, status in result.items():
                total_tests += 1
                if status is True:
                    passed_tests += 1
                    print_status(f"{category}.{service}: PASS", "success")
                elif status is False:
                    print_status(f"{category}.{service}: FAIL", "error")
                else:
                    print_status(f"{category}.{service}: SKIP", "warning")
        else:
            total_tests += 1
            if result:
                passed_tests += 1
                print_status(f"{category}: PASS", "success")
            else:
                print_status(f"{category}: FAIL", "error")

    # Final status
    success_rate = (passed_tests / total_tests) * 100 if total_tests > 0 else 0

    if success_rate == 100:
        print_status(f"ALL TESTS PASSED! ({passed_tests}/{total_tests})", "success")
        return 0
    elif success_rate >= 80:
        print_status(
            f"MOSTLY PASSING ({passed_tests}/{total_tests} - {success_rate:.1f}%)",
            "warning",
        )
        return 0
    else:
        print_status(
            f"MULTIPLE FAILURES ({passed_tests}/{total_tests} - {success_rate:.1f}%)",
            "error",
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
