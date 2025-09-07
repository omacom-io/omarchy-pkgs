FROM archlinux:base-devel

# Update packages and install dependencies for mise and Ruby compilation
RUN pacman -Syu --noconfirm --needed git curl sudo ca-certificates openssl zlib libyaml libffi readline ncurses base-devel \
    && pacman -Scc --noconfirm

# Set mise environment variables for a consistent, container-friendly path
ENV MISE_DATA_DIR=/mise
ENV MISE_CONFIG_DIR=/mise
ENV MISE_CACHE_DIR=/mise/cache
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
ENV PATH=/mise/shims:$PATH

# Install mise
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl https://mise.run | sh

# Set Ruby build options for relocatable/portable compilation
ENV MISE_RUBY_BUILD_OPTS="--enable-load-relative --with-static-linked-ext"

# Install Ruby 3.4.5
RUN mise install ruby@3.4.5

# Activate Ruby and install Rails
RUN mise use ruby@3.4.5
RUN gem install rails --version 8.0.2.1

# Generate a temporary Rails app to install default gems
RUN rails new temp_app \
    && rm -rf temp_app

# Create a single tarball with Ruby and all gems
RUN tar -czf /ruby-3.4.5-rails-8.0.2.1.tar.gz -C /mise/installs/ruby 3.4.5
