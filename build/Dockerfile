FROM archlinux:latest

# Update system and install build tools
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm base-devel git sudo wget

# Create build user
RUN useradd -m -G wheel builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Create output directory
RUN mkdir -p /output && chown builder:builder /output

USER builder
WORKDIR /home/builder

# Copy package list
COPY --chown=builder:builder packages ./

# Copy build scripts
COPY --chown=builder:builder build-packages.sh ./
COPY --chown=builder:builder build-aur.sh ./

# Make scripts executable
RUN chmod +x build-packages.sh build-aur.sh

CMD ["./build-packages.sh"]
