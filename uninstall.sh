#!/bin/sh
# Uninstaller for mudi-em120k-patch (restores stock GL-E750 V2 files)

set -eu

DESTDIR="${DESTDIR:-}"
BACKUP_DIR="${DESTDIR}/etc/em120k-fix/backups"

log() {
    printf '[uninstall] %s\n' "$*"
}

if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
    printf '[uninstall][err] Please run as root.\n' >&2
    exit 1
fi

if [ -z "$DESTDIR" ] && [ -x /etc/init.d/em120k-fix ]; then
    log "Disabling /etc/init.d/em120k-fix..."
    /etc/init.d/em120k-fix disable 2>/dev/null || true
fi

rm -f \
    "${DESTDIR}/usr/bin/em120k-fix" \
    "${DESTDIR}/etc/init.d/em120k-fix" \
    "${DESTDIR}/etc/hotplug.d/usb/25_em120k_fix.sh" \
    "${DESTDIR}/lib/upgrade/keep.d/em120k-fix"

if [ -f "${BACKUP_DIR}/tuning_switch_control.orig" ]; then
    log "Restoring original /usr/bin/tuning_switch_control..."
    cp "${BACKUP_DIR}/tuning_switch_control.orig" "${DESTDIR}/usr/bin/tuning_switch_control"
    chmod 755 "${DESTDIR}/usr/bin/tuning_switch_control"
fi

rm -rf "${DESTDIR}/etc/em120k-fix"

log "Uninstall complete. Stock GL-E750 V2 files restored."
