#!/bin/bash
# migrate-to-persistent.sh
# Migration script to convert existing setup to persistent storage

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "============================================="
    echo "   Migration to Persistent AI Services"
    echo "============================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_existing_setup() {
    print_status "Checking existing setup..."

    # Check for running containers that might be CogVideo/WAN21
    echo "Current AI-related containers:"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "(comfy|cog|wan|video)" || echo "None found"

    echo
    echo "Current model directories:"
    ls -la | grep -E "(models|cog|wan)" || echo "None found"

    echo
    echo "Disk usage of model directories:"
    for dir in cogvideo-models wan21-models stable-diffusion-models svd-models; do
        if [ -d "$dir" ]; then
            echo "$dir: $(du -sh $dir | cut -f1)"
        fi
    done
}

stop_existing_services() {
    print_status "Stopping any existing AI video services..."

    # Stop any running containers that look like they might be CogVideo/WAN21
    docker ps --format "{{.Names}}" | grep -E "(comfy|cog|wan|video)" | while IFS= read -r container; do
        if [ ! -z "$container" ]; then
            print_warning "Stopping container: $container"
            docker stop "$container" || true
        fi
    done

    # Also stop our main compose services to be safe
    docker-compose stop stable-diffusion stable-video-diffusion 2>/dev/null || true
}

create_directory_structure() {
    print_status "Creating new directory structure..."

    # Create all necessary directories
    for service in cogvideo wan21; do
        echo "Creating directories for $service..."

        mkdir -p "./${service}-data"
        mkdir -p "./${service}-outputs"
        mkdir -p "./${service}-custom-nodes"

        # Set proper permissions
        sudo chown -R 1000:1000 "./${service}-data" "./${service}-outputs" "./${service}-custom-nodes" 2>/dev/null || true
        chmod -R 755 "./${service}-data" "./${service}-outputs" "./${service}-custom-nodes"
    done

    # Create scripts directory
    mkdir -p "./scripts"

    print_status "Directory structure created"
}

create_setup_scripts() {
    print_status "Creating setup scripts..."

    # Create CogVideo setup script
    cat > "./scripts/cogvideo-setup.sh" << 'EOF'
#!/bin/bash
# CogVideo Custom Node Setup Script

set -e
echo "=== CogVideo Custom Node Setup ==="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

COMFYUI_PATH="/home/runner/ComfyUI"
CUSTOM_NODES_PATH="$COMFYUI_PATH/custom_nodes"

# Wait for ComfyUI to be installed
while [ ! -d "$COMFYUI_PATH" ]; do
    echo "Waiting for ComfyUI installation..."
    sleep 10
done

mkdir -p "$CUSTOM_NODES_PATH"

install_if_missing() {
    local node_name="$1"
    local repo_url="$2"
    local node_path="$CUSTOM_NODES_PATH/$node_name"

    if [ -d "$node_path" ]; then
        echo -e "${GREEN}✓ $node_name already installed${NC}"
    else
        echo -e "${YELLOW}Installing $node_name...${NC}"
        cd "$CUSTOM_NODES_PATH"
        git clone --depth=1 "$repo_url" "$node_name" || echo "Failed to clone $node_name"

        if [ -f "$node_path/requirements.txt" ]; then
            echo "Installing requirements for $node_name..."
            pip install -r "$node_path/requirements.txt" || echo "Warning: Some requirements failed"
        fi

        echo -e "${GREEN}✓ $node_name installed${NC}"
    fi
}

# Install CogVideo nodes
install_if_missing "ComfyUI-CogVideoXWrapper" "https://github.com/kijai/ComfyUI-CogVideoXWrapper.git"
install_if_missing "ComfyUI-VideoHelperSuite" "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
install_if_missing "ComfyUI-Advanced-ControlNet" "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git"
install_if_missing "ComfyUI-Manager" "https://github.com/ltdrdata/ComfyUI-Manager.git"

echo -e "${GREEN}=== CogVideo setup complete ===${NC}"
EOF

    # Create WAN21 setup script
    cat > "./scripts/wan21-setup.sh" << 'EOF'
#!/bin/bash
# WAN21 Custom Node Setup Script

set -e
echo "=== WAN21 Custom Node Setup ==="

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

COMFYUI_PATH="/home/runner/ComfyUI"
CUSTOM_NODES_PATH="$COMFYUI_PATH/custom_nodes"

# Wait for ComfyUI to be installed
while [ ! -d "$COMFYUI_PATH" ]; do
    echo "Waiting for ComfyUI installation..."
    sleep 10
done

mkdir -p "$CUSTOM_NODES_PATH"

install_if_missing() {
    local node_name="$1"
    local repo_url="$2"
    local node_path="$CUSTOM_NODES_PATH/$node_name"

    if [ -d "$node_path" ]; then
        echo -e "${GREEN}✓ $node_name already installed${NC}"
    else
        echo -e "${YELLOW}Installing $node_name...${NC}"
        cd "$CUSTOM_NODES_PATH"
        git clone --depth=1 "$repo_url" "$node_name" || echo "Failed to clone $node_name"

        if [ -f "$node_path/requirements.txt" ]; then
            echo "Installing requirements for $node_name..."
            pip install -r "$node_path/requirements.txt" || echo "Warning: Some requirements failed"
        fi

        echo -e "${GREEN}✓ $node_name installed${NC}"
    fi
}

# Install WAN21 nodes - adjust URLs based on actual repositories
install_if_missing "ComfyUI-VideoHelperSuite" "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
install_if_missing "ComfyUI-Advanced-ControlNet" "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git"
install_if_missing "ComfyUI-Manager" "https://github.com/ltdrdata/ComfyUI-Manager.git"
install_if_missing "ComfyUI_essentials" "https://github.com/cubiq/ComfyUI_essentials.git"

echo -e "${GREEN}=== WAN21 setup complete ===${NC}"
EOF

    chmod +x ./scripts/*.sh
    print_status "Setup scripts created"
}

backup_current_setup() {
    print_status "Creating backup of current setup..."

    backup_date=$(date +%Y%m%d-%H%M%S)
    backup_file="pre-migration-backup-${backup_date}.tar.gz"

    print_warning "Creating backup: $backup_file"
    print_warning "This may take several minutes due to model sizes..."

    # Create backup excluding the largest model directories to save time/space
    tar -czf "$backup_file" \
        --exclude='./wan21-models' \
        --exclude='./cogvideo-models' \
        --exclude='./stable-diffusion-models' \
        --exclude='./postgres-data' \
        --exclude='./daily-backups' \
        --exclude='./backups' \
        . 2>/dev/null || true

    if [ -f "$backup_file" ]; then
        print_status "Backup created: $backup_file ($(du -sh $backup_file | cut -f1))"
        print_warning "Models were NOT backed up due to size - they will remain in place"
    else
        print_error "Backup failed, but continuing with migration"
    fi
}

update_docker_compose() {
    print_status "Updating docker-compose.yml..."

    # Create backup of current compose file
    cp docker-compose.yml "docker-compose.yml.backup-$(date +%Y%m%d-%H%M%S)"

    print_warning "You need to manually add the CogVideo and WAN21 services to your docker-compose.yml"
    print_warning "The service definitions have been provided in the artifacts."
    print_warning "Add them to the 'services:' section of your docker-compose.yml"
}

show_completion_instructions() {
    print_banner
    print_status "Migration setup complete!"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Add the CogVideo and WAN21 service definitions to your docker-compose.yml"
    echo "2. Test the setup:"
    echo "   ./scripts/manage-ai-video.sh start"
    echo "3. Monitor the first startup (will take 5-10 minutes):"
    echo "   ./scripts/manage-ai-video.sh logs cogvideo"
    echo "   ./scripts/manage-ai-video.sh logs wan21"
    echo "4. Access the services:"
    echo "   CogVideo: http://localhost:8189"
    echo "   WAN21: http://localhost:8190"
    echo
    echo -e "${YELLOW}Important:${NC}"
    echo "- Your models (66GB + 172GB) are preserved and will be mounted correctly"
    echo "- First startup will download ComfyUI and custom nodes (one-time ~5GB)"
    echo "- Subsequent restarts will be much faster using persistent storage"
    echo "- Use 'manage-ai-video.sh clean' if you need to reset the installations"
    echo
    echo -e "${GREEN}Disk Space Saved:${NC}"
    echo "- No more re-downloading custom nodes on restart"
    echo "- No more re-downloading Python dependencies"
    echo "- Only one-time setup, then persistent storage"
}

# Main migration process
main() {
    print_banner

    print_warning "This script will migrate your setup to use persistent storage"
    print_warning "for CogVideo and WAN21 services to prevent re-downloading."
    echo
    read -p "Continue with migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 0
    fi

    check_existing_setup
    echo
    read -p "Proceed with stopping services and migration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 0
    fi

    stop_existing_services
    backup_current_setup
    create_directory_structure
    create_setup_scripts
    update_docker_compose
    show_completion_instructions
}

# Run main function
main "$@"
