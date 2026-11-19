#!/bin/sh
# Installer for mudi-em120k-patch (GL.iNet GL-E750 V2 + Quectel EM120K-GL)
# Safe, idempotent, BusyBox ash compatible. Supports DESTDIR for staged testing.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DESTDIR="${DESTDIR:-}"
BACKUP_DIR="${DESTDIR}/etc/em120k-fix/backups"
SKIP_APPLY=0

for arg in "$@"; do
    case "$arg" in
        --no-apply) SKIP_APPLY=1 ;;
        -h|--help)
            printf 'Usage: %s [--no-apply]\n' "$0"
            exit 0
            ;;
    esac
done

log() {
    printf '[install] %s\n' "$*"
}

if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    printf '[install][err] Please run as root on the GL-E750 V2 router.\n' >&2
    exit 1
fi

log "Installing em120k-fix files into ${DESTDIR:-/}..."

mkdir -p \
    "${DESTDIR}/usr/bin" \
    "${DESTDIR}/etc/init.d" \
    "${DESTDIR}/etc/hotplug.d/usb" \
    "${DESTDIR}/lib/upgrade/keep.d" \
    "$BACKUP_DIR"

cp "${SCRIPT_DIR}/files/usr/bin/em120k-fix" "${DESTDIR}/usr/bin/em120k-fix"
chmod 755 "${DESTDIR}/usr/bin/em120k-fix"

cp "${SCRIPT_DIR}/files/etc/init.d/em120k-fix" "${DESTDIR}/etc/init.d/em120k-fix"
chmod 755 "${DESTDIR}/etc/init.d/em120k-fix"

cp "${SCRIPT_DIR}/files/etc/hotplug.d/usb/25_em120k_fix.sh" "${DESTDIR}/etc/hotplug.d/usb/25_em120k_fix.sh"
chmod 755 "${DESTDIR}/etc/hotplug.d/usb/25_em120k_fix.sh"

cp "${SCRIPT_DIR}/files/lib/upgrade/keep.d/em120k-fix" "${DESTDIR}/lib/upgrade/keep.d/em120k-fix"
chmod 644 "${DESTDIR}/lib/upgrade/keep.d/em120k-fix"

# Patch /usr/bin/tuning_switch_control to add *EM120KGL* support for RF antenna tuning
TUNING_SCRIPT="${DESTDIR}/usr/bin/tuning_switch_control"
if [ -f "$TUNING_SCRIPT" ]; then
    if ! grep -q '\*EM120KGL\*' "$TUNING_SCRIPT"; then
        if [ ! -f "${BACKUP_DIR}/tuning_switch_control.orig" ]; then
            cp "$TUNING_SCRIPT" "${BACKUP_DIR}/tuning_switch_control.orig"
        fi
        log "Patching ${TUNING_SCRIPT} to support *EM120KGL* antenna band tuning..."
        awk '
            /\*EM060KGL\*/ {
                print "    *EM120KGL*|\\"
            }
            { print }
        ' "$TUNING_SCRIPT" > "${TUNING_SCRIPT}.tmp"
        mv "${TUNING_SCRIPT}.tmp" "$TUNING_SCRIPT"
        chmod 755 "$TUNING_SCRIPT"
    else
        log "${TUNING_SCRIPT} already supports *EM120KGL*; skipping."
    fi
else
    log "Note: ${TUNING_SCRIPT} not present; skipping antenna tuning patch."
fi

if [ -z "$DESTDIR" ]; then
    if [ -x /etc/init.d/em120k-fix ]; then
        log "Enabling /etc/init.d/em120k-fix boot service..."
        /etc/init.d/em120k-fix enable
    fi

    if [ "$SKIP_APPLY" -eq 0 ]; then
        log "Applying EM120K-GL fix now..."
        /usr/bin/em120k-fix apply || true
        /usr/bin/em120k-fix status || true
    fi
fi

log "Installation complete."
