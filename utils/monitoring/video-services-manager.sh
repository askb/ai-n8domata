#!/bin/bash
# video-services-manager.sh
# Manage WAN21 and CogVideo services

set -e

# RED='\033[0;31m'  # Unused color
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "================================================="
    echo "        Video AI Services Manager"
    echo "      WAN21 & CogVideo for AMD RX 6800M"
    echo "================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

create_directories() {
    print_status "Creating required directories..."

    # Create directories for both services
    for service in wan21 cogvideo; do
        mkdir -p "./${service}-data"
        mkdir -p "./${service}-outputs"
        mkdir -p "./${service}-custom-nodes"

        # Fix permissions
        sudo chown -R 1000:1000 "./${service}-data" "./${service}-outputs" "./${service}-custom-nodes" 2>/dev/null || true
        chmod -R 755 "./${service}-data" "./${service}-outputs" "./${service}-custom-nodes"

        echo "  ✅ Created directories for $service"
    done
}

show_status() {
    print_status "Video AI Services Status:"
    echo

    # WAN21 service
    if docker ps --format "{{.Names}}" | grep -q "wan21-comfyui"; then
        echo -e "${GREEN}WAN21 ComfyUI:${NC} RUNNING"
        echo "  └─ Access: http://localhost:8190"
        echo "  └─ Models: $(du -sh wan21-models 2>/dev/null | cut -f1 || echo 'N/A')"
    else
        echo -e "${YELLOW}WAN21 ComfyUI:${NC} STOPPED"
    fi

    # CogVideo service
    if docker ps --format "{{.Names}}" | grep -q "cogvideo-comfyui"; then
        echo -e "${GREEN}CogVideo ComfyUI:${NC} RUNNING"
        echo "  └─ Access: http://localhost:8189"
        echo "  └─ Models: $(du -sh cogvideo-models 2>/dev/null | cut -f1 || echo 'N/A')"
    else
        echo -e "${YELLOW}CogVideo ComfyUI:${NC} STOPPED"
    fi

    # Disk usage
    echo -e "\n${BLUE}Storage Usage:${NC}"
    df -h . | tail -1

    echo -e "\n${BLUE}Service Data Usage:${NC}"
    for service in wan21 cogvideo; do
        if [ -d "${service}-data" ]; then
            size=$(du -sh "${service}-data" 2>/dev/null | cut -f1 || echo '0B')
            echo "  ${service}-data: $size"
        fi
    done
}

start_services() {
    local service="$1"

    if [ "$service" = "all" ]; then
        print_status "Starting both WAN21 and CogVideo services..."
        docker-compose --profile anim up -d wan21-video cogvideo
    elif [ "$service" = "wan21" ]; then
        print_status "Starting WAN21 service..."
        docker-compose --profile anim up -d wan21-video
    elif [ "$service" = "cogvideo" ]; then
        print_status "Starting CogVideo service..."
        docker-compose --profile anim up -d cogvideo
    else
        print_warning "Invalid service. Use: all, wan21, or cogvideo"
        return 1
    fi

    echo
    print_status "Services starting... First startup may take 5-10 minutes to install ROCm PyTorch"
    print_status "Monitor progress with: docker logs -f [service-name]"
}

stop_services() {
    local service="$1"

    if [ "$service" = "all" ]; then
        print_status "Stopping both video services..."
        docker-compose stop wan21-comfyui cogvideo-comfyui 2>/dev/null || true
    elif [ "$service" = "wan21" ]; then
        print_status "Stopping WAN21 service..."
        docker-compose stop wan21-comfyui 2>/dev/null || true
    elif [ "$service" = "cogvideo" ]; then
        print_status "Stopping CogVideo service..."
        docker-compose stop cogvideo-comfyui 2>/dev/null || true
    else
        print_warning "Invalid service. Use: all, wan21, or cogvideo"
        return 1
    fi
}

show_logs() {
    local service="$1"

    if [ "$service" = "wan21" ]; then
        print_status "Showing WAN21 logs (Ctrl+C to exit)..."
        docker logs -f wan21-comfyui
    elif [ "$service" = "cogvideo" ]; then
        print_status "Showing CogVideo logs (Ctrl+C to exit)..."
        docker logs -f cogvideo-comfyui
    else
        print_warning "Invalid service. Use: wan21 or cogvideo"
        return 1
    fi
}

check_health() {
    print_status "Checking service health..."
    echo

    # Check WAN21
    if docker ps --format "{{.Names}}" | grep -q "wan21-comfyui"; then
        echo -e "${BLUE}WAN21 Health Check:${NC}"
        if curl -s http://localhost:8190/ >/dev/null 2>&1; then
            echo "  ✅ WAN21 ComfyUI responding on port 8190"
        else
            echo "  ❌ WAN21 ComfyUI not responding"
        fi
    fi

    # Check CogVideo
    if docker ps --format "{{.Names}}" | grep -q "cogvideo-comfyui"; then
        echo -e "${BLUE}CogVideo Health Check:${NC}"
        if curl -s http://localhost:8189/ >/dev/null 2>&1; then
            echo "  ✅ CogVideo ComfyUI responding on port 8189"
        else
            echo "  ❌ CogVideo ComfyUI not responding"
        fi
    fi
}

reset_service() {
    local service="$1"

    print_warning "This will reset the $service service (remove cached installations)"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    # Stop service
    stop_services "$service"

    # Remove cached data (but keep models)
    if [ "$service" = "wan21" ]; then
        print_status "Resetting WAN21 service data..."
        sudo rm -rf ./wan21-data/* 2>/dev/null || true
    elif [ "$service" = "cogvideo" ]; then
        print_status "Resetting CogVideo service data..."
        sudo rm -rf ./cogvideo-data/* 2>/dev/null || true
    fi

    print_status "Service reset complete. Next startup will reinstall everything."
}

show_help() {
    echo "Video AI Services Manager"
    echo
    echo "Manages WAN21 and CogVideo services with AMD ROCm support"
    echo
    echo "Usage: $0 [COMMAND] [SERVICE]"
    echo
    echo "Commands:"
    echo "  start SERVICE    Start service (wan21|cogvideo|all)"
    echo "  stop SERVICE     Stop service (wan21|cogvideo|all)"
    echo "  status           Show service status"
    echo "  logs SERVICE     Show service logs (wan21|cogvideo)"
    echo "  health           Check service health"
    echo "  reset SERVICE    Reset service data (wan21|cogvideo)"
    echo "  setup            Create required directories"
    echo "  help             Show this help"
    echo
    echo "Examples:"
    echo "  $0 setup              # Create directories first"
    echo "  $0 start wan21        # Start WAN21 only"
    echo "  $0 start all          # Start both services"
    echo "  $0 logs wan21         # Monitor WAN21 startup"
    echo "  $0 reset cogvideo     # Reset CogVideo if issues"
    echo
    echo "Service URLs:"
    echo "  WAN21:    http://localhost:8190"
    echo "  CogVideo: http://localhost:8189"
}

# Main execution
print_banner

case "${1:-help}" in
    "setup")
        create_directories
        ;;
    "start")
        create_directories
        start_services "${2:-all}"
        show_status
        ;;
    "stop")
        stop_services "${2:-all}"
        show_status
        ;;
    "status")
        show_status
        ;;
    "logs")
        if [ -z "$2" ]; then
            echo "Please specify service: wan21 or cogvideo"
            exit 1
        fi
        show_logs "$2"
        ;;
    "health")
        check_health
        ;;
    "reset")
        if [ -z "$2" ]; then
            echo "Please specify service: wan21 or cogvideo"
            exit 1
        fi
        reset_service "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac
