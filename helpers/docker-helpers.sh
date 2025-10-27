# Docker helper functions for Omarchy package build system

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

# Make directory writable by Docker container user
make_dir_writable() {
  local dir="$1"
  if [ "$(id -u)" -eq 0 ]; then
    chmod -R 777 "$dir"
  else
    sudo chown -R $(id -u):$(id -g) "$dir" 2>/dev/null || chmod -R 777 "$dir"
  fi
}

# Run a Docker container with standard setup
run_docker() {
  local script="$1"
  shift
  local -a args=("$@")
  
  docker run --rm "${args[@]}" omarchy-aur-builder:latest "$script"
}
