#!/bin/bash
# wan21-model-analyzer.sh
# Analyze WAN21 models for AMD RX 6800M compatibility and find redundancies

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "          WAN21 Model Analyzer for AMD RX 6800M"
    echo "     Find what you need vs what's wasting 172GB of space"
    echo "=================================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[ANALYSIS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_keep() {
    echo -e "${GREEN}[KEEP]${NC} $1"
}

print_remove() {
    echo -e "${RED}[REMOVE]${NC} $1"
}

print_maybe() {
    echo -e "${YELLOW}[MAYBE]${NC} $1"
}

analyze_hardware_compatibility() {
    print_status "AMD RX 6800M Hardware Analysis..."
    echo

    echo -e "${CYAN}Your Hardware Specs:${NC}"
    echo "  GPU: AMD RX 6800M"
    echo "  Architecture: RDNA2 (gfx1031)"
    echo "  VRAM: 12GB GDDR6"
    echo "  Compute Units: 40"
    echo "  Max Memory Bandwidth: 384 GB/s"
    echo

    echo -e "${CYAN}WAN21 Model Requirements Analysis:${NC}"
    echo "  🟢 Models that should work well (≤8GB VRAM):"
    echo "     • WAN2.1 T2V 1.3B models (text-to-video, small)"
    echo "     • FP16/FP8 quantized versions"
    echo "     • 480p resolution models"
    echo
    echo "  🟡 Models that might work (8-12GB VRAM):"
    echo "     • WAN2.1 I2V 14B models IF heavily quantized (FP8)"
    echo "     • With significant CPU offloading"
    echo
    echo "  🔴 Models that likely WON'T work (>12GB VRAM):"
    echo "     • WAN2.1 I2V 14B in BF16/FP16 format"
    echo "     • Unquantized large models"
    echo "     • Multiple models loaded simultaneously"
    echo
}

scan_wan21_models() {
    local wan21_dir="wan21-models"

    if [ ! -d "$wan21_dir" ]; then
        print_warning "wan21-models directory not found"
        return 1
    fi

    print_status "Scanning WAN21 models directory..."
    echo

    # Initialize counters
    local total_size=0
    local model_count=0
    local duplicate_count=0
    local oversized_count=0

    echo -e "${BLUE}=== MODEL INVENTORY ===${NC}"

    # Analyze .safetensors files
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file=$(basename "$file")

            model_count=$((model_count + 1))
            total_size=$((total_size + size_bytes))

            # Analyze model characteristics
            local model_type=""
            local precision=""
            local size_category=""
            local compatibility=""

            # Determine model type
            if [[ "$basename_file" == *"t2v"* ]]; then
                model_type="Text-to-Video"
            elif [[ "$basename_file" == *"i2v"* ]]; then
                model_type="Image-to-Video"
            else
                model_type="Unknown"
            fi

            # Determine precision
            if [[ "$basename_file" == *"bf16"* ]]; then
                precision="BF16 (high precision)"
            elif [[ "$basename_file" == *"fp16"* ]]; then
                precision="FP16 (medium precision)"
            elif [[ "$basename_file" == *"fp8"* ]]; then
                precision="FP8 (low precision, AMD optimized)"
            else
                precision="Unknown"
            fi

            # Determine size category and compatibility
            if (( $(echo "$size_gb < 4" | bc -l) )); then
                size_category="Small"
                compatibility="🟢 Should work great"
            elif (( $(echo "$size_gb < 8" | bc -l) )); then
                size_category="Medium"
                compatibility="🟢 Should work well"
            elif (( $(echo "$size_gb < 12" | bc -l) )); then
                size_category="Large"
                compatibility="🟡 Might work with optimization"
                oversized_count=$((oversized_count + 1))
            else
                size_category="Very Large"
                compatibility="🔴 Likely too big for 12GB VRAM"
                oversized_count=$((oversized_count + 1))
            fi

            echo -e "\n📁 ${basename_file}"
            echo "   Size: ${size_gb}GB ($size_category)"
            echo "   Type: $model_type"
            echo "   Precision: $precision"
            echo "   Compatibility: $compatibility"
            echo "   Path: $file"
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)

    # Summary
    local total_size_gb=$(echo "scale=1; $total_size/1024/1024/1024" | bc -l 2>/dev/null || echo "0")

    echo -e "\n${CYAN}=== INVENTORY SUMMARY ===${NC}"
    echo "  Total models found: $model_count"
    echo "  Total size: ${total_size_gb}GB"
    echo "  Models too big for your GPU: $oversized_count"
    echo "  Estimated wasted space: $(echo "scale=0; $oversized_count * 10" | bc -l 2>/dev/null || echo "?")GB+"
}

identify_duplicates_and_redundancies() {
    local wan21_dir="wan21-models"

    print_status "Identifying duplicates and redundancies..."
    echo

    echo -e "${BLUE}=== DUPLICATE ANALYSIS ===${NC}"

    # Find models with same base name but different precisions
    declare -A model_families

    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local basename_file=$(basename "$file")
            local base_name=""

            # Extract base model name (remove precision suffixes)
            base_name=$(echo "$basename_file" | sed -E 's/_?(bf16|fp16|fp8|fp8_e4m3fn)\.safetensors$//' | sed -E 's/\.safetensors$//')

            if [ -n "${model_families[$base_name]}" ]; then
                model_families[$base_name]="${model_families[$base_name]}|$file"
            else
                model_families[$base_name]="$file"
            fi
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)

    # Analyze each model family
    for base_name in "${!model_families[@]}"; do
        local files_list="${model_families[$base_name]}"
        local file_count=$(echo "$files_list" | tr '|' '\n' | wc -l)

        if [ "$file_count" -gt 1 ]; then
            echo -e "\n🔍 Model Family: ${base_name}"
            echo "   Multiple versions found ($file_count files):"

            local total_family_size=0
            local recommended_file=""
            local recommended_size=999999

            echo "$files_list" | tr '|' '\n' | while read -r file; do
                if [ -f "$file" ]; then
                    local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
                    local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
                    local basename_file=$(basename "$file")

                    # Determine recommendation
                    local recommendation=""
                    if [[ "$basename_file" == *"fp8"* ]]; then
                        recommendation="🟢 BEST for AMD (smallest, optimized)"
                        if (( $(echo "$size_gb < $recommended_size" | bc -l) )); then
                            recommended_file="$file"
                            recommended_size="$size_gb"
                        fi
                    elif [[ "$basename_file" == *"fp16"* ]]; then
                        recommendation="🟡 GOOD (medium size, good quality)"
                    elif [[ "$basename_file" == *"bf16"* ]]; then
                        recommendation="🔴 LARGEST (probably unnecessary)"
                    else
                        recommendation="❓ Unknown format"
                    fi

                    echo "     • $basename_file (${size_gb}GB) - $recommendation"
                fi
            done

            echo "   💡 Recommendation: Keep only the FP8 version if it works for you"
            echo "   💾 Potential savings: Keep smallest, remove others"
        fi
    done
}

create_cleanup_recommendations() {
    local wan21_dir="wan21-models"

    print_status "Creating cleanup recommendations..."
    echo

    local report_file="wan21-cleanup-recommendations-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$report_file" << EOF
# WAN21 Model Cleanup Recommendations for AMD RX 6800M
# Generated: $(date)
# Your GPU: AMD RX 6800M (12GB VRAM)

## RECOMMENDED TO KEEP (Optimized for your hardware):

EOF

    echo -e "${GREEN}=== RECOMMENDATIONS ===${NC}"
    echo
    echo -e "${GREEN}✅ DEFINITELY KEEP:${NC}"

    # Find recommended models
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file=$(basename "$file")

            # Recommend based on size and format
            if (( $(echo "$size_gb < 6" | bc -l) )) && [[ "$basename_file" == *"fp8"* ]]; then
                print_keep "$basename_file (${size_gb}GB) - Optimized for AMD"
                echo "# KEEP: $file (${size_gb}GB) - AMD optimized" >> "$report_file"
            elif (( $(echo "$size_gb < 4" | bc -l) )) && [[ "$basename_file" == *"t2v"* ]] && [[ "$basename_file" == *"1.3B"* ]]; then
                print_keep "$basename_file (${size_gb}GB) - Small T2V model"
                echo "# KEEP: $file (${size_gb}GB) - Fits in VRAM" >> "$report_file"
            fi
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)

    echo
    echo -e "${YELLOW}⚠️  CONSIDER REMOVING:${NC}"

    cat >> "$report_file" << EOF

## CONSIDER REMOVING (Likely won't work well on your hardware):

EOF

    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file=$(basename "$file")

            # Flag for removal based on size and format
            if (( $(echo "$size_gb > 10" | bc -l) )); then
                print_remove "$basename_file (${size_gb}GB) - Too big for 12GB VRAM"
                echo "# REMOVE: $file (${size_gb}GB) - Too big" >> "$report_file"
            elif [[ "$basename_file" == *"bf16"* ]] && (( $(echo "$size_gb > 6" | bc -l) )); then
                print_remove "$basename_file (${size_gb}GB) - BF16 format unnecessary"
                echo "# REMOVE: $file (${size_gb}GB) - BF16 redundant" >> "$report_file"
            elif [[ "$basename_file" == *"14B"* ]] && [[ "$basename_file" == *"fp16"* ]]; then
                print_maybe "$basename_file (${size_gb}GB) - Large model, might work with CPU offload"
                echo "# MAYBE: $file (${size_gb}GB) - Test if works" >> "$report_file"
            fi
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)

    cat >> "$report_file" << EOF

## CLEANUP COMMANDS (Review before running):
# Backup first: cp -r wan21-models wan21-models-backup

EOF

    echo
    echo "📋 Detailed recommendations saved to: $report_file"
}

estimate_space_savings() {
    local wan21_dir="wan21-models"

    print_status "Estimating potential space savings..."
    echo

    local total_size=0
    local removable_size=0
    local keep_size=0

    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file=$(basename "$file")

            total_size=$((total_size + size_bytes))

            # Categorize for removal
            if (( $(echo "$size_gb > 10" | bc -l) )) ||
               [[ "$basename_file" == *"bf16"* && $(echo "$size_gb > 6" | bc -l) ]]; then
                removable_size=$((removable_size + size_bytes))
            else
                keep_size=$((keep_size + size_bytes))
            fi
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)

    local total_gb=$(echo "scale=1; $total_size/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
    local removable_gb=$(echo "scale=1; $removable_size/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
    local keep_gb=$(echo "scale=1; $keep_size/1024/1024/1024" | bc -l 2>/dev/null || echo "0")

    echo -e "${CYAN}=== SPACE SAVINGS ESTIMATE ===${NC}"
    echo "  Current total: ${total_gb}GB"
    echo "  Recommended to keep: ${keep_gb}GB"
    echo "  Safe to remove: ${removable_gb}GB"
    echo "  Space savings: $(echo "scale=0; $removable_gb * 100 / $total_gb" | bc -l 2>/dev/null || echo "?")%"
    echo

    if (( $(echo "$removable_gb > 50" | bc -l) )); then
        echo -e "  ${GREEN}🎉 Excellent! You can free up ${removable_gb}GB${NC}"
        echo -e "  ${GREEN}   This should solve your disk space issue!${NC}"
    elif (( $(echo "$removable_gb > 20" | bc -l) )); then
        echo -e "  ${YELLOW}👍 Good! You can free up ${removable_gb}GB${NC}"
        echo -e "  ${YELLOW}   This will help significantly with disk space${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Limited savings: ${removable_gb}GB${NC}"
        echo -e "  ${YELLOW}   May need to look at other cleanup options too${NC}"
    fi
}

interactive_model_review() {
    local wan21_dir="wan21-models"

    echo -e "\n${BLUE}=== INTERACTIVE MODEL REVIEW ===${NC}"
    echo "Let's go through your models and decide what to keep..."
    echo

    print_warning "This will show you each large model and let you decide"
    print_warning "No files will be deleted without your explicit confirmation"
    echo

    read -p "Start interactive review? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local size_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_gb=$(echo "scale=1; $size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
            local basename_file=$(basename "$file")

            # Only review large files
            if (( $(echo "$size_gb > 3" | bc -l) )); then
                echo -e "\n📁 Reviewing: ${basename_file}"
                echo "   Size: ${size_gb}GB"
                echo "   Path: $file"

                # Provide recommendation
                if (( $(echo "$size_gb > 10" | bc -l) )); then
                    echo "   🔴 Recommendation: REMOVE (too big for 12GB VRAM)"
                elif [[ "$basename_file" == *"bf16"* ]]; then
                    echo "   🟡 Recommendation: REMOVE (BF16 format uses more VRAM)"
                elif [[ "$basename_file" == *"fp8"* ]]; then
                    echo "   🟢 Recommendation: KEEP (FP8 optimized for AMD)"
                else
                    echo "   🟡 Recommendation: REVIEW (test if it works)"
                fi

                echo "   Options:"
                echo "     k) Keep this model"
                echo "     r) Mark for removal"
                echo "     s) Skip (decide later)"
                echo "     q) Quit review"

                read -p "   Decision (k/r/s/q): " -n 1 -r
                echo

                case $REPLY in
                    k|K) echo "   ✅ Marked to KEEP" ;;
                    r|R) echo "   ❌ Marked for REMOVAL" ;;
                    s|S) echo "   ⏭️  Skipped" ;;
                    q|Q) echo "   Quitting review"; break ;;
                    *) echo "   Invalid option, skipping" ;;
                esac
            fi
        fi
    done < <(find "$wan21_dir" -name "*.safetensors" -type f -print0 2>/dev/null)
}

show_help() {
    echo "WAN21 Model Analyzer for AMD RX 6800M"
    echo
    echo "Analyzes your 172GB of WAN21 models to identify:"
    echo "• Which models will work on your 12GB VRAM GPU"
    echo "• Redundant formats and duplicates"
    echo "• Potential space savings"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  analyze      Complete analysis of all models"
    echo "  scan         Quick scan and inventory"
    echo "  duplicates   Find duplicate/redundant models"
    echo "  recommend    Create cleanup recommendations"
    echo "  interactive  Interactive model review"
    echo "  help         Show this help"
    echo
    echo "Example workflow:"
    echo "  $0 analyze      # See what you have"
    echo "  $0 interactive  # Review each model"
    echo "  # Then use safe cleanup tools to remove unwanted models"
}

# Main execution
print_banner

case "${1:-analyze}" in
    "analyze")
        analyze_hardware_compatibility
        scan_wan21_models
        identify_duplicates_and_redundancies
        create_cleanup_recommendations
        estimate_space_savings
        ;;
    "scan")
        scan_wan21_models
        ;;
    "duplicates")
        identify_duplicates_and_redundancies
        ;;
    "recommend")
        create_cleanup_recommendations
        estimate_space_savings
        ;;
    "interactive")
        analyze_hardware_compatibility
        interactive_model_review
        ;;
    "help"|*)
        show_help
        ;;
esac
