#!/bin/bash
# Build script for Ruby + Rails bundles
set -e

# Check required environment variables
if [[ -z "$RUBY_VERSION" ]]; then
  echo "Error: RUBY_VERSION environment variable is required"
  exit 1
fi

if [[ -z "$RAILS_VERSION" ]]; then
  echo "Error: RAILS_VERSION environment variable is required"
  exit 1
fi

if [[ -z "$ARCH" ]]; then
  echo "Error: ARCH environment variable is required"
  exit 1
fi

OUTPUT_DIR="/output/ruby/$ARCH"
mkdir -p "$OUTPUT_DIR"

echo "==> Ruby Bundle Builder"
echo "==> Ruby version: $RUBY_VERSION"
echo "==> Rails version: $RAILS_VERSION"
echo "==> Architecture: $ARCH"
echo "==> Output directory: $OUTPUT_DIR"

# Handle special Ruby versions
if [[ "$RUBY_VERSION" == "edge" ]]; then
  echo "==> Installing Ruby edge from git..."
  # mise can install Ruby from git
  mise install ruby@ref:master
  RUBY_INSTALL_VERSION="ref:master"
  TARBALL_VERSION="edge"
else
  echo "==> Installing Ruby $RUBY_VERSION..."
  mise install "ruby@$RUBY_VERSION"
  RUBY_INSTALL_VERSION="$RUBY_VERSION"
  TARBALL_VERSION="$RUBY_VERSION"
fi

# Activate Ruby
echo "==> Activating Ruby..."
mise use "ruby@$RUBY_INSTALL_VERSION"

# Verify Ruby is working
echo "==> Ruby version check:"
ruby --version

# Find the actual Ruby installation directory
if [[ "$RUBY_INSTALL_VERSION" == "ref:master" ]]; then
  # For edge builds, find the directory (it will have a hash name)
  RUBY_DIR=$(ls -d /mise/installs/ruby/ref-* | head -1 | xargs basename)
else
  RUBY_DIR="$RUBY_INSTALL_VERSION"
fi

# Set up gem paths for relocatable installation
export GEM_HOME="/mise/installs/ruby/$RUBY_DIR/lib/ruby/gems"
export GEM_PATH="$GEM_HOME"
export BUNDLE_PATH="$GEM_HOME"
mkdir -p "$GEM_HOME"

echo "==> Gem environment:"
echo "    GEM_HOME: $GEM_HOME"
echo "    GEM_PATH: $GEM_PATH"

# Install Rails
echo "==> Installing Rails $RAILS_VERSION..."
if [[ "$RAILS_VERSION" == "edge" ]]; then
  gem install rails --pre
  # Get the actual version installed
  RAILS_ACTUAL_VERSION=$(gem list rails | grep "^rails " | sed 's/rails (\(.*\))/\1/')
  TARBALL_RAILS_VERSION="edge-$RAILS_ACTUAL_VERSION"
else
  gem install rails --version "$RAILS_VERSION"
  TARBALL_RAILS_VERSION="$RAILS_VERSION"
fi

# Verify Rails is installed
echo "==> Rails version check:"
rails --version

# Generate a temporary Rails app to install default gems
echo "==> Generating temporary Rails app to install default gems..."
rails new temp_app --skip-git --skip-bundle
cd temp_app

# Install all the default gems to our GEM_HOME
bundle install

# Show installed gems count
echo "==> Installed gems:"
gem list | wc -l

# Clean up
cd /
rm -rf temp_app

# Create the tarball with proper naming
TARBALL_NAME="ruby-${TARBALL_VERSION}-rails-${TARBALL_RAILS_VERSION}-${ARCH}.tar.gz"
TARBALL_PATH="$OUTPUT_DIR/$TARBALL_NAME"

echo "==> Creating tarball: $TARBALL_NAME"

# Create the tarball including Ruby binaries and all gems
echo "    Including Ruby installation and gems..."
tar -czf "$TARBALL_PATH" -C /mise/installs/ruby "$RUBY_DIR"

# Show file info
echo "==> Tarball created:"
ls -lh "$TARBALL_PATH"

echo "==> Build complete!"