#!/bin/bash
# cleanup-testcontainers.sh
# Script to clean up all Testcontainers containers and resources

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Testcontainers Cleanup Script ===${NC}"
echo ""

# Function to check if Docker is running
check_docker() {
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}Error: Docker is not running or not accessible${NC}"
        exit 1
    fi
}

# Function to list Testcontainers
list_testcontainers() {
    echo -e "${YELLOW}Listing Testcontainers...${NC}"
    local containers=$(docker ps -a --filter "label=org.testcontainers=true" --format "{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}")
    
    if [ -z "$containers" ]; then
        echo -e "${GREEN}No Testcontainers found${NC}"
        return 0
    fi
    
    echo "$containers"
    echo ""
}

# Function to stop Ryuk
stop_ryuk() {
    echo -e "${YELLOW}Stopping Ryuk containers...${NC}"
    local ryuk_containers=$(docker ps -q --filter "name=testcontainers-ryuk")
    
    if [ -n "$ryuk_containers" ]; then
        echo "$ryuk_containers" | xargs docker rm -f
        echo -e "${GREEN}Ryuk containers stopped${NC}"
    else
        echo -e "${GREEN}No Ryuk containers found${NC}"
    fi
    echo ""
}

# Function to remove Kind containers
remove_kind_containers() {
    echo -e "${YELLOW}Removing Kind containers...${NC}"
    local kind_containers=$(docker ps -aq --filter "label=org.testcontainers=true")
    
    if [ -n "$kind_containers" ]; then
        echo "$kind_containers" | xargs docker rm -f
        echo -e "${GREEN}Kind containers removed${NC}"
    else
        echo -e "${GREEN}No Kind containers found${NC}"
    fi
    echo ""
}

# Function to remove temporary images
remove_temp_images() {
    echo -e "${YELLOW}Removing temporary images...${NC}"
    
    # Remove images with 'test' in the name
    local test_images=$(docker images --filter "reference=*test*" -q 2>/dev/null | sort -u)
    
    if [ -n "$test_images" ]; then
        echo "$test_images" | xargs -r docker rmi -f 2>/dev/null || true
        echo -e "${GREEN}Temporary test images removed${NC}"
    else
        echo -e "${GREEN}No temporary test images found${NC}"
    fi
    
    # Remove kindest/images if requested
    if [ "$1" = "--deep" ]; then
        echo -e "${YELLOW}Removing Kind images (deep clean)...${NC}"
        local kind_images=$(docker images --filter "reference=kindest/*" -q 2>/dev/null | sort -u)
        
        if [ -n "$kind_images" ]; then
            echo "$kind_images" | xargs -r docker rmi -f 2>/dev/null || true
            echo -e "${GREEN}Kind images removed${NC}"
        fi
    fi
    echo ""
}

# Function to clean networks
clean_networks() {
    echo -e "${YELLOW}Cleaning unused networks...${NC}"
    docker network prune -f > /dev/null 2>&1
    echo -e "${GREEN}Networks cleaned${NC}"
    echo ""
}

# Function to clean volumes
clean_volumes() {
    if [ "$1" = "--deep" ]; then
        echo -e "${YELLOW}Cleaning unused volumes (deep clean)...${NC}"
        docker volume prune -f > /dev/null 2>&1
        echo -e "${GREEN}Volumes cleaned${NC}"
    fi
    echo ""
}

# Function to show final status
show_status() {
    echo -e "${YELLOW}=== Final Status ===${NC}"
    
    local total_containers=$(docker ps -a --filter "label=org.testcontainers=true" -q | wc -l)
    local running_containers=$(docker ps --filter "label=org.testcontainers=true" -q | wc -l)
    
    echo "Testcontainers remaining: $total_containers"
    echo "Running: $running_containers"
    
    if [ "$total_containers" -eq 0 ]; then
        echo -e "${GREEN}Cleanup complete!${NC}"
    else
        echo -e "${YELLOW}Some containers remain. Try running with --deep flag${NC}"
    fi
}

# Main execution
main() {
    check_docker
    
    case "$1" in
        --list|-l)
            list_testcontainers
            ;;
        --deep|-d)
            list_testcontainers
            stop_ryuk
            remove_kind_containers
            remove_temp_images --deep
            clean_networks
            clean_volumes --deep
            show_status
            ;;
        --help|-h)
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Options:"
            echo "  --list, -l    List Testcontainers without removing"
            echo "  --deep, -d    Deep clean including Kind images and volumes"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Without options, performs standard cleanup"
            ;;
        *)
            list_testcontainers
            stop_ryuk
            remove_kind_containers
            remove_temp_images
            clean_networks
            show_status
            ;;
    esac
}

main "$@"
