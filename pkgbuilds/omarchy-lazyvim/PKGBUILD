# Maintainer: Ryan Hughes <ryan@omarchy.org>
pkgname=omarchy-lazyvim
pkgver=2025.08.29
pkgrel=1
pkgdesc="Pre-built LazyVim configuration with cached plugins"
arch=('any')
url="https://github.com/LazyVim/LazyVim"
license=('MIT')
depends=('neovim>=0.9.0' 'git')
makedepends=('git' 'nodejs' 'npm' 'tree-sitter-cli')
source=("git+https://github.com/LazyVim/starter.git")
sha256sums=('SKIP')

build() {
  cd "$srcdir"

  # Create isolated environment for building
  export HOME="$srcdir/build-home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CACHE_HOME="$HOME/.cache"

  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

  # Setup LazyVim starter
  cp -r "$srcdir/starter" "$XDG_CONFIG_HOME/nvim"
  rm -rf "$XDG_CONFIG_HOME/nvim/.git"

  # Copy our custom configs
  cp -r "$startdir/lua" "$XDG_CONFIG_HOME/nvim/"
  cp -r "$startdir/plugin" "$XDG_CONFIG_HOME/nvim/"
  cp "$startdir/lazyvim.json" "$XDG_CONFIG_HOME/nvim/"

  # Add custom option to disable relative numbers
  echo "vim.opt.relativenumber = false" >>"$XDG_CONFIG_HOME/nvim/lua/config/options.lua"

  # Prime LazyVim - download all plugins and TreeSitter parsers in one session
  # Run for minimum 60 seconds to ensure everything completes
  echo ":: Installing LazyVim plugins and TreeSitter parsers (minimum 60 seconds)..."
  nvim --headless \
    "+Lazy! sync" \
    "+qa!" || true
}

package() {
  cd "$srcdir"

  # Install everything to /usr/share/omarchy-lazyvim
  install -dm755 "$pkgdir/usr/share/$pkgname"

  # Copy all the built artifacts
  cp -a "$XDG_CONFIG_HOME/nvim" "$pkgdir/usr/share/$pkgname/config"
  cp -a "$XDG_DATA_HOME/nvim" "$pkgdir/usr/share/$pkgname/data"
  cp -a "$XDG_CACHE_HOME/nvim" "$pkgdir/usr/share/$pkgname/cache"

  # Fix permissions to be readable by all users
  chmod -R 755 "$pkgdir/usr/share/$pkgname"
  find "$pkgdir/usr/share/$pkgname" -type f -exec chmod 644 {} \;

  # Install setup script to /usr/bin
  install -Dm755 "$startdir/omarchy-lazyvim-setup" "$pkgdir/usr/bin/omarchy-lazyvim-setup"
}
