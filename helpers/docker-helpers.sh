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
  local arch="${2:-x86_64}"
  local dockerfile="$build_dir/Dockerfile.$arch"
  local platform=""
  local image_tag="omarchy-pkg-builder:latest-$arch"
  
  # Set platform for Docker build
  if [[ "$arch" == "aarch64" ]]; then
    platform="--platform linux/arm64"
  elif [[ "$arch" == "x86_64" ]]; then
    platform="--platform linux/amd64"
  fi
  
  print_info "Building Docker image for $arch..."
  docker build $platform -t "$image_tag" -f "$dockerfile" "$build_dir"
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
  local arch="${2:-x86_64}"
  shift 2
  local -a args=("$@")
  local image_tag="omarchy-pkg-builder:latest-$arch"
  local platform=""
  
  # Set platform for Docker run
  if [[ "$arch" == "aarch64" ]]; then
    platform="--platform linux/arm64"
  elif [[ "$arch" == "x86_64" ]]; then
    platform="--platform linux/amd64"
  fi
  
  docker run --rm $platform "${args[@]}" "$image_tag" "$script"
}
