#!/bin/bash
# docker-log-analyzer.sh
# Analyze Docker logs to see which models actually worked vs failed

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
# PURPLE='\033[0;35m'  # Unused color
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "              DOCKER LOG ANALYZER FOR MODEL USAGE"
    echo "      Find which of your 172GB models actually worked"
    echo "=================================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[ANALYSIS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

find_relevant_containers() {
    print_status "Finding containers that might have used WAN21/CogVideo models..."
    echo

    # Look for any containers that might have used AI models
    echo -e "${BLUE}Current containers:${NC}"
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}" | grep -E "(comfy|wan|cog|video|ai|stable)" || echo "No AI-related containers found"

    echo -e "\n${BLUE}All containers (in case models were used elsewhere):${NC}"
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | head -10

    echo -e "\n${YELLOW}Note: If you don't see containers, they may have been removed${NC}"
    echo "We can still analyze logs from stopped containers if they exist"
}

analyze_container_logs() {
    local container_name="$1"
    local max_lines="${2:-1000}"

    print_status "Analyzing logs for container: $container_name"
    echo

    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        print_error "Container '$container_name' not found"
        return 1
    fi

    # Get container info
    echo -e "${BLUE}Container Info:${NC}"
    docker inspect "$container_name" --format "{{.State.Status}}" | while IFS= read -r status; do
        echo "  Status: $status"
    done
    docker inspect "$container_name" --format "{{.Created}}" | while IFS= read -r created; do
        echo "  Created: $created"
    done

    echo -e "\n${BLUE}Extracting model-related log entries...${NC}"

    # Create temporary log file
    local temp_log="/tmp/${container_name}_analysis.log"
    docker logs "$container_name" --tail "$max_lines" > "$temp_log" 2>&1

    if [ ! -s "$temp_log" ]; then
        print_warning "No logs found for container $container_name"
        return 1
    fi

    echo "Total log lines: $(wc -l < "$temp_log")"
    echo

    # Analyze different types of model events
    analyze_model_loading "$temp_log"
    analyze_model_failures "$temp_log"
    analyze_memory_usage "$temp_log"
    analyze_successful_generations "$temp_log"

    # Keep temp log for user reference
    cp "$temp_log" "${container_name}_model_analysis.log"
    echo "📋 Full analysis saved to: ${container_name}_model_analysis.log"

    rm "$temp_log"
}

analyze_model_loading() {
    local log_file="$1"

    echo -e "${GREEN}=== MODEL LOADING ANALYSIS ===${NC}"

    # Look for model loading patterns
    echo -e "\n🔍 Models that were loaded successfully:"
    grep -i "load.*model\|loading.*model\|model.*load" "$log_file" | grep -v -i "fail\|error\|exception" | head -10 | while IFS= read -r line; do
        echo "  ✅ $line"
    done

    # Look for specific model file names
    echo -e "\n🔍 Specific model files mentioned:"
    grep -E "(wan2\.1|cogvideo|\.safetensors|\.ckpt|\.pth)" "$log_file" | head -10 | while IFS= read -r line; do
        # Check if it's a success or failure
        if echo "$line" | grep -qi "error\|fail\|exception\|out of memory"; then
            echo "  ❌ $line"
        else
            echo "  ✅ $line"
        fi
    done
}

analyze_model_failures() {
    local log_file="$1"

    echo -e "\n${RED}=== MODEL FAILURE ANALYSIS ===${NC}"

    # Look for common failure patterns
    echo -e "\n🚫 VRAM/Memory failures:"
    grep -i "out of memory\|oom\|cuda out of memory\|not enough memory\|memory error" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  💥 $line"
    done

    echo -e "\n🚫 Model loading failures:"
    grep -i "failed to load\|cannot load\|model.*error\|loading.*fail" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  💥 $line"
    done

    echo -e "\n🚫 Format/compatibility issues:"
    grep -i "unsupported\|incompatible\|format.*error\|dtype.*error" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  💥 $line"
    done

    echo -e "\n🚫 ROCm/AMD specific errors:"
    grep -i "rocm\|hip\|amd\|gfx.*error" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  💥 $line"
    done
}

analyze_memory_usage() {
    local log_file="$1"

    echo -e "\n${CYAN}=== MEMORY USAGE ANALYSIS ===${NC}"

    # Look for memory usage patterns
    echo -e "\n📊 Memory allocation info:"
    grep -i "memory\|vram\|gpu.*memory\|allocated" "$log_file" | grep -E "[0-9]+\s*(MB|GB|bytes)" | head -5 | while IFS= read -r line; do
        echo "  📈 $line"
    done

    # Look for model size information
    echo -e "\n📊 Model size information:"
    grep -E "([0-9]+\.?[0-9]*)\s*(GB|MB).*model|model.*([0-9]+\.?[0-9]*)\s*(GB|MB)" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  📏 $line"
    done
}

analyze_successful_generations() {
    local log_file="$1"

    echo -e "\n${GREEN}=== SUCCESSFUL GENERATION ANALYSIS ===${NC}"

    # Look for successful generation patterns
    echo -e "\n🎬 Successful video generations:"
    grep -i "generated\|completed\|finished\|success.*video\|video.*success" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  🎉 $line"
    done

    # Look for output file creation
    echo -e "\n💾 Output files created:"
    grep -i "saved\|output\|wrote.*file\|created.*video" "$log_file" | head -5 | while IFS= read -r line; do
        echo "  💾 $line"
    done
}

extract_used_models() {
    local log_file="$1"

    print_status "Extracting list of actually used vs unused models..."
    echo

    # Create arrays for used and unused models
    declare -A used_models
    declare -A failed_models

    # Extract model names from successful operations
    while read -r line; do
        # Extract model filenames from log lines
        if echo "$line" | grep -qE "\.safetensors|\.ckpt|\.pth"; then
            model_file=$(echo "$line" | grep -oE "[a-zA-Z0-9._-]*\.(safetensors|ckpt|pth)")
            if echo "$line" | grep -qi "error\|fail\|exception"; then
                failed_models["$model_file"]=1
            else
                used_models["$model_file"]=1
            fi
        fi
    done < "$log_file"

    echo -e "${GREEN}Models that worked:${NC}"
    for model in "${!used_models[@]}"; do
        echo "  ✅ $model"
    done

    echo -e "\n${RED}Models that failed:${NC}"
    for model in "${!failed_models[@]}"; do
        echo "  ❌ $model"
    done
}

cross_reference_with_filesystem() {
    print_status "Cross-referencing log findings with your 172GB of models..."
    echo

    if [ ! -d "wan21-models" ]; then
        print_warning "wan21-models directory not found for cross-reference"
        return 1
    fi

    echo -e "${BLUE}Your WAN21 models vs log evidence:${NC}"

    # For each model file, check if it appears in any container logs
    find wan21-models -name "*.safetensors" | while IFS= read -r model_path; do
        model_name=$(basename "$model_path")
        model_size=$(du -sh "$model_path" | cut -f1)

        # Check if this model appears in any container logs
        found_in_logs=false
        for container in $(docker ps -a --format "{{.Names}}"); do
            if docker logs "$container" 2>&1 | grep -q "$model_name"; then
                found_in_logs=true
                break
            fi
        done

        if [ "$found_in_logs" = true ]; then
            echo "  ✅ $model_name ($model_size) - Found in logs"
        else
            echo "  ❓ $model_name ($model_size) - No evidence of use"
        fi
    done
}

generate_cleanup_report() {
    local analysis_date
    analysis_date=$(date +%Y%m%d-%H%M%S)
    local report_file="docker-log-model-analysis-${analysis_date}.txt"

    print_status "Generating comprehensive model usage report..."

    cat > "$report_file" << EOF
# Docker Log Model Analysis Report
# Generated: $(date)
# Analysis of model usage based on Docker container logs

## SUMMARY:
This report analyzes Docker logs to determine which of your models
were actually used vs which failed to load or were never attempted.

## CONTAINERS ANALYZED:
EOF

    docker ps -a --format "{{.Names}} - {{.Image}} - {{.Status}}" >> "$report_file"

    cat >> "$report_file" << EOF

## FINDINGS:
(Run the analysis to populate this section)

## RECOMMENDATIONS:
Based on log analysis:
1. Keep models that show successful loading/generation
2. Remove models that consistently fail with VRAM errors
3. Remove models with no evidence of use
4. Consider quantized versions of working models

## CLEANUP COMMANDS:
# Review these carefully before running:
# (Generated based on log analysis)

EOF

    echo "📋 Report template created: $report_file"
    echo "Run the analysis to populate findings"
}

interactive_log_analysis() {
    print_status "Starting interactive log analysis..."
    echo

    # Show available containers
    find_relevant_containers
    echo

    # Let user choose containers to analyze
    echo "Available containers for analysis:"
    docker ps -a --format "{{.Names}}" | nl
    echo

    read -r -p "Enter container name to analyze (or 'all' for all containers): " container_choice

    if [ "$container_choice" = "all" ]; then
        docker ps -a --format "{{.Names}}" | while IFS= read -r container; do
            echo -e "\n${BLUE}=== ANALYZING $container ===${NC}"
            analyze_container_logs "$container" 500
        done
    else
        analyze_container_logs "$container_choice" 1000
    fi

    # Cross-reference with filesystem
    echo -e "\n${BLUE}=== CROSS-REFERENCING WITH YOUR MODELS ===${NC}"
    cross_reference_with_filesystem
}

check_recent_activity() {
    print_status "Checking recent Docker activity for model usage..."
    echo

    # Check docker events for recent model-related activity
    echo -e "${BLUE}Recent Docker events (last 24h):${NC}"
    docker events --since "24h" --until "0s" | grep -E "(start|die|kill)" | head -10 || echo "No recent events found"

    # Check if any containers are currently running AI workloads
    echo -e "\n${BLUE}Currently running containers:${NC}"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

    # Check for recent image pulls
    echo -e "\n${BLUE}Recently pulled images:${NC}"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}" | head -10
}

show_help() {
    echo "Docker Log Analyzer for Model Usage"
    echo
    echo "Analyzes Docker container logs to determine which of your 172GB"
    echo "of models actually worked vs which failed to load."
    echo
    echo "Usage: $0 [COMMAND] [CONTAINER_NAME]"
    echo
    echo "Commands:"
    echo "  containers     List containers that might have used models"
    echo "  analyze NAME   Analyze specific container logs"
    echo "  interactive    Interactive analysis of all containers"
    echo "  recent         Check recent Docker activity"
    echo "  cross-ref      Cross-reference logs with filesystem models"
    echo "  report         Generate cleanup report based on findings"
    echo "  help           Show this help"
    echo
    echo "Examples:"
    echo "  $0 containers           # See what containers exist"
    echo "  $0 analyze comfyui      # Analyze specific container"
    echo "  $0 interactive          # Full interactive analysis"
    echo
    echo "What this finds:"
    echo "  ✅ Models that loaded successfully"
    echo "  ❌ Models that failed (VRAM, format, etc.)"
    echo "  ❓ Models with no evidence of use"
    echo "  💥 Specific error messages and causes"
}

# Main execution
print_banner

case "${1:-interactive}" in
    "containers")
        find_relevant_containers
        ;;
    "analyze")
        if [ -z "$2" ]; then
            echo "Please specify container name: $0 analyze CONTAINER_NAME"
            exit 1
        fi
        analyze_container_logs "$2"
        ;;
    "interactive")
        interactive_log_analysis
        ;;
    "recent")
        check_recent_activity
        ;;
    "cross-ref")
        cross_reference_with_filesystem
        ;;
    "report")
        generate_cleanup_report
        ;;
    "help"|*)
        show_help
        ;;
esac
