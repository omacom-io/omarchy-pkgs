# ==============================================================================
# Omarchy Package Builder - Multi-Architecture
# Supports: x86_64 (Arch Linux) and aarch64 (Arch Linux ARM)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Bootstrap - Create base Arch/ALARM system from scratch
# ------------------------------------------------------------------------------
FROM docker.io/alpine:3.21 AS bootstrapper

ARG TARGETARCH
ARG BUILDPLATFORM
ARG MIRROR=edge

COPY pacstrap-docker /usr/local/bin/

RUN apk add --no-cache \
    pacman-makepkg \
    curl \
    bash \
    zstd \
    gnupg

# Map Docker TARGETARCH (amd64/arm64) to Arch naming (x86_64/aarch64)
RUN case "${TARGETARCH}" in \
    amd64) \
        echo "x86_64" > /tmp/arch && \
        printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n' > /tmp/repos.conf ;; \
    arm64) \
        echo "aarch64" > /tmp/arch && \
        printf '[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n[alarm]\nInclude = /etc/pacman.d/mirrorlist\n\n[aur]\nInclude = /etc/pacman.d/mirrorlist\n' > /tmp/repos.conf ;; \
    *) \
        echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac

RUN mkdir -p /etc/pacman.d && \
    cat /tmp/repos.conf >> /etc/pacman.conf

RUN if [ "${TARGETARCH}" = "amd64" ]; then \
        if [ "${MIRROR}" = "stable" ]; then \
            printf 'Server = https://stable-mirror.omarchy.org/$repo/os/$arch\n' > /etc/pacman.d/mirrorlist; \
        else \
            printf 'Server = https://mirror.omarchy.org/$repo/os/$arch\n' > /etc/pacman.d/mirrorlist; \
        fi; \
    else \
        curl -L "https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/pacman-mirrorlist/mirrorlist" 2>/dev/null | \
            sed -E 's/^\s*#\s*Server\s*=/Server =/g' > /etc/pacman.d/mirrorlist && \
        sed -i 's/\$arch/aarch64/g' /etc/pacman.d/mirrorlist; \
    fi

# Bootstrap keyrings (required before pacstrap can verify packages)
RUN mkdir -p /usr/share/pacman/keyrings && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        KEYRING_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/master/core/archlinuxarm-keyring/" && \
        for file in archlinuxarm-revoked archlinuxarm-trusted archlinuxarm.gpg; do \
            curl -fsSL "${KEYRING_URL}${file}" -o /usr/share/pacman/keyrings/${file} || exit 1; \
        done && \
        BOOTSTRAP_EXTRA="archlinuxarm-keyring"; \
    else \
        mkdir /tmp/archlinux-keyring && \
        curl -fsSL https://archlinux.org/packages/core/any/archlinux-keyring/download | \
            unzstd | tar -C /tmp/archlinux-keyring -xv && \
        mv /tmp/archlinux-keyring/usr/share/pacman/keyrings/* /usr/share/pacman/keyrings/ && \
        BOOTSTRAP_EXTRA=""; \
    fi && \
    pacman-key --init && \
    pacman-key --populate

RUN mkdir /rootfs && \
    if [ "${TARGETARCH}" = "arm64" ]; then \
        BOOTSTRAP_EXTRA="archlinuxarm-keyring"; \
    else \
        BOOTSTRAP_EXTRA=""; \
    fi && \
    pacstrap-docker /rootfs base ${BOOTSTRAP_EXTRA} && \
    cp /etc/pacman.conf /rootfs/etc/pacman.conf && \
    cp /etc/pacman.d/mirrorlist /rootfs/etc/pacman.d/mirrorlist && \
    echo "en_US.UTF-8 UTF-8" > /rootfs/etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /rootfs/etc/locale.conf && \
    rm -rf /rootfs/var/lib/pacman/sync/* \
           /rootfs/var/cache/pacman/pkg/* \
           /rootfs/tmp/*

# ------------------------------------------------------------------------------
# Stage 2: Build Environment
# ------------------------------------------------------------------------------
FROM scratch AS builder

ARG TARGETARCH

COPY --from=bootstrapper /rootfs/ /

ENV LANG=en_US.UTF-8
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN ln -sf /usr/lib/os-release /etc/os-release && \
    locale-gen && \
    pacman-key --init && \
    if pacman -Q archlinuxarm-keyring >/dev/null 2>&1; then \
        pacman-key --populate archlinux archlinuxarm && \
        pacman-key --lsign-key 77193F152BDBE6A6; \
    else \
        pacman-key --populate archlinux; \
    fi

# Setup Omarchy keyring manually before adding repo (avoids keyserver trust issues)
# Note: Repository is removed at the end since build scripts add it dynamically
RUN pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org && \
    pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571 && \
    printf '\n[omarchy]\nSigLevel = Optional\nServer = https://pkgs.omarchy.org/$arch\n' >> /etc/pacman.conf && \
    pacman -Sy --noconfirm && \
    pacman -S --noconfirm omarchy-keyring && \
    pacman-key --populate omarchy && \
    sed -i '/^\[omarchy\]/,/^$/d' /etc/pacman.conf

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        base-devel \
        git \
        sudo \
        wget \
        curl \
        jq \
        gnupg && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

# makepkg cannot run as root
RUN useradd -m -G wheel -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    mkdir -p /home/builder/.gnupg && \
    chmod 700 /home/builder/.gnupg && \
    chown -R builder:builder /home/builder

RUN sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf && \
    sed -i 's/^COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q --threads=0 -)/' /etc/makepkg.conf

RUN rm -rf /etc/pacman.d/gnupg/{openpgp-revocs.d/,private-keys-v1.d/,pubring.gpg~,gnupg.S.}*

USER builder
WORKDIR /src

CMD ["/bin/bash"]

LABEL maintainer="Omarchy <https://omarchy.org>"
LABEL description="Multi-architecture Arch Linux package build environment"
LABEL version="2.0"
LABEL architectures="x86_64,aarch64"
