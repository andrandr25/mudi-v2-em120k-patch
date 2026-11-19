#!/bin/sh
# USB hotplug hook for Quectel EM120K-GL on GL.iNet GL-E750 V2 (Mudi V2)
# Runs before 30_modem.sh to ensure RmNet/QMI mode (usbnet=0) and RF enablement.

[ "$ACTION" = "add" ] && [ "$DEVTYPE" = "usb_device" ] || exit 0
[ -x /usr/bin/em120k-fix ] || exit 0

VID_FILE="/sys${DEVPATH}/idVendor"
PID_FILE="/sys${DEVPATH}/idProduct"
[ -f "$VID_FILE" ] && [ -f "$PID_FILE" ] || exit 0

VID="$(cat "$VID_FILE" 2>/dev/null | tr -d ' \r\n')"
PID="$(cat "$PID_FILE" 2>/dev/null | tr -d ' \r\n')"

# Quectel VID 2c7c (EM060K/EM120K PID 030b, 030e)
case "${VID}:${PID}" in
    2c7c:030b|2c7c:030e)
        (/usr/bin/em120k-fix apply --no-verify >/dev/null 2>&1) &
        ;;
esac
