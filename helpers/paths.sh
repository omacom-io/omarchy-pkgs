# Common path variables for Omarchy package build system
# This file should be sourced after setting BUILD_ROOT

# Every script that knows these paths is a script that can mutate them, so the
# mutex travels with them. Sourcing only defines acquire_repo_lock; each entry
# point decides when to call it.
source "$BUILD_ROOT/helpers/lock-helpers.sh"

# Default architecture and mirror
ARCH=${ARCH:-x86_64}
MIRROR=${MIRROR:-edge}

# Core directories (architecture-independent)
BUILD_DIR="$BUILD_ROOT/build"
SRC_DIR="$BUILD_ROOT/src"
LOG_DIR="$BUILD_ROOT/logs"
PKGBUILDS_DIR="$BUILD_ROOT/pkgbuilds"

# Function to update architecture and mirror-specific paths
# Call this after changing ARCH or MIRROR variables
update_arch_paths() {
  BUILD_OUTPUT_DIR="$BUILD_ROOT/build-output/$MIRROR/$ARCH"        # Unsigned packages
  REPO_DIR="$BUILD_ROOT/pkgs.omarchy.org/$MIRROR/$ARCH"            # Repository (signed packages)
}

# Initialize architecture-specific directories with default ARCH and MIRROR
update_arch_paths
