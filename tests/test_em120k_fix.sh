#!/bin/sh
# Automated test suite for mudi-em120k-patch
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_BASE="$(mktemp -d /tmp/em120k-test.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0

pass() {
    PASS=$((PASS + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '[FAIL] %s\n' "$1" >&2
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label (expected='$expected', actual='$actual')"
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if grep -q -- "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label (pattern '$pattern' not found in $file)"
    fi
}

echo "=== 1. POSIX sh syntax checks ==="
for s in \
    "$REPO_DIR/files/usr/bin/em120k-fix" \
    "$REPO_DIR/files/etc/init.d/em120k-fix" \
    "$REPO_DIR/files/etc/hotplug.d/usb/25_em120k_fix.sh" \
    "$REPO_DIR/install.sh" \
    "$REPO_DIR/uninstall.sh"; do
    if sh -n "$s"; then
        pass "syntax OK: $(basename "$s")"
    else
        fail "syntax error: $s"
    fi
done

echo "=== 2. Staged install.sh / idempotency / uninstall.sh test ==="
STAGE="$TMP_BASE/stage"
mkdir -p "$STAGE/usr/bin"
cat <<'EOF' > "$STAGE/usr/bin/tuning_switch_control"
#!/bin/sh
case $version in
    *EM060KGL*|\
    *EM05*)
        echo "tuned"
        ;;
esac
EOF
cp "$STAGE/usr/bin/tuning_switch_control" "$TMP_BASE/tuning_orig"

DESTDIR="$STAGE" sh "$REPO_DIR/install.sh" --no-apply >/dev/null
assert_contains "$STAGE/usr/bin/tuning_switch_control" '\*EM120KGL\*' "install.sh adds *EM120KGL* to tuning_switch_control"
sh -n "$STAGE/usr/bin/tuning_switch_control" && pass "patched tuning_switch_control syntax OK" || fail "patched tuning_switch_control syntax error"

# Run install.sh a second time to verify idempotency
DESTDIR="$STAGE" sh "$REPO_DIR/install.sh" --no-apply >/dev/null
COUNT="$(grep -c '\*EM120KGL\*' "$STAGE/usr/bin/tuning_switch_control")"
assert_eq "$COUNT" "1" "install.sh is idempotent (no duplicate *EM120KGL*)"

# Uninstall and verify exact restoration
DESTDIR="$STAGE" sh "$REPO_DIR/uninstall.sh" >/dev/null
if cmp -s "$STAGE/usr/bin/tuning_switch_control" "$TMP_BASE/tuning_orig"; then
    pass "uninstall.sh restores exact original tuning_switch_control"
else
    fail "uninstall.sh did not restore original tuning_switch_control"
fi
[ ! -e "$STAGE/usr/bin/em120k-fix" ] && pass "uninstall.sh removes /usr/bin/em120k-fix" || fail "em120k-fix still present"

# Helper to build a mock OpenWrt environment
setup_mock_env() {
    local env_dir="$1"
    local init_usbnet="$2"
    local init_cfun="$3"

    rm -rf "$env_dir"
    mkdir -p \
        "$env_dir/bin" \
        "$env_dir/state" \
        "$env_dir/sys/bus/usb/devices/1-1.2" \
        "$env_dir/sys/class/net" \
        "$env_dir/sys/devices" \
        "$env_dir/dev" \
        "$env_dir/proc"

    printf '2c7c\n' > "$env_dir/sys/bus/usb/devices/1-1.2/idVendor"
    printf '030b\n' > "$env_dir/sys/bus/usb/devices/1-1.2/idProduct"
    printf '1-1.2\n' > "$env_dir/proc/build-in-modem"

    printf '%s\n' "$init_usbnet" > "$env_dir/state/usbnet"
    printf '%s\n' "$init_cfun" > "$env_dir/state/cfun"
    printf '0\n' > "$env_dir/state/mbn_autosel"
    printf '1\n' > "$env_dir/state/uci_disabled"
    printf '/dev/wrong0\n' > "$env_dir/state/uci_device"
    printf '1-1.2:1.9\n' > "$env_dir/state/uci_node"
    : > "$env_dir/state/calls.log"

    if [ "$init_usbnet" = "0" ]; then
        mkdir -p "$env_dir/sys/bus/usb/devices/1-1.2/1-1.2:1.4/usbmisc/cdc-wdm0"
        mkdir -p "$env_dir/sys/bus/usb/devices/1-1.2/1-1.2:1.4/net/wwan0"
        mkdir -p "$env_dir/sys/class/net/wwan0/qmi"
        printf 'N\n' > "$env_dir/sys/class/net/wwan0/qmi/raw_ip"
    fi

    # Mock sleep (no-op for fast tests)
    cat <<'EOF' > "$env_dir/bin/fastsleep"
#!/bin/sh
exit 0
EOF
    chmod 755 "$env_dir/bin/fastsleep"

    # Mock gl_modem
    cat <<EOF > "$env_dir/bin/gl_modem"
#!/bin/sh
STATE="$env_dir/state"
SYSUSB="$env_dir/sys/bus/usb/devices/1-1.2"
SYSNET="$env_dir/sys/class/net"
echo "gl_modem \$*" >> "\$STATE/calls.log"
# Args: -B <bus> AT <cmd>
shift 2
action="\$1"
shift || true
if [ "\$action" = "connect-auto" ]; then
    exit 0
fi
cmd="\$1"
case "\$cmd" in
    AT)
        printf 'AT\r\nOK\r\n'
        ;;
    ATI)
        printf 'Quectel\r\nEM120K-GL\r\nRevision: EM120KGLAUR01A08M4G\r\nIMEI: 861234567890123\r\nOK\r\n'
        ;;
    AT+QGMR)
        printf 'EM120KGLAUR01A08M4G\r\nOK\r\n'
        ;;
    'AT+QCFG="usbnet"')
        printf '+QCFG: "usbnet",%s\r\nOK\r\n' "\$(cat "\$STATE/usbnet")"
        ;;
    'AT+QCFG="usbnet",0')
        printf '0\n' > "\$STATE/usbnet"
        printf 'OK\r\n'
        ;;
    'AT+CFUN=1,1')
        if [ "\$(cat "\$STATE/usbnet")" = "0" ]; then
            mkdir -p "\$SYSUSB/1-1.2:1.4/usbmisc/cdc-wdm0"
            mkdir -p "\$SYSUSB/1-1.2:1.4/net/wwan0"
            mkdir -p "\$SYSNET/wwan0/qmi"
            printf 'N\n' > "\$SYSNET/wwan0/qmi/raw_ip"
        fi
        printf 'OK\r\n'
        ;;
    'AT+CFUN?')
        printf '+CFUN: %s\r\nOK\r\n' "\$(cat "\$STATE/cfun")"
        ;;
    'AT+CFUN=1')
        printf '1\n' > "\$STATE/cfun"
        printf 'OK\r\n'
        ;;
    'AT+CPIN?')
        printf '+CPIN: READY\r\nOK\r\n'
        ;;
    'AT+CSQ')
        printf '+CSQ: 24,99\r\nOK\r\n'
        ;;
    'AT+CEREG?')
        printf '+CEREG: 0,1\r\nOK\r\n'
        ;;
    'AT+COPS?')
        printf '+COPS: 0,0,"TestCarrier",7\r\nOK\r\n'
        ;;
    'AT+QMBNCFG="AutoSel"')
        printf '+QMBNCFG: "AutoSel",%s\r\nOK\r\n' "\$(cat "\$STATE/mbn_autosel")"
        ;;
    'AT+QMBNCFG="AutoSel",1')
        printf '1\n' > "\$STATE/mbn_autosel"
        printf 'OK\r\n'
        ;;
    *)
        printf 'OK\r\n'
        ;;
esac
EOF
    chmod 755 "$env_dir/bin/gl_modem"

    # Mock uqmi
    cat <<EOF > "$env_dir/bin/uqmi"
#!/bin/sh
STATE="$env_dir/state"
echo "uqmi \$*" >> "\$STATE/calls.log"
case "\$*" in
    *--wda-get-data-format*)
        printf '"raw-ip"\n'
        ;;
    *--fcc-auth*)
        printf '1\n' > "\$STATE/cfun"
        ;;
esac
exit 0
EOF
    chmod 755 "$env_dir/bin/uqmi"

    # Mock uci
    cat <<EOF > "$env_dir/bin/uci"
#!/bin/sh
STATE="$env_dir/state"
echo "uci \$*" >> "\$STATE/calls.log"
if [ "\$1" = "-q" ]; then shift; fi
case "\$1" in
    get)
        case "\$2" in
            network.modem_1_1_2.proto) echo "qcm" ;;
            network.modem_1_1_2.device) cat "\$STATE/uci_device" ;;
            network.modem_1_1_2.node) cat "\$STATE/uci_node" ;;
            network.modem_1_1_2.disabled) cat "\$STATE/uci_disabled" ;;
        esac
        ;;
    set)
        case "\$2" in
            network.modem_1_1_2.device=*) printf '%s\n' "\${2#*=}" > "\$STATE/uci_device" ;;
            network.modem_1_1_2.node=*) printf '%s\n' "\${2#*=}" > "\$STATE/uci_node" ;;
            network.modem_1_1_2.disabled=*) printf '%s\n' "\${2#*=}" > "\$STATE/uci_disabled" ;;
        esac
        ;;
    show)
        echo "network.modem_1_1_2.iccid='89380010001234567890'"
        echo "network.modem_1_1_2.pincode='1234'"
        echo "network.modem_1_1_2.proto='qcm'"
        ;;
esac
exit 0
EOF
    chmod 755 "$env_dir/bin/uci"

    # Mock ip, ifup, ping
    cat <<EOF > "$env_dir/bin/ip"
#!/bin/sh
if [ "\$1" = "-4" ]; then
    echo "    inet 10.42.0.5/30 scope global wwan0"
fi
exit 0
EOF
    chmod 755 "$env_dir/bin/ip"

    cat <<EOF > "$env_dir/bin/ifup"
#!/bin/sh
echo "ifup \$*" >> "$env_dir/state/calls.log"
exit 0
EOF
    chmod 755 "$env_dir/bin/ifup"

    cat <<EOF > "$env_dir/bin/ping"
#!/bin/sh
echo "ping \$*" >> "$env_dir/state/calls.log"
exit 0
EOF
    chmod 755 "$env_dir/bin/ping"
}

echo "=== 3. Scenario A: EM120K-GL stuck in MBIM mode (usbnet=2) ==="
ENV_A="$TMP_BASE/env_a"
setup_mock_env "$ENV_A" "2" "1"

PATH="$ENV_A/bin:$PATH" \
EM120K_MODEM_SH="/nonexistent" \
EM120K_SYSFS_USB="$ENV_A/sys/bus/usb" \
EM120K_SYSFS_NET="$ENV_A/sys/class/net" \
EM120K_SYSFS_DEVICES="$ENV_A/sys/devices" \
EM120K_DEV_ROOT="$ENV_A/dev" \
EM120K_PROC_GL_MODEM="$ENV_A/proc/build-in-modem" \
EM120K_LOCK_DIR="$ENV_A/lock" \
EM120K_SLEEP_CMD="$ENV_A/bin/fastsleep" \
sh "$REPO_DIR/files/usr/bin/em120k-fix" apply >/dev/null

assert_eq "$(cat "$ENV_A/state/usbnet")" "0" "Scenario A: switched usbnet from 2 (MBIM) to 0 (QMI)"
assert_contains "$ENV_A/state/calls.log" 'AT+CFUN=1,1' "Scenario A: rebooted modem to apply usbnet=0"
assert_eq "$(cat "$ENV_A/sys/class/net/wwan0/qmi/raw_ip")" "Y" "Scenario A: set raw_ip=Y"
assert_eq "$(cat "$ENV_A/state/uci_device")" "$ENV_A/dev/cdc-wdm0" "Scenario A: updated UCI device"
assert_eq "$(cat "$ENV_A/state/uci_node")" "1-1.2:1.4" "Scenario A: updated UCI node"
assert_eq "$(cat "$ENV_A/state/uci_disabled")" "0" "Scenario A: re-enabled UCI modem interface"
assert_contains "$ENV_A/state/calls.log" 'ifup modem_1_1_2' "Scenario A: brought up modem_1_1_2"
assert_contains "$ENV_A/state/calls.log" 'ping -I wwan0' "Scenario A: verified connectivity via ping"

echo "=== 4. Scenario B: EM120K-GL in QMI mode with FCC Lock (CFUN=7) ==="
ENV_B="$TMP_BASE/env_b"
setup_mock_env "$ENV_B" "0" "7"

PATH="$ENV_B/bin:$PATH" \
EM120K_MODEM_SH="/nonexistent" \
EM120K_SYSFS_USB="$ENV_B/sys/bus/usb" \
EM120K_SYSFS_NET="$ENV_B/sys/class/net" \
EM120K_SYSFS_DEVICES="$ENV_B/sys/devices" \
EM120K_DEV_ROOT="$ENV_B/dev" \
EM120K_PROC_GL_MODEM="$ENV_B/proc/build-in-modem" \
EM120K_LOCK_DIR="$ENV_B/lock" \
EM120K_SLEEP_CMD="$ENV_B/bin/fastsleep" \
sh "$REPO_DIR/files/usr/bin/em120k-fix" apply >/dev/null

if grep -q 'AT+CFUN=1,1' "$ENV_B/state/calls.log"; then
    fail "Scenario B: should not reboot when usbnet is already 0"
else
    pass "Scenario B: did not unnecessarily reboot modem"
fi
assert_contains "$ENV_B/state/calls.log" '--fcc-auth' "Scenario B: ran uqmi --fcc-auth"
assert_eq "$(cat "$ENV_B/state/cfun")" "1" "Scenario B: unlocked RF to CFUN=1"
assert_eq "$(cat "$ENV_B/state/mbn_autosel")" "1" "Scenario B: enabled QMBNCFG AutoSel=1"

echo "=== 5. Scenario C: status & redacted diag ==="
DIAG_OUT="$TMP_BASE/diag.log"
PATH="$ENV_B/bin:$PATH" \
EM120K_MODEM_SH="/nonexistent" \
EM120K_SYSFS_USB="$ENV_B/sys/bus/usb" \
EM120K_SYSFS_NET="$ENV_B/sys/class/net" \
EM120K_SYSFS_DEVICES="$ENV_B/sys/devices" \
EM120K_DEV_ROOT="$ENV_B/dev" \
EM120K_PROC_GL_MODEM="$ENV_B/proc/build-in-modem" \
EM120K_DIAG_FILE="$DIAG_OUT" \
sh "$REPO_DIR/files/usr/bin/em120k-fix" diag >/dev/null

assert_contains "$DIAG_OUT" 'EM120KGLAUR01A08M4G' "Scenario C: diag captured firmware revision"
assert_contains "$DIAG_OUT" '<REDACTED_ID>' "Scenario C: diag redacted 15-digit IMEI"
if grep -q '861234567890123' "$DIAG_OUT"; then
    fail "Scenario C: IMEI leaked into diag log"
else
    pass "Scenario C: no IMEI leak in diag log"
fi
if grep -q '1234' "$DIAG_OUT"; then
    fail "Scenario C: PIN leaked into diag log"
else
    pass "Scenario C: no PIN leak in diag log"
fi

echo "========================================"
printf 'Total: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
