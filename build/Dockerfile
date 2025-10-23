FROM archlinux:latest

# Update system and install build tools
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git sudo wget jq gnupg

# Create build user (required for makepkg)
# Note: UID/GID can be overridden at runtime via --build-arg
ARG BUILD_UID=1000
ARG BUILD_GID=1000

# Only create builder user if not using root (UID 0)
RUN if [ ${BUILD_UID} -ne 0 ]; then \
      groupadd -g ${BUILD_GID} builder && \
      useradd -m -u ${BUILD_UID} -g ${BUILD_GID} -G wheel builder && \
      echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers; \
    fi

# Switch to builder user if not root, otherwise stay as root
USER ${BUILD_UID}
WORKDIR /src

# Setup GPG directory for whichever user we're using
RUN mkdir -p ~/.gnupg && chmod 700 ~/.gnupg

# Default command
CMD ["/build/build.sh"]
