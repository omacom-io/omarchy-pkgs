#!/bin/bash
# Common printing functions for Omarchy scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Message printing functions
print_info() {
  echo -e "${BLUE}==>${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_step() {
  echo -e "  ${BLUE}→${NC} $1"
}

print_header() {
  echo -e "${BOLD}================================${NC}"
  echo -e "${BOLD}$1${NC}"
  echo -e "${BOLD}================================${NC}"
}

# Check Docker is available and running
check_docker() {
  if ! command -v docker &>/dev/null; then
    print_error "Docker is not installed"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    print_error "Docker daemon is not running"
    print_warning "Start Docker with: sudo systemctl start docker"
    exit 1
  fi
}

# Build the Docker image if needed
build_docker_image() {
  local build_dir="$1"
  print_info "Building Docker image..."
  docker build -t omarchy-aur-builder:latest -f "$build_dir/Dockerfile" "$build_dir"
}
