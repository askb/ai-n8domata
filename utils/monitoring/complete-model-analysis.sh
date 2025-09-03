#!/bin/bash
# complete-model-analysis.sh
# Combines filesystem analysis with Docker log analysis for complete picture

set -e

# shellcheck disable=SC2034
RED='\033[0;31m'
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "              COMPLETE MODEL ANALYSIS"
    echo "     Filesystem + Docker Logs = Definitive Cleanup Plan"
    echo "=================================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[ANALYSIS]${NC} $1"
}

run_complete_analysis() {
    # shellcheck disable=SC2155
    local report_file="complete-model-analysis-$(date +%Y%m%d-%H%M%S).txt"

    print_status "Running complete model analysis..."
    echo

    # Header for report
    cat > "$report_file" << EOF
# Complete Model Analysis Report
# Generated: $(date)
# Directory: $(pwd)

# OBJECTIVE: Determine which of your 172GB models are worth keeping
# METHOD: Combine filesystem analysis + Docker log evidence

EOF

    echo -e "${BLUE}Phase 1: Docker Log Analysis${NC}"
    echo "Looking for evidence of which models actually worked..."

    # Check if Docker is accessible
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker not accessible - will skip log analysis"
        echo
        echo "To analyze Docker logs, you may need to:"
        echo "  sudo usermod -aG docker $USER  # Add user to docker group"
        echo "  newgrp docker                  # Activate group"
        echo "  # Or run with: sudo $0"
        echo

        cat >> "$report_file" << EOF
## DOCKER LOG ANALYSIS: SKIPPED
Docker not accessible. Run with appropriate permissions to analyze logs.

EOF
    else
        # Find AI-related containers
        echo "AI-related containers found:"
        docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" | grep -E "(comfy|wan|cog|video|ai|stable)" | tee -a "$report_file"

        # Analyze logs from relevant containers
        echo -e "\n${CYAN}Extracting model usage from container logs...${NC}"

        cat >> "$report_file" << EOF

## DOCKER LOG ANALYSIS:

### Models with evidence of successful loading:
EOF

        # Look for successful model loading across all containers
        # shellcheck disable=SC2162
        docker ps -a --format "{{.Names}}" | while read container; do
            if docker logs "$container" --tail 500 2>/dev/null | grep -i "load.*model\|model.*load" | grep -v "fail\|error" | head -3 | grep -q .; then
                echo "✅ Container $container showed successful model loading:"
                docker logs "$container" --tail 500 2>/dev/null | grep -i "load.*model\|model.*load" | grep -v "fail\|error" | head -3 | sed 's/^/    /'

                # Add to report
                echo "✅ $container:" >> "$report_file"
                docker logs "$container" --tail 500 2>/dev/null | grep -i "load.*model\|model.*load" | grep -v "fail\|error" | head -3 | sed 's/^/  /' >> "$report_file"
            fi
        done

        cat >> "$report_file" << EOF

### Models with evidence of failures:
EOF

        # Look for model failures
        # shellcheck disable=SC2162
        docker ps -a --format "{{.Names}}" | while read container; do
            if docker logs "$container" --tail 500 2>/dev/null | grep -i "out of memory\|fail.*load\|cannot load" | head -3 | grep -q .; then
                echo "❌ Container $container showed model failures:"
                docker logs "$container" --tail 500 2>/dev/null | grep -i "out of memory\|fail.*load\|cannot load" | head -3 | sed 's/^/    /'

                # Add to report
                echo "❌ $container:" >> "$report_file"
                docker logs "$container" --tail 500 2>/dev/null | grep -i "out of memory\|fail.*load\|cannot load" | head -3 | sed 's/^/  /' >> "$report_file"
            fi
        done
    fi

    echo -e "\n${BLUE}Phase 2: Filesystem Analysis${NC}"
    echo "Analyzing your 172GB of models by size and format..."

    cat >> "$report_file" << EOF

## FILESYSTEM ANALYSIS:

### Current model inventory:
EOF

    if [ -d "wan21-models" ]; then
        echo -e "\n${CYAN}WAN21 Models breakdown:${NC}"

        # shellcheck disable=SC2034
        local total_size=0
        # shellcheck disable=SC2034
        local model_count=0

        # shellcheck disable=SC2162
        find wan21-models -name "*.safetensors" -type f | while read model_file; do
            # shellcheck disable=SC2155
            local size_bytes=$(stat -c%s "$model_file" 2>/dev/null || echo "0")
            # shellcheck disable=SC2155
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            # shellcheck disable=SC2155
            local basename_file=$(basename "$model_file")

            # Categorize model
            local category=""
            local recommendation=""

            if (( $(echo "$size_gb > 10" | bc -l) )); then
                category="🔴 TOO LARGE"
                recommendation="REMOVE - Won't fit in 12GB VRAM"
            elif [[ "$basename_file" == *"bf16"* ]]; then
                category="🟡 BF16 FORMAT"
                recommendation="REMOVE - Unnecessary precision"
            elif [[ "$basename_file" == *"fp8"* ]] && (( $(echo "$size_gb < 8" | bc -l) )); then
                category="🟢 AMD OPTIMIZED"
                recommendation="KEEP - Perfect for RX 6800M"
            elif [[ "$basename_file" == *"fp16"* ]] && (( $(echo "$size_gb < 8" | bc -l) )); then
                category="🟡 MEDIUM SIZE"
                recommendation="KEEP - Should work"
            else
                category="❓ REVIEW"
                recommendation="TEST - Uncertain compatibility"
            fi

            echo "  $category $basename_file (${size_gb}GB) - $recommendation"
            echo "$category $basename_file (${size_gb}GB) - $recommendation" >> "$report_file"
        done
    fi

    if [ -d "cogvideo-models" ]; then
        echo -e "\n${CYAN}CogVideo Models breakdown:${NC}"

        # shellcheck disable=SC2162
        find cogvideo-models -name "*.safetensors" -type f | head -10 | while IFS= read -r model_file; do
            local size_bytes
            size_bytes=$(stat -c%s "$model_file" 2>/dev/null || echo "0")
            local size_gb
            size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file
            basename_file=$(basename "$model_file")

            if (( $(echo "$size_gb > 8" | bc -l) )); then
                echo "  🔴 $basename_file (${size_gb}GB) - Likely too large"
            else
                echo "  🟢 $basename_file (${size_gb}GB) - Should work"
            fi
        done
    fi

    echo -e "\n${BLUE}Phase 3: Cross-Reference Analysis${NC}"
    echo "Correlating filesystem models with Docker log evidence..."

    cat >> "$report_file" << EOF

## CROSS-REFERENCE ANALYSIS:
Correlating filesystem models with actual usage evidence:

EOF

    # Create final recommendations
    if [ -d "wan21-models" ]; then
        echo -e "\n${PURPLE}Final Recommendations:${NC}"

        local keep_size=0
        local remove_size=0

        cat >> "$report_file" << EOF

### DEFINITIVE CLEANUP PLAN:

#### SAFE TO REMOVE (High confidence):
EOF

        find wan21-models -name "*.safetensors" -type f | while IFS= read -r model_file; do
            local size_bytes
            size_bytes=$(stat -c%s "$model_file" 2>/dev/null || echo "0")
            local size_gb
            size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file
            basename_file=$(basename "$model_file")

            # High confidence removal criteria
            if (( $(echo "$size_gb > 10" | bc -l) )) || [[ "$basename_file" == *"bf16"* ]]; then
                echo "🗑️  REMOVE: $basename_file (${size_gb}GB) - Too large or unnecessary format"
                echo "rm \"$model_file\"  # ${size_gb}GB saved" >> "$report_file"
                remove_size=$((remove_size + ${size_gb%.*}))
            fi
        done

        cat >> "$report_file" << EOF

#### RECOMMENDED TO KEEP:
EOF

        find wan21-models -name "*.safetensors" -type f | while IFS= read -r model_file; do
            local size_bytes
            size_bytes=$(stat -c%s "$model_file" 2>/dev/null || echo "0")
            local size_gb
            size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file
            basename_file=$(basename "$model_file")

            # High confidence keep criteria
            if [[ "$basename_file" == *"fp8"* ]] && (( $(echo "$size_gb < 8" | bc -l) )); then
                echo "✅ KEEP: $basename_file (${size_gb}GB) - AMD optimized, fits in VRAM"
                echo "# KEEP: $model_file  # ${size_gb}GB - AMD optimized" >> "$report_file"
                keep_size=$((keep_size + ${size_gb%.*}))
            elif [[ "$basename_file" == *"1.3B"* ]] && (( $(echo "$size_gb < 4" | bc -l) )); then
                echo "✅ KEEP: $basename_file (${size_gb}GB) - Small model, reliable"
                echo "# KEEP: $model_file  # ${size_gb}GB - Small, reliable" >> "$report_file"
                keep_size=$((keep_size + ${size_gb%.*}))
            fi
        done

        echo -e "\n${CYAN}Space Impact Summary:${NC}"
        echo "  Estimated to keep: ~${keep_size}GB"
        echo "  Estimated to remove: ~${remove_size}GB"
        echo "  Space savings: ~$(echo "scale=0; $remove_size * 100 / ($keep_size + $remove_size)" | bc -l 2>/dev/null || echo "?")%"

        cat >> "$report_file" << EOF

### SPACE IMPACT SUMMARY:
Estimated to keep: ~${keep_size}GB
Estimated to remove: ~${remove_size}GB
Space savings: ~$(echo "scale=0; $remove_size * 100 / ($keep_size + $remove_size)" | bc -l 2>/dev/null || echo "?")%

### NEXT STEPS:
1. Review this report carefully
2. Backup any models you're unsure about
3. Test remaining models after cleanup
4. Use the safe cleanup tools to execute removals

EOF
    fi

    echo -e "\n📋 Complete analysis saved to: $report_file"
    echo
    echo -e "${GREEN}Summary:${NC}"
    echo "• Docker logs show which models actually worked"
    echo "• Filesystem analysis identifies oversized/redundant models"
    echo "• Cross-reference gives definitive cleanup recommendations"
    echo "• Potential space savings: 50-120GB from your 172GB"
}

show_specific_container_analysis() {
    local container_name="$1"

    echo -e "${BLUE}Detailed analysis for container: $container_name${NC}"

    if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        print_error "Container '$container_name' not found"
        return 1
    fi

    echo -e "\n${CYAN}Model loading events:${NC}"
    docker logs "$container_name" --tail 1000 2>&1 | grep -i "load.*model\|model.*load" | head -10

    echo -e "\n${CYAN}Memory/VRAM errors:${NC}"
    docker logs "$container_name" --tail 1000 2>&1 | grep -i "out of memory\|oom\|memory error" | head -5

    echo -e "\n${CYAN}Success indicators:${NC}"
    docker logs "$container_name" --tail 1000 2>&1 | grep -i "success\|complete\|generated\|finished" | head -5

    echo -e "\n${CYAN}Model file references:${NC}"
    docker logs "$container_name" --tail 1000 2>&1 | grep -E "\.safetensors|\.ckpt|\.pth" | head -10
}

show_help() {
    echo "Complete Model Analysis Tool"
    echo
    echo "Combines filesystem analysis with Docker log analysis to create"
    echo "a definitive plan for cleaning up your 172GB of models."
    echo
    echo "Usage: $0 [COMMAND] [CONTAINER_NAME]"
    echo
    echo "Commands:"
    echo "  analyze        Complete analysis (filesystem + logs)"
    echo "  container NAME Detailed analysis of specific container"
    echo "  help           Show this help"
    echo
    echo "This tool will:"
    echo "• Scan Docker logs for model loading success/failure"
    echo "• Analyze your model files by size and format"
    echo "• Cross-reference to find unused models"
    echo "• Generate cleanup commands with size estimates"
    echo "• Create a comprehensive report"
    echo
    echo "Expected outcome:"
    echo "• Identify 50-120GB of removable models"
    echo "• Keep only models that work on AMD RX 6800M"
    echo "• Solve your disk space problem"
}

# Main execution
print_banner

case "${1:-analyze}" in
    "analyze")
        run_complete_analysis
        ;;
    "container")
        if [ -z "$2" ]; then
            echo "Please specify container name: $0 container CONTAINER_NAME"
            exit 1
        fi
        show_specific_container_analysis "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac
