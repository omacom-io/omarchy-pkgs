# Docker helper functions for Omarchy package build system

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

build_docker_image() {
  local build_dir="$1"
  local arch="${2:-x86_64}"
  local platform=""
  local image_tag="omarchy-pkg-builder:latest-$arch"
  
  case "$arch" in
    x86_64)  platform="linux/amd64" ;;
    aarch64) platform="linux/arm64" ;;
    *)
      print_error "Unsupported architecture: $arch"
      exit 1
      ;;
  esac
  
  print_info "Building Docker image for $arch ($platform)..."
  
  docker buildx build \
    --platform "$platform" \
    --load \
    -t "$image_tag" \
    -f "$build_dir/Dockerfile" \
    "$build_dir"
}

make_dir_writable() {
  local dir="$1"
  if [ "$(id -u)" -eq 0 ]; then
    chmod -R 777 "$dir"
  else
    sudo chown -R $(id -u):$(id -g) "$dir" 2>/dev/null || chmod -R 777 "$dir"
  fi
}
