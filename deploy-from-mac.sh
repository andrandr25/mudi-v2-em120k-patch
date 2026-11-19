#!/bin/sh
# One-step deploy helper for macOS/Linux connected to GL-E750 V2 (Mudi V2) over Ethernet
# Usage: sh deploy-from-mac.sh [router-ip]
set -eu

ROUTER_IP="${1:-192.168.8.1}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ARCHIVE="${SCRIPT_DIR}/mudi-v2-em120k-patch.tar.gz"

echo "=== Deploying EM120K-GL patch to root@${ROUTER_IP} ==="

if [ -f "$ARCHIVE" ]; then
    echo "[1/2] Uploading archive ${ARCHIVE}..."
    scp -O "$ARCHIVE" "root@${ROUTER_IP}:/tmp/mudi-v2-em120k-patch.tar.gz"
    echo "[2/2] Extracting and running install.sh on Mudi V2..."
    ssh "root@${ROUTER_IP}" "rm -rf /tmp/mudi-v2-em120k-patch && mkdir -p /tmp/mudi-v2-em120k-patch && tar -xzf /tmp/mudi-v2-em120k-patch.tar.gz -C /tmp/mudi-v2-em120k-patch && sh /tmp/mudi-v2-em120k-patch/install.sh"
else
    echo "[1/2] Uploading project directory ${SCRIPT_DIR}..."
    scp -O -r "$SCRIPT_DIR" "root@${ROUTER_IP}:/tmp/mudi-v2-em120k-patch"
    echo "[2/2] Running install.sh on Mudi V2..."
    ssh "root@${ROUTER_IP}" "sh /tmp/mudi-v2-em120k-patch/install.sh"
fi
