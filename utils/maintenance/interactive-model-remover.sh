#!/bin/bash
# interactive-model-remover.sh
# Safely remove models one by one with confirmation

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
    echo "           INTERACTIVE MODEL REMOVER"
    echo "     Ask permission before deleting each model file"
    echo "=================================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[SAFE]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_file_details() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        return 1
    fi

    local filename=$(basename "$file_path")
    local file_size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
    local file_size_human=$(du -sh "$file_path" 2>/dev/null | cut -f1 || echo "Unknown")
    local file_size_gb=$(echo "scale=1; $file_size_bytes/1024/1024/1024" | bc -l 2>/dev/null || echo "0")
    local last_modified=$(stat -c %y "$file_path" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")

    echo -e "\n${CYAN}📁 File Details:${NC}"
    echo "   Name: $filename"
    echo "   Size: $file_size_human (${file_size_gb}GB)"
    echo "   Path: $file_path"
    echo "   Modified: $last_modified"

    # Analyze what type of model this is
    local model_type=""
    local recommendation=""

    if [[ "$filename" == *"bf16"* ]]; then
        model_type="BF16 Precision Model"
        recommendation="🔴 REMOVE RECOMMENDED - BF16 uses more VRAM than necessary"
    elif [[ "$filename" == *"fp8"* ]]; then
        model_type="FP8 Quantized Model"
        recommendation="🟢 KEEP RECOMMENDED - FP8 optimized for AMD GPUs"
    elif [[ "$filename" == *"fp16"* ]]; then
        model_type="FP16 Precision Model"
        recommendation="🟡 REVIEW - Medium precision, should work"
    elif [[ "$filename" == *"14B"* ]] && (( $(echo "$file_size_gb > 8" | bc -l) )); then
        model_type="Large 14B Parameter Model"
        recommendation="🔴 REMOVE RECOMMENDED - Likely too big for 12GB VRAM"
    elif [[ "$filename" == *"1.3B"* ]]; then
        model_type="Small 1.3B Parameter Model"
        recommendation="🟢 KEEP RECOMMENDED - Small models work well"
    elif [[ "$filename" == diffusion_pytorch_model*.safetensors ]] && (( $(echo "$file_size_gb > 8" | bc -l) )); then
        model_type="Large Diffusion Model Segment"
        recommendation="🔴 REMOVE RECOMMENDED - Individual segments too large"
    else
        model_type="Unknown Model Type"
        recommendation="❓ MANUAL REVIEW - Examine before deciding"
    fi

    echo "   Type: $model_type"
    echo "   Recommendation: $recommendation"

    # Show directory context
    echo -e "\n${CYAN}📂 Directory Context:${NC}"
    local parent_dir=$(dirname "$file_path")
    echo "   Directory: $parent_dir"
    echo "   Other files in directory:"
    ls -lah "$parent_dir" | head -5 | sed 's/^/     /'
    if [ $(ls "$parent_dir" | wc -l) -gt 5 ]; then
        echo "     ... and $(($(ls "$parent_dir" | wc -l) - 5)) more files"
    fi
}

ask_for_confirmation() {
    local file_path="$1"
    local reason="$2"

    echo -e "\n${YELLOW}❓ DECISION TIME:${NC}"
    echo "   File: $(basename "$file_path")"
    echo "   Reason for removal: $reason"
    echo "   Size that will be freed: $(du -sh "$file_path" | cut -f1)"
    echo
    echo "   Options:"
    echo "     y) YES - Delete this file"
    echo "     n) NO - Keep this file"
    echo "     s) SKIP - Decide later"
    echo "     b) BACKUP - Copy to backup location first, then delete"
    echo "     q) QUIT - Stop the removal process"
    echo

    while true; do
        read -p "   Your choice (y/n/s/b/q): " -n 1 -r
        echo

        case $REPLY in
            y|Y)
                return 0  # Delete
                ;;
            n|N)
                echo "   ✅ File will be kept"
                return 1  # Keep
                ;;
            s|S)
                echo "   ⏭️  File skipped for now"
                return 2  # Skip
                ;;
            b|B)
                return 3  # Backup first
                ;;
            q|Q)
                echo "   🛑 Removal process stopped"
                return 99  # Quit
                ;;
            *)
                echo "   Invalid choice. Please enter y, n, s, b, or q"
                ;;
        esac
    done
}

backup_file() {
    local file_path="$1"
    local backup_dir="model-backups-$(date +%Y%m%d)"

    print_status "Creating backup of $(basename "$file_path")..."

    # Create backup directory
    mkdir -p "$backup_dir"

    # Copy file to backup
    if cp "$file_path" "$backup_dir/"; then
        echo "   ✅ Backup created: $backup_dir/$(basename "$file_path")"
        return 0
    else
        print_error "Failed to create backup"
        return 1
    fi
}

safe_delete_file() {
    local file_path="$1"

    print_status "Deleting $(basename "$file_path")..."

    # Double-check file exists
    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        return 1
    fi

    # Get size for reporting
    local freed_space=$(du -sh "$file_path" | cut -f1)

    # Delete the file
    if rm "$file_path"; then
        echo "   ✅ Deleted successfully"
        echo "   💾 Space freed: $freed_space"
        return 0
    else
        print_error "Failed to delete file"
        return 1
    fi
}

process_removal_candidates() {
    print_status "Processing models identified for removal..."
    echo

    # Based on the analysis, these are the candidates for removal
    local removal_candidates=(
        # BF16 models (unnecessary precision)
        "wan21-models/wan2.1_t2v_1.3B_bf16.safetensors"
        "wan21-models/wan2.1_i2v_480p_14B_bf16.safetensors"
        "wan21-models/text_encoders/umt5-xxl-enc-bf16.safetensors"

        # Large diffusion model segments (likely too big)
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00001-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00002-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00003-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00004-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00005-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00006-of-00007.safetensors"
        "wan21-models/diffusion_models/temp_wan_i2v/diffusion_pytorch_model-00007-of-00007.safetensors"
    )

    local total_candidates=${#removal_candidates[@]}
    local processed=0
    local deleted=0
    local kept=0
    local skipped=0
    local backed_up=0
    local total_space_freed=0

    echo "Found $total_candidates model files to review"
    echo

    for candidate in "${removal_candidates[@]}"; do
        processed=$((processed + 1))

        echo -e "${PURPLE}=== FILE $processed of $total_candidates ===${NC}"

        # Check if file exists
        if [ ! -f "$candidate" ]; then
            print_warning "File not found: $candidate (may have been moved or already deleted)"
            continue
        fi

        # Show file details
        show_file_details "$candidate"

        # Determine reason for removal
        local reason=""
        if [[ "$candidate" == *"bf16"* ]]; then
            reason="BF16 format uses unnecessary VRAM (FP16/FP8 versions are better)"
        elif [[ "$candidate" == *"diffusion_pytorch_model-"*"-of-00007"* ]]; then
            reason="Large model segment likely won't fit in 12GB VRAM"
        else
            reason="Identified as non-essential by analysis"
        fi

        # Ask for confirmation
        ask_for_confirmation "$candidate" "$reason"
        local choice=$?

        case $choice in
            0)  # Delete
                if safe_delete_file "$candidate"; then
                    deleted=$((deleted + 1))
                    # Note: would need to calculate space, but keeping simple for now
                fi
                ;;
            1)  # Keep
                kept=$((kept + 1))
                ;;
            2)  # Skip
                skipped=$((skipped + 1))
                ;;
            3)  # Backup first
                if backup_file "$candidate"; then
                    echo "   Now deleting original file..."
                    if safe_delete_file "$candidate"; then
                        deleted=$((deleted + 1))
                        backed_up=$((backed_up + 1))
                    fi
                else
                    print_error "Backup failed, keeping original file"
                    kept=$((kept + 1))
                fi
                ;;
            99) # Quit
                break
                ;;
        esac

        # Show progress
        echo -e "\n${BLUE}Progress: $processed/$total_candidates files reviewed${NC}"
        echo "  Deleted: $deleted | Kept: $kept | Skipped: $skipped | Backed up: $backed_up"

        # Ask if user wants to continue
        if [ $processed -lt $total_candidates ]; then
            echo
            read -p "Continue to next file? (Y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                echo "Stopping at user request"
                break
            fi
        fi
    done

    # Final summary
    echo -e "\n${GREEN}=== REMOVAL SUMMARY ===${NC}"
    echo "  Total files reviewed: $processed"
    echo "  Files deleted: $deleted"
    echo "  Files kept: $kept"
    echo "  Files skipped: $skipped"
    echo "  Files backed up: $backed_up"

    if [ $deleted -gt 0 ]; then
        echo -e "\n💾 Check your disk space:"
        df -h .
    fi

    if [ $backed_up -gt 0 ]; then
        echo -e "\n📁 Backup files are in: model-backups-$(date +%Y%m%d)/"
    fi
}

interactive_custom_removal() {
    print_status "Interactive custom file removal..."
    echo

    while true; do
        echo -e "${BLUE}Enter path to model file to review (or 'quit' to exit):${NC}"
        read -p "File path: " file_path

        if [ "$file_path" = "quit" ] || [ "$file_path" = "q" ]; then
            break
        fi

        if [ ! -f "$file_path" ]; then
            print_error "File not found: $file_path"
            continue
        fi

        show_file_details "$file_path"
        ask_for_confirmation "$file_path" "Manual review requested"
        local choice=$?

        case $choice in
            0)  # Delete
                safe_delete_file "$file_path"
                ;;
            1)  # Keep
                echo "File kept"
                ;;
            2)  # Skip
                echo "File skipped"
                ;;
            3)  # Backup first
                if backup_file "$file_path"; then
                    safe_delete_file "$file_path"
                fi
                ;;
            99) # Quit
                break
                ;;
        esac

        echo
    done
}

show_help() {
    echo "Interactive Model Remover"
    echo
    echo "Safely remove model files one by one with detailed confirmation."
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  auto       Process files identified by analysis (recommended)"
    echo "  custom     Manually specify files to review"
    echo "  help       Show this help"
    echo
    echo "Safety Features:"
    echo "• Shows detailed file information before each deletion"
    echo "• Asks for individual confirmation on each file"
    echo "• Option to backup files before deletion"
    echo "• Can quit at any time"
    echo "• Shows space freed after each deletion"
    echo
    echo "Based on your analysis, this will help you remove:"
    echo "• BF16 format models (unnecessary precision)"
    echo "• Large model segments that won't fit in 12GB VRAM"
    echo "• Duplicate model formats"
}

# Main execution
print_banner

case "${1:-auto}" in
    "auto")
        print_warning "This will review model files identified for removal"
        print_warning "You will be asked to confirm each deletion individually"
        echo
        read -p "Start interactive removal process? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            process_removal_candidates
        else
            echo "Removal cancelled"
        fi
        ;;
    "custom")
        interactive_custom_removal
        ;;
    "help"|*)
        show_help
        ;;
esac
