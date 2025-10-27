# Common path variables for Omarchy package build system
# This file should be sourced after setting BUILD_ROOT

# Default architecture
ARCH=${ARCH:-x86_64}

# Core directories (architecture-independent)
BUILD_DIR="$BUILD_ROOT/build"
SRC_DIR="$BUILD_ROOT/src"
LOG_DIR="$BUILD_ROOT/logs"
PKGBUILDS_DIR="$BUILD_ROOT/pkgbuilds"

# Function to update architecture-specific paths
# Call this after changing ARCH variable
update_arch_paths() {
  BUILD_OUTPUT_DIR="$BUILD_ROOT/build-output/$ARCH"        # Unsigned packages
  REPO_DIR="$BUILD_ROOT/pkgs.omarchy.org/$ARCH"            # Repository (signed packages)
}

# Initialize architecture-specific directories with default ARCH
update_arch_paths
