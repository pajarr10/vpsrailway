# syntax=docker/dockerfile:1
#
# Railway VPS-like Environment (Debian 12 + SSH) — for Termux access
# ---------------------------------------------------------------
# This is a container that behaves like a small Linux dev box you can
# SSH into. It is NOT a real VPS / KVM machine: no kernel of its own,
# no systemd, no privileged access to the host. It runs as an ordinary
# (unprivileged) Docker container, which is exactly what Railway gives you.

FROM debian:12-slim

LABEL maintainer="pajar" \
      description="Debian 12 minimal SSH dev container for Railway, accessed from Termux"

ARG SSH_USERNAME=pajar
ENV SSH_USERNAME=${SSH_USERNAME} \
    DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ---------------------------------------------------------------------------
# 1. Base packages
#    - openssh-server : SSH access
#    - sudo           : non-root user with admin rights
#    - python3/pip    : Python runtime
#    - php            : Debian 12 "bookworm" ships PHP 8.2 by default
#    - git curl wget nano htop unzip zip ca-certificates gnupg : everyday tools
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server \
        sudo \
        python3 \
        python3-pip \
        python3-venv \
        php-cli \
        php-common \
        git \
        curl \
        wget \
        nano \
        htop \
        unzip \
        zip \
        ca-certificates \
        gnupg \
        tzdata \
        procps \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. Node.js 20 LTS via NodeSource (Debian 12's built-in repo only has v18)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node -v && npm -v

# ---------------------------------------------------------------------------
# 3. Timezone: UTC, fixed
# ---------------------------------------------------------------------------
RUN ln -sf /usr/share/zoneinfo/UTC /etc/localtime \
    && echo "UTC" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

# ---------------------------------------------------------------------------
# 4. Non-root user with sudo, bash shell, no password (key-only login)
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash -G sudo "${SSH_USERNAME}" \
    && passwd -l "${SSH_USERNAME}" \
    && echo "${SSH_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${SSH_USERNAME} \
    && chmod 0440 /etc/sudoers.d/90-${SSH_USERNAME} \
    && mkdir -p /home/${SSH_USERNAME}/.ssh \
    && chmod 700 /home/${SSH_USERNAME}/.ssh \
    && chown -R ${SSH_USERNAME}:${SSH_USERNAME} /home/${SSH_USERNAME}

# ---------------------------------------------------------------------------
# 5. SSH server hardening
#    - generate host keys at BUILD time (stay stable across plain restarts,
#      only rotate when the image is rebuilt/redeployed)
#    - no root login, no password login — public key only
# ---------------------------------------------------------------------------
RUN ssh-keygen -A \
    && mkdir -p /run/sshd

COPY sshd_config.template /etc/ssh/sshd_config.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Railway injects PORT; sshd will actually bind to it (see entrypoint.sh).
# 22 here is just a documented default/fallback for local `docker run`.
ENV PORT=22
EXPOSE 22

# sshd must start as root (to manage privilege separation / per-user
# sessions); it immediately drops privileges for the login shell itself.
# This does NOT require --privileged or any special Docker capability.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
