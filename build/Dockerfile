FROM archlinux:latest

# Update system and install build tools
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git sudo wget jq gnupg

# Import Omarchy signing key into pacman keyring
RUN pacman-key --init && \
    pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org && \
    pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

# Create build user (required for makepkg - cannot run as root)
RUN useradd -m -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER builder
WORKDIR /src

# Setup GPG directory
RUN mkdir -p ~/.gnupg && chmod 700 ~/.gnupg

# Default command
CMD ["/build/build.sh"]
