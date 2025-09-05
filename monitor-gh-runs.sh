#!/bin/bash
# monitor-gh-runs.sh
# Monitor GitHub Actions runs and show failure details

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "          GitHub Actions Run Monitor"
    echo "   Wait for runs to complete & show failures"
    echo "=================================================="
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_gh_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        print_error "GitHub CLI not authenticated. Run 'gh auth login' first."
        exit 1
    fi
}

get_in_progress_runs() {
    local repo="$1"
    gh run list --repo="$repo" --status=in_progress --json databaseId,status,conclusion,displayTitle,workflowName,headBranch,createdAt,url
}

get_run_details() {
    local repo="$1"
    local run_id="$2"
    gh run view "$run_id" --repo="$repo" --json databaseId,status,conclusion,displayTitle,workflowName,jobs,url
}

get_failed_job_logs() {
    local repo="$1"
    local run_id="$2"
    local job_id="$3"
    local job_name="$4"

    echo -e "\n${RED}=== FAILED JOB: $job_name ===${NC}"
    echo -e "${CYAN}Job ID: $job_id${NC}"
    echo -e "${CYAN}Fetching logs...${NC}\n"

    # Get the logs for the specific job
    gh run view "$run_id" --repo="$repo" --log --job="$job_id" 2>/dev/null || {
        print_warning "Could not fetch detailed logs for job $job_id"
        # Try alternative approach
        gh api "repos/$repo/actions/jobs/$job_id/logs" 2>/dev/null || {
            print_error "Failed to fetch logs for job $job_name"
        }
    }
}

wait_for_runs() {
    local repo="$1"
    local check_interval="${2:-30}"  # Default 30 seconds
    local max_wait="${3:-3600}"     # Default 1 hour

    print_status "Checking for in-progress runs in repository: $repo"

    local start_time
    start_time=$(date +%s)
    local runs_found=false

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -gt $max_wait ]; then
            print_warning "Maximum wait time ($max_wait seconds) exceeded"
            break
        fi

        # Get current in-progress runs
        local in_progress_runs
        in_progress_runs=$(get_in_progress_runs "$repo")

        if [ "$in_progress_runs" = "[]" ] || [ -z "$in_progress_runs" ]; then
            if [ "$runs_found" = true ]; then
                print_status "All runs completed!"
                break
            else
                print_status "No in-progress runs found"
                break
            fi
        fi

        runs_found=true
        local run_count
        run_count=$(echo "$in_progress_runs" | jq length)

        print_status "$run_count run(s) still in progress..."

        # Show current runs
        echo "$in_progress_runs" | jq -r '.[] | "  • " + .workflowName + " (" + .headBranch + ") - " + .displayTitle'

        print_status "Waiting $check_interval seconds... (${elapsed}s elapsed)"
        sleep "$check_interval"
    done

    # Now check for any recent failures
    check_recent_failures "$repo"
}

check_recent_failures() {
    local repo="$1"
    print_status "Checking for recent failures..."

    # Get recent completed runs and filter for failures
    local all_runs
    all_runs=$(gh run list --repo="$repo" --status=completed --limit=10 --json databaseId,conclusion,displayTitle,workflowName,headBranch,url,createdAt)

    local failed_runs
    failed_runs=$(echo "$all_runs" | jq '[.[] | select(.conclusion == "failure")] | .[0:5]')

    if [ "$failed_runs" = "[]" ] || [ -z "$failed_runs" ]; then
        print_status "No recent failures found! 🎉"
        return
    fi

    local failure_count
    failure_count=$(echo "$failed_runs" | jq length)
    print_error "Found $failure_count recent failure(s):"

    echo "$failed_runs" | jq -r '.[] | "  • " + .workflowName + " (" + .headBranch + ") - " + .displayTitle'

    echo
    read -r -p "Show detailed failure logs? (y/N): " show_logs

    if [[ $show_logs =~ ^[Yy]$ ]]; then
        show_failure_details "$repo" "$failed_runs"
    fi
}

show_failure_details() {
    local repo="$1"
    local failed_runs="$2"

    echo "$failed_runs" | jq -c '.[]' | while IFS= read -r run; do
        local run_id
        run_id=$(echo "$run" | jq -r '.databaseId')
        local workflow_name
        workflow_name=$(echo "$run" | jq -r '.workflowName')
        local display_title
        display_title=$(echo "$run" | jq -r '.displayTitle')
        local run_url
        run_url=$(echo "$run" | jq -r '.url')

        echo -e "\n${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}FAILED RUN: $workflow_name${NC}"
        echo -e "${CYAN}Title: $display_title${NC}"
        echo -e "${CYAN}URL: $run_url${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Get detailed run info
        local run_details
        run_details=$(get_run_details "$repo" "$run_id")

        # Extract failed jobs
        local failed_jobs
        failed_jobs=$(echo "$run_details" | jq -r '.jobs[] | select(.conclusion == "failure") | {id: .databaseId, name: .name}')

        if [ -n "$failed_jobs" ]; then
            echo "$failed_jobs" | jq -c '.' | while IFS= read -r job; do
                local job_id
                job_id=$(echo "$job" | jq -r '.id')
                local job_name
                job_name=$(echo "$job" | jq -r '.name')

                get_failed_job_logs "$repo" "$run_id" "$job_id" "$job_name"
            done
        else
            print_warning "No specific job failures found, showing general run logs..."
            gh run view "$run_id" --repo="$repo" --log
        fi

        echo -e "\n${CYAN}Full run details: $run_url${NC}\n"
    done
}

main() {
    print_banner

    # Parse arguments
    local repo=""
    local interval=30
    local max_wait=3600
    local help=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--repo)
                repo="$2"
                shift 2
                ;;
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            -w|--wait)
                max_wait="$2"
                shift 2
                ;;
            -h|--help)
                help=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                help=true
                shift
                ;;
        esac
    done

    if [ "$help" = true ]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Monitor GitHub Actions runs and show failure details"
        echo ""
        echo "Options:"
        echo "  -r, --repo REPO     Repository (owner/name, default: current repo)"
        echo "  -i, --interval SEC  Check interval in seconds (default: 30)"
        echo "  -w, --wait SEC      Maximum wait time in seconds (default: 3600)"
        echo "  -h, --help          Show this help"
        echo ""
        echo "Examples:"
        echo "  $0                                    # Monitor current repo"
        echo "  $0 -r owner/repo                     # Monitor specific repo"
        echo "  $0 -i 10 -w 1800                    # Check every 10s, max 30min"
        exit 0
    fi

    # Check GitHub CLI authentication
    check_gh_auth

    # Determine repository
    if [ -z "$repo" ]; then
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || {
                print_error "Could not determine repository. Use -r option or run in a git repository."
                exit 1
            })
        else
            print_error "Not in a git repository. Please specify repository with -r option."
            exit 1
        fi
    fi

    print_status "Monitoring repository: $repo"
    print_status "Check interval: ${interval}s, Max wait: ${max_wait}s"
    echo

    # Start monitoring
    wait_for_runs "$repo" "$interval" "$max_wait"
}

# Run main function with all arguments
main "$@"
