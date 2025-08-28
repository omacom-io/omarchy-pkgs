FROM archlinux:latest

# Update system and install build tools
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git sudo wget jq gnupg

# Create build user (required for makepkg)
RUN useradd -m -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER builder
WORKDIR /src

# Setup GPG directory
RUN mkdir -p ~/.gnupg && chmod 700 ~/.gnupg

# Default command
CMD ["/build/build.sh"]
