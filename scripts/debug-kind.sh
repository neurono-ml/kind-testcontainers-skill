#!/bin/bash
# debug-kind.sh
# Script for debugging Kind clusters and Testcontainers

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kind Debug Script ===${NC}"
echo ""

# Check if Docker is running
check_docker() {
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or not accessible${NC}"
        exit 1
    fi
}

# List all Kind/Testcontainers
list_containers() {
    echo -e "${YELLOW}=== All Testcontainers ===${NC}"
    
    docker ps -a --filter "label=org.testcontainers=true" --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}"
    echo ""
}

# Show container details
show_container_details() {
    local container_id=$1
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Container Details: $container_id ===${NC}"
    
    echo -e "${BLUE}Basic Info:${NC}"
    docker inspect "$container_id" --format '
ID: {{.Id}}
Image: {{.Config.Image}}
Created: {{.Created}}
Status: {{.State.Status}}
IP: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}
' 2>/dev/null || echo "Container not found"
    echo ""
    
    echo -e "${BLUE}Port Mappings:${NC}"
    docker port "$container_id" 2>/dev/null || echo "No port mappings"
    echo ""
    
    echo -e "${BLUE}Environment Variables:${NC}"
    docker inspect "$container_id" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | head -20
    echo ""
}

# Show container logs
show_logs() {
    local container_id=$1
    local tail=${2:-100}
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Logs for: $container_id (last $tail lines) ===${NC}"
    docker logs --tail "$tail" "$container_id" 2>&1
    echo ""
}

# Execute command in container
exec_in_container() {
    local container_id=$1
    shift
    local cmd="$@"
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    if [ -z "$cmd" ]; then
        echo -e "${RED}Error: Command required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Executing: $cmd ===${NC}"
    docker exec "$container_id" $cmd 2>&1
    echo ""
}

# Get kubeconfig from container
get_kubeconfig() {
    local container_id=$1
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Kubeconfig from: $container_id ===${NC}"
    docker exec "$container_id" cat /etc/kubernetes/admin.conf 2>/dev/null || echo "Could not read kubeconfig"
    echo ""
}

# Check Kubernetes nodes
check_nodes() {
    local container_id=$1
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Kubernetes Nodes ===${NC}"
    docker exec "$container_id" kubectl get nodes 2>/dev/null || echo "kubectl not available"
    echo ""
}

# Check Kubernetes pods
check_pods() {
    local container_id=$1
    local namespace=${2:-all}
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Kubernetes Pods ($namespace) ===${NC}"
    
    if [ "$namespace" = "all" ]; then
        docker exec "$container_id" kubectl get pods --all-namespaces 2>/dev/null || echo "kubectl not available"
    else
        docker exec "$container_id" kubectl get pods -n "$namespace" 2>/dev/null || echo "kubectl not available"
    fi
    echo ""
}

# Check Kubernetes events
check_events() {
    local container_id=$1
    local namespace=${2:-default}
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Kubernetes Events ($namespace) ===${NC}"
    docker exec "$container_id" kubectl get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null || echo "kubectl not available"
    echo ""
}

# Check Ryuk status
check_ryuk() {
    echo -e "${YELLOW}=== Ryuk Status ===${NC}"
    
    local ryuk_container=$(docker ps -q --filter "name=testcontainers-ryuk")
    
    if [ -n "$ryuk_container" ]; then
        echo -e "${GREEN}Ryuk is running${NC}"
        echo "Container ID: $ryuk_container"
        docker ps --filter "name=testcontainers-ryuk" --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
    else
        echo -e "${RED}Ryuk is not running${NC}"
    fi
    echo ""
}

# Full diagnostic
full_diagnostic() {
    local container_id=$1
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       FULL DIAGNOSTIC REPORT          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_docker
    
    echo -e "${YELLOW}System Information:${NC}"
    echo "Date: $(date)"
    echo "Docker Version: $(docker --version)"
    echo ""
    
    list_containers
    check_ryuk
    
    if [ -n "$container_id" ]; then
        show_container_details "$container_id"
        show_logs "$container_id" 50
        get_kubeconfig "$container_id"
        check_nodes "$container_id"
        check_pods "$container_id" "kube-system"
        check_events "$container_id" "kube-system"
    fi
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       END DIAGNOSTIC REPORT           ${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Watch container logs
watch_logs() {
    local container_id=$1
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Error: Container ID required${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}=== Following logs for: $container_id ===${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    docker logs -f "$container_id" 2>&1
}

# Help message
show_help() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                          List all Testcontainers"
    echo "  details <container_id>        Show container details"
    echo "  logs <container_id> [tail]    Show container logs (default: 100 lines)"
    echo "  watch <container_id>          Follow container logs"
    echo "  exec <container_id> <cmd>     Execute command in container"
    echo "  kubeconfig <container_id>     Get kubeconfig from container"
    echo "  nodes <container_id>          Check Kubernetes nodes"
    echo "  pods <container_id> [ns]      Check Kubernetes pods (default: all namespaces)"
    echo "  events <container_id> [ns]    Check Kubernetes events (default: default namespace)"
    echo "  ryuk                          Check Ryuk status"
    echo "  full [container_id]           Run full diagnostic"
    echo "  help                          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 logs abc123 200"
    echo "  $0 pods abc123 kube-system"
    echo "  $0 exec abc123 kubectl get ns"
    echo "  $0 full abc123"
}

# Main execution
main() {
    check_docker
    
    case "$1" in
        list)
            list_containers
            ;;
        details)
            show_container_details "$2"
            ;;
        logs)
            show_logs "$2" "${3:-100}"
            ;;
        watch)
            watch_logs "$2"
            ;;
        exec)
            shift 2
            exec_in_container "$2" "$@"
            ;;
        kubeconfig)
            get_kubeconfig "$2"
            ;;
        nodes)
            check_nodes "$2"
            ;;
        pods)
            check_pods "$2" "${3:-all}"
            ;;
        events)
            check_events "$2" "${3:-default}"
            ;;
        ryuk)
            check_ryuk
            ;;
        full)
            full_diagnostic "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [ -n "$1" ]; then
                echo -e "${RED}Unknown command: $1${NC}"
                echo ""
            fi
            show_help
            ;;
    esac
}

main "$@"
