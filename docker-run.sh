#!/bin/bash

# Script to build and run Docker containers for both frontend and backend
# Usage: ./docker-run.sh [--build] [--stop] [--logs] [--clean]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BACKEND_DIR="${SCRIPT_DIR}/backend"
FRONTEND_DIR="${SCRIPT_DIR}/frontend"

# Functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop and try again."
        exit 1
    fi
}

# Stop all containers
stop_containers() {
    print_info "Stopping all containers..."
    cd "${BACKEND_DIR}/docker"
    docker-compose down 2>/dev/null || true
    cd "${FRONTEND_DIR}"
    docker-compose down 2>/dev/null || true
    print_success "All containers stopped"
}

# Clean up containers, volumes, and images
clean_all() {
    print_info "Cleaning up Docker resources..."
    stop_containers
    
    print_info "Removing containers..."
    docker rm -f rloco-backend rloco-frontend-dev rloco-mongodb rloco-storage 2>/dev/null || true
    
    print_info "Removing volumes..."
    docker volume rm backend_docker_mongodb_data backend_docker_minio_data 2>/dev/null || true
    
    print_info "Removing images..."
    docker rmi rloco-backend rloco-frontend-dev 2>/dev/null || true
    
    print_success "Cleanup complete"
}

# Show logs
show_logs() {
    print_info "Showing logs (Ctrl+C to exit)..."
    cd "${BACKEND_DIR}/docker"
    docker-compose logs -f backend mongodb minio &
    BACKEND_LOGS_PID=$!
    
    cd "${FRONTEND_DIR}"
    docker-compose logs -f frontend &
    FRONTEND_LOGS_PID=$!
    
    # Wait for user interrupt
    trap "kill $BACKEND_LOGS_PID $FRONTEND_LOGS_PID 2>/dev/null; exit" INT TERM
    wait
}

# Build and start backend
start_backend() {
    print_info "Starting backend services (MongoDB, MinIO, Backend)..."
    cd "${BACKEND_DIR}/docker"
    
    if [ "$BUILD" = true ]; then
        print_info "Building backend image..."
        docker-compose build --no-cache backend
    fi
    
    print_info "Starting backend containers..."
    docker-compose up -d
    
    # Wait for services to be healthy
    print_info "Waiting for MongoDB to be ready..."
    timeout=60
    elapsed=0
    while ! docker-compose exec -T mongodb mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            print_error "MongoDB failed to start within ${timeout}s"
            exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    print_success "MongoDB is ready"
    
    print_info "Waiting for MinIO to be ready..."
    timeout=60
    elapsed=0
    while ! docker-compose exec -T minio curl -f http://localhost:9000/minio/health/live > /dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            print_error "MinIO failed to start within ${timeout}s"
            exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    print_success "MinIO is ready"
    
    print_info "Waiting for backend API to be ready..."
    timeout=60
    elapsed=0
    # Try health endpoint first, then fallback to products endpoint
    while ! curl -f http://localhost:8080/health > /dev/null 2>&1 && ! curl -f http://localhost:8080/api/products?limit=1 > /dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Backend API may not be ready yet. Check logs with: ./docker-run.sh --logs"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    print_success "Backend is ready"
}

# Build and start frontend
start_frontend() {
    print_info "Starting frontend service..."
    cd "${FRONTEND_DIR}"
    
    if [ "$BUILD" = true ]; then
        print_info "Building frontend image..."
        docker-compose build --no-cache frontend
    fi
    
    print_info "Starting frontend container..."
    docker-compose up -d
    
    # Wait for frontend to be ready
    print_info "Waiting for frontend to be ready..."
    timeout=60
    elapsed=0
    while ! curl -f http://localhost:5173 > /dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Frontend may not be ready yet. Check logs with: ./docker-run.sh --logs"
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    echo ""
    print_success "Frontend is ready"
}

# Parse arguments
BUILD=false
STOP=false
LOGS=false
CLEAN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=true
            shift
            ;;
        --stop)
            STOP=true
            shift
            ;;
        --logs)
            LOGS=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Usage: $0 [--build] [--stop] [--logs] [--clean]"
            echo ""
            echo "Options:"
            echo "  --build    Force rebuild of Docker images"
            echo "  --stop     Stop all containers"
            echo "  --logs     Show logs from all containers"
            echo "  --clean    Stop and remove all containers, volumes, and images"
            exit 1
            ;;
    esac
done

# Check Docker
check_docker

# Handle special commands
if [ "$CLEAN" = true ]; then
    clean_all
    exit 0
fi

if [ "$STOP" = true ]; then
    stop_containers
    exit 0
fi

if [ "$LOGS" = true ]; then
    show_logs
    exit 0
fi

# Main execution
print_info "=========================================="
print_info "  Rloco Docker Setup"
print_info "=========================================="
echo ""

# Stop existing containers if they're running
print_info "Checking for existing containers..."
stop_containers

# Start backend first (includes MongoDB and MinIO)
start_backend

echo ""
print_info "Waiting 5 seconds before starting frontend..."
sleep 5

# Start frontend
start_frontend

echo ""
print_success "=========================================="
print_success "  All services are running!"
print_success "=========================================="
echo ""
print_info "Backend API:  http://localhost:8080/api"
print_info "Frontend:     http://localhost:5173 (Docker: VITE_API_URL forced to local API above)"
print_info "MongoDB:      localhost:28017"
print_info "MinIO Console: http://localhost:9001 (minioadmin/minioadmin)"
echo ""
print_info "Useful commands:"
print_info "  View logs:    ./docker-run.sh --logs"
print_info "  Stop all:     ./docker-run.sh --stop"
print_info "  Clean all:    ./docker-run.sh --clean"
print_info "  Rebuild:      ./docker-run.sh --build"
echo ""
