#!/bin/bash
# ---------------------------------------------------------------------------
# entrypoint.sh — Railway VPS-like Environment
#
# Runs once per container start (fresh deploy, restart, or crash recovery).
# No systemd is used or assumed: this script IS the container's PID 1 logic,
# and it ends by exec-ing sshd in the foreground so Docker/Railway can see
# and manage the real server process directly (correct restart handling).
# ---------------------------------------------------------------------------
set -euo pipefail

SSH_USERNAME="${SSH_USERNAME:-pajar}"
HOME_DIR="/home/${SSH_USERNAME}"
SSH_DIR="${HOME_DIR}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"
LISTEN_PORT="${PORT:-22}"

log() {
    echo "[entrypoint] $(date -u '+%Y-%m-%dT%H:%M:%SZ') - $*"
}

log "========================================================"
log " Railway VPS-like Environment — starting up"
log " This is a Debian 12 Docker container, not a real VPS/KVM."
log "========================================================"
log "User            : ${SSH_USERNAME}"
log "Listen port     : ${LISTEN_PORT} (from \$PORT, Railway-managed)"
log "Timezone        : $(cat /etc/timezone 2>/dev/null || echo UTC)"
log "Node.js         : $(node -v 2>/dev/null || echo 'not found')"
log "PHP             : $(php -v 2>/dev/null | head -n1 || echo 'not found')"
log "Python          : $(python3 -V 2>/dev/null || echo 'not found')"

# ---------------------------------------------------------------------------
# 1. Require a public key. We never bake credentials into the image, and we
#    refuse to boot an SSH server that nobody can actually unlock.
# ---------------------------------------------------------------------------
if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
    log "FATAL: SSH_PUBLIC_KEY environment variable is not set."
    log "       Set it in Railway → Variables, to your public key"
    log "       (e.g. the contents of ~/.ssh/id_ed25519.pub from Termux)."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Persistent storage: if a Railway Volume is mounted on $HOME_DIR, this
#    directory (and anything the user puts in it) survives redeploys.
#    We (re)create .ssh and authorized_keys every boot so a key rotation
#    in Railway's dashboard takes effect on the next restart.
# ---------------------------------------------------------------------------
mkdir -p "${SSH_DIR}"
printf '%s\n' "${SSH_PUBLIC_KEY}" > "${AUTH_KEYS}"
chmod 700 "${SSH_DIR}"
chmod 600 "${AUTH_KEYS}"
chown -R "${SSH_USERNAME}:${SSH_USERNAME}" "${HOME_DIR}"
log "authorized_keys written for ${SSH_USERNAME} ($(wc -l < "${AUTH_KEYS}") key line(s))"

# ---------------------------------------------------------------------------
# 3. Render sshd_config from the template (Port comes from Railway's $PORT,
#    which varies per-deploy/per-proxy — it cannot be hardcoded at build time)
# ---------------------------------------------------------------------------
sed -e "s/__PORT__/${LISTEN_PORT}/g" \
    -e "s/__SSH_USERNAME__/${SSH_USERNAME}/g" \
    /etc/ssh/sshd_config.template > /etc/ssh/sshd_config

# Privilege-separation directory; not persisted by systemd-tmpfiles here
# since there's no systemd, so we ensure it ourselves on every boot.
mkdir -p /run/sshd

# Defensive: host keys are normally baked in at image build time (see
# Dockerfile). If they're ever missing at runtime, generate them so the
# container can still start rather than crash-looping.
if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    log "No SSH host keys found, generating now (unexpected after a normal build)"
    ssh-keygen -A
fi

# Validate the rendered config before handing control to sshd.
if ! /usr/sbin/sshd -t -f /etc/ssh/sshd_config; then
    log "FATAL: sshd_config failed validation, see errors above."
    exit 1
fi

log "sshd configuration OK, listening on 0.0.0.0:${LISTEN_PORT}"
log "Ready. Connect from Termux with:"
log "  ssh -p ${LISTEN_PORT} ${SSH_USERNAME}@<railway-tcp-proxy-host>"
log "========================================================"

# ---------------------------------------------------------------------------
# 4. Hand off to sshd in the foreground (-D) with logs to stderr (-e), so
#    it becomes PID 1's direct child / effectively PID 1 via exec. Railway
#    (Docker) then sees the real server process and can restart the
#    container correctly if it ever exits, with no systemd involved.
# ---------------------------------------------------------------------------
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
