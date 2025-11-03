#!/bin/bash
set -e

# E2E Test Runner Script
# This script helps manage the E2E test environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_images() {
    print_info "Checking required Docker images..."
    local missing_images=0
    
    if ! docker image inspect rpingmesh-controller:latest >/dev/null 2>&1; then
        print_error "Missing image: rpingmesh-controller:latest"
        missing_images=$((missing_images + 1))
    fi
    
    if ! docker image inspect rpingmesh-analyzer:latest >/dev/null 2>&1; then
        print_error "Missing image: rpingmesh-analyzer:latest"
        missing_images=$((missing_images + 1))
    fi
    
    if ! docker image inspect rpingmesh-agent:latest >/dev/null 2>&1; then
        print_error "Missing image: rpingmesh-agent:latest"
        missing_images=$((missing_images + 1))
    fi
    
    if [ $missing_images -gt 0 ]; then
        print_error "Missing $missing_images required image(s)"
        print_info "Please build images first:"
        print_info "  cd ../agent-build && bash build.sh"
        print_info "  cd ../controller-build && bash build.sh"
        print_info "  cd ../analyzer-build && bash build.sh"
        return 1
    fi
    
    print_info "All required images are available"
    return 0
}

start_services() {
    print_info "Starting E2E test environment..."
    if ! check_images; then
        return 1
    fi
    
    docker compose up -d
    
    print_info "Waiting for services to be healthy..."
    sleep 5
    
    print_info "Service status:"
    docker compose ps
    
    print_info "E2E environment started"
    print_info "View logs with: docker compose logs -f"
}

stop_services() {
    print_info "Stopping E2E test environment..."
    docker compose down
    print_info "E2E environment stopped"
}

show_logs() {
    local service="${1:-}"
    if [ -z "$service" ]; then
        docker compose logs -f
    else
        docker compose logs -f "$service"
    fi
}

check_status() {
    print_info "Checking service status..."
    docker compose ps
    
    print_info "\nChecking service health..."
    
    # Check RQLite
    if docker compose exec -T rqlite wget -q --spider http://localhost:4001/status 2>/dev/null; then
        print_info "✓ RQLite is healthy"
    else
        print_warn "✗ RQLite may not be ready"
    fi
    
    # Check Controller
    if docker compose exec -T controller nc -zv localhost 50051 >/dev/null 2>&1; then
        print_info "✓ Controller is healthy"
    else
        print_warn "✗ Controller may not be ready"
    fi
    
    # Check Analyzer
    if docker compose exec -T analyzer nc -zv localhost 50052 >/dev/null 2>&1; then
        print_info "✓ Analyzer is healthy"
    else
        print_warn "✗ Analyzer may not be ready"
    fi
    
    # Check Agent registration
    print_info "\nChecking Agent status..."
    if docker compose logs agent 2>&1 | grep -q "Successfully registered"; then
        print_info "✓ Agent has registered with Controller"
    else
        print_warn "✗ Agent may not have registered yet"
    fi
    
    # Check Analyzer data reception
    if docker compose logs analyzer 2>&1 | grep -q "Received data upload"; then
        print_info "✓ Analyzer has received data from Agent"
    else
        print_warn "✗ Analyzer has not received data yet"
    fi
}

query_database() {
    print_info "Querying RQLite database..."
    docker compose exec -T rqlite rqlite -H localhost:4001 "SELECT * FROM rnics;" 2>/dev/null || {
        print_warn "Could not query database. Is RQLite running?"
    }
}

# Main command handler
case "${1:-help}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        stop_services
        sleep 2
        start_services
        ;;
    status)
        check_status
        ;;
    logs)
        show_logs "${2:-}"
        ;;
    query)
        query_database
        ;;
    clean)
        print_info "Cleaning up E2E environment..."
        docker compose down -v
        print_info "Cleanup complete"
        ;;
    help|--help|-h)
        echo "E2E Test Runner"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  start       Start all services"
        echo "  stop        Stop all services"
        echo "  restart     Restart all services"
        echo "  status      Check service status and health"
        echo "  logs [svc]  Show logs (optionally for specific service)"
        echo "  query       Query RQLite database"
        echo "  clean       Stop and remove all containers and volumes"
        echo "  help        Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 start              # Start all services"
        echo "  $0 logs agent         # Show agent logs"
        echo "  $0 status             # Check all services"
        ;;
    *)
        print_error "Unknown command: $1"
        echo "Run '$0 help' for usage information"
        exit 1
        ;;
esac

