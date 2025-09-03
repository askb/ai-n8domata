#!/bin/bash
# safe-cleanup-executor.sh
# Actually performs the cleanup operations safely with confirmation

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
# PURPLE='\033[0;35m'  # Unused color
NC='\033[0m'

# Critical directories that should NEVER be deleted
PROTECTED_DIRS=(
    "postgres-data"
    "backups"
    "daily-backups"
    "manual-backups"
    "n8n-data"
    "n8n-workflows"
    "n8n-credentials"
    ".git"
    "wan21-models"
    "cogvideo-models"
    "stable-diffusion-models"
    "svd-models"
    "data"
    "videos"
)

print_status() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

is_protected_path() {
    local path="$1"

    for protected in "${PROTECTED_DIRS[@]}"; do
        if [[ "$path" == ./"$protected"/* ]] || [[ "$path" == "$protected"/* ]] || [[ "$path" == "$protected" ]]; then
            return 0  # Protected
        fi
    done
    return 1  # Not protected
}

check_path_safety() {
    local path="$1"

    # Never delete if it's a protected path
    if is_protected_path "$path"; then
        print_error "BLOCKED: $path is in a protected directory"
        return 1
    fi

    # Never delete if it contains important files
    if [ -d "$path" ]; then
        # Check for database files
        if find "$path" -name "*.db" -o -name "*.sql" -o -name "pgdata" | grep -q .; then
            print_error "BLOCKED: $path contains database files"
            return 1
        fi

        # Check for model files
        if find "$path" -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pth" | grep -q .; then
            print_error "BLOCKED: $path contains model files"
            return 1
        fi

        # Check for config files
        if find "$path" -name "*.json" -o -name "*.yml" -o -name "*.yaml" | head -5 | grep -q .; then
            print_warning "WARNING: $path contains config files"
            echo "Files found:"
            find "$path" -name "*.json" -o -name "*.yml" -o -name "*.yaml" | head -5 | sed 's/^/  /'
            read -p "Still proceed? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi

    return 0  # Safe to delete
}

safe_remove_directory() {
    local dir="$1"
    local description="$2"

    if [ ! -d "$dir" ]; then
        return 0  # Nothing to remove
    fi

    print_status "Preparing to remove: $dir"
    echo "  Description: $description"
    echo "  Size: $(du -sh "$dir" 2>/dev/null | cut -f1 || echo 'Unknown')"
    echo "  Contents preview:"
    ls -la "$dir" 2>/dev/null | head -5 | sed 's/^/    /'
    echo

    if ! check_path_safety "$dir"; then
        print_error "Skipping $dir for safety reasons"
        return 1
    fi

    read -p "Delete this directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deleting $dir..."

        # Try without sudo first
        if rm -rf "$dir" 2>/dev/null; then
            print_status "✅ Successfully deleted $dir"
            return 0
        else
            print_warning "Permission denied, trying with sudo..."
            if sudo rm -rf "$dir" 2>/dev/null; then
                print_status "✅ Successfully deleted $dir (with sudo)"
                return 0
            else
                print_error "❌ Failed to delete $dir even with sudo"
                return 1
            fi
        fi
    else
        print_status "Skipped $dir"
        return 1
    fi
}

safe_remove_file() {
    local file="$1"
    local description="$2"

    if [ ! -f "$file" ]; then
        return 0  # Nothing to remove
    fi

    print_status "Preparing to remove file: $file"
    echo "  Description: $description"
    echo "  Size: $(du -sh "$file" 2>/dev/null | cut -f1 || echo 'Unknown')"
    echo "  Modified: $(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || echo 'Unknown')"
    echo

    if ! check_path_safety "$file"; then
        print_error "Skipping $file for safety reasons"
        return 1
    fi

    read -p "Delete this file? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deleting $file..."

        # Try without sudo first
        if rm "$file" 2>/dev/null; then
            print_status "✅ Successfully deleted $file"
            return 0
        else
            print_warning "Permission denied, trying with sudo..."
            if sudo rm "$file" 2>/dev/null; then
                print_status "✅ Successfully deleted $file (with sudo)"
                return 0
            else
                print_error "❌ Failed to delete $file even with sudo"
                return 1
            fi
        fi
    else
        print_status "Skipped $file"
        return 1
    fi
}

cleanup_virtual_environments() {
    print_status "Starting virtual environment cleanup..."
    echo

    local cleaned_count=0
    local cleaned_size=0
    local total_found=0

    # Find virtual environments, avoiding protected directories
    while IFS= read -r -d '' dir; do
        if [ -d "$dir" ]; then
            # Skip if in protected directory
            if is_protected_path "$dir"; then
                continue
            fi

            # Check if it looks like a real venv
            if [ -f "$dir/bin/python" ] || [ -f "$dir/Scripts/python.exe" ] || [ -d "$dir/lib" ] || [ -d "$dir/Lib" ]; then
                size_mb=$(du -sm "$dir" 2>/dev/null | cut -f1 || echo "0")

                if [ "$size_mb" -gt 10 ]; then  # Only process venvs > 10MB
                    total_found=$((total_found + 1))

                    # Check if currently in use
                    if [ -n "$VIRTUAL_ENV" ] && [[ "$VIRTUAL_ENV" == *"$dir"* ]]; then
                        print_warning "Skipping $dir - currently active virtual environment"
                        continue
                    fi

                    if safe_remove_directory "$dir" "Virtual environment (will be recreated)"; then
                        cleaned_count=$((cleaned_count + 1))
                        cleaned_size=$((cleaned_size + size_mb))
                    fi
                fi
            fi
        fi
    done < <(find . -maxdepth 3 -name "*venv*" -o -name "*env*" -type d -print0 2>/dev/null)

    echo -e "\n${BLUE}Virtual Environment Cleanup Summary:${NC}"
    echo "  Environments found: $total_found"
    echo "  Environments cleaned: $cleaned_count"
    echo "  Space freed: ${cleaned_size}MB ($(echo "scale=1; $cleaned_size/1024" | bc -l 2>/dev/null || echo "?")GB)"
}

cleanup_cache_directories() {
    print_status "Starting cache directory cleanup..."
    echo

    local cleaned_count=0
    local cleaned_size=0
    local total_found=0

    # Cache patterns to look for
    cache_patterns=("__pycache__" ".cache" "*.egg-info" ".pytest_cache" ".mypy_cache")

    for pattern in "${cache_patterns[@]}"; do
        while IFS= read -r -d '' dir; do
            if [ -d "$dir" ]; then
                # Skip if in protected directory
                if is_protected_path "$dir"; then
                    continue
                fi

                size_mb=$(du -sm "$dir" 2>/dev/null | cut -f1 || echo "0")

                if [ "$size_mb" -gt 1 ]; then  # Only process cache > 1MB
                    total_found=$((total_found + 1))

                    if safe_remove_directory "$dir" "Cache directory (will be recreated)"; then
                        cleaned_count=$((cleaned_count + 1))
                        cleaned_size=$((cleaned_size + size_mb))
                    fi
                fi
            fi
        done < <(find . -name "$pattern" -type d -print0 2>/dev/null)
    done

    echo -e "\n${BLUE}Cache Cleanup Summary:${NC}"
    echo "  Cache dirs found: $total_found"
    echo "  Cache dirs cleaned: $cleaned_count"
    echo "  Space freed: ${cleaned_size}MB"
}

cleanup_temp_files() {
    print_status "Starting temporary file cleanup..."
    echo

    local cleaned_count=0
    local cleaned_size=0
    local total_found=0

    # Safe temp file patterns
    temp_patterns=("*.tmp" "*.temp" "*.part" "*.download" "*.partial" "*.lock")

    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            if [ -f "$file" ]; then
                # Skip if in protected directory
                if is_protected_path "$file"; then
                    continue
                fi

                size_mb=$(du -sm "$file" 2>/dev/null | cut -f1 || echo "0")

                if [ "$size_mb" -gt 1 ]; then  # Only process files > 1MB
                    total_found=$((total_found + 1))

                    if safe_remove_file "$file" "Temporary file"; then
                        cleaned_count=$((cleaned_count + 1))
                        cleaned_size=$((cleaned_size + size_mb))
                    fi
                fi
            fi
        done < <(find . -name "$pattern" -type f -print0 2>/dev/null)
    done

    echo -e "\n${BLUE}Temporary File Cleanup Summary:${NC}"
    echo "  Temp files found: $total_found"
    echo "  Temp files cleaned: $cleaned_count"
    echo "  Space freed: ${cleaned_size}MB"
}

cleanup_docker_safely() {
    print_status "Starting Docker cleanup..."
    echo

    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not found, skipping Docker cleanup"
        return 0
    fi

    if ! docker info >/dev/null 2>&1; then
        print_warning "Cannot access Docker (permission issue?)"
        print_warning "You may need to:"
        print_warning "  1. Add your user to docker group: sudo usermod -aG docker $USER"
        print_warning "  2. Or run with: sudo ./safe-cleanup-executor.sh"
        return 0
    fi

    echo "Current Docker disk usage:"
    docker system df
    echo

    # Show what will be cleaned
    echo "Docker cleanup will remove:"
    echo "  • Stopped containers"
    echo "  • Unused networks"
    echo "  • Dangling images"
    echo "  • Build cache"
    echo
    echo "Docker cleanup will NOT remove:"
    echo "  • Running containers"
    echo "  • Images used by running containers"
    echo "  • Named volumes"
    echo

    read -p "Proceed with Docker system prune? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Running docker system prune..."
        docker system prune -f

        echo
        read -p "Also remove unused images? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Running docker image prune..."
            docker image prune -f
        fi

        echo -e "\n${BLUE}Docker cleanup complete!${NC}"
        echo "New Docker disk usage:"
        docker system df
    else
        print_status "Docker cleanup cancelled"
    fi
}

interactive_cleanup() {
    while true; do
        echo -e "\n${BLUE}=== SAFE CLEANUP EXECUTOR ===${NC}"
        echo "What would you like to clean up?"
        echo
        echo "1) Virtual environments (venv, .venv, etc.)"
        echo "2) Cache directories (__pycache__, .cache, etc.)"
        echo "3) Temporary files (*.tmp, *.part, etc.)"
        echo "4) Docker unused data"
        echo "5) Show current disk usage"
        echo "6) Exit"
        echo
        read -r -p "Choose option (1-6): " choice

        case $choice in
            1) cleanup_virtual_environments ;;
            2) cleanup_cache_directories ;;
            3) cleanup_temp_files ;;
            4) cleanup_docker_safely ;;
            5)
                echo -e "\n${BLUE}Current disk usage:${NC}"
                df -h .
                echo -e "\nLargest directories:"
                du -sh ./*/ 2>/dev/null | sort -hr | head -10
                ;;
            6)
                echo "Exiting cleanup executor"
                break
                ;;
            *)
                echo "Invalid option, please choose 1-6"
                ;;
        esac
    done
}

show_help() {
    echo "Safe Cleanup Executor"
    echo
    echo "This script safely removes files after showing you exactly what will be deleted"
    echo "and asking for confirmation at each step."
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  venv         Clean virtual environments"
    echo "  cache        Clean cache directories"
    echo "  temp         Clean temporary files"
    echo "  docker       Clean Docker unused data"
    echo "  interactive  Interactive cleanup menu"
    echo "  help         Show this help"
    echo
    echo "Safety Features:"
    echo "- Protected directories are never touched"
    echo "- Shows exactly what will be deleted before deletion"
    echo "- Requires individual confirmation for each item"
    echo "- Tries user permissions first, sudo only if needed"
}

# Check if scanner is available
if [ ! -f "safe-cleanup-scanner.sh" ]; then
    print_warning "Recommendation: Run ./safe-cleanup-scanner.sh first to scan your system"
fi

# Main execution
case "${1:-interactive}" in
    "venv")
        cleanup_virtual_environments
        ;;
    "cache")
        cleanup_cache_directories
        ;;
    "temp")
        cleanup_temp_files
        ;;
    "docker")
        cleanup_docker_safely
        ;;
    "interactive")
        interactive_cleanup
        ;;
    "help"|*)
        show_help
        ;;
esac
