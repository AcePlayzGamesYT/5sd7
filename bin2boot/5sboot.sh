#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "====== Starting iPhone 5s Tethered Boot ======"
echo "Make sure your device is plugged in and in pwnDFU mode."
echo

wait_for_recovery() {
    local label="$1"
    local timeout="${2:-20}"
    local elapsed=0

    echo "Waiting for device after $label..."

    while [[ "$elapsed" -lt "$timeout" ]]; do
        if irecovery -q >/dev/null 2>&1; then
            echo "[OK] Device detected."
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    echo "[ERROR] Device did not reconnect after $label."
    return 1
}

send_file() {
    local label="$1"
    local file="$2"

    if [[ ! -f "$file" ]]; then
        echo "[ERROR] Missing file: $file"
        exit 1
    fi

    echo "$label"
    irecovery -f "$file"
    local result=$?

    if [[ "$result" -ne 0 ]]; then
        echo "[ERROR] Failed sending: $file"
        exit 1
    fi
}

send_cmd() {
    local cmd="$1"

    echo "Executing command: $cmd"
    irecovery -c "$cmd"
    local result=$?

    if [[ "$result" -ne 0 ]]; then
        echo "[ERROR] Failed command: $cmd"
        exit 1
    fi
}

send_file "[1/4] Sending iBSS..." "iBSS.img4"

# iBSS often causes USB reconnect
wait_for_recovery "iBSS" 20 || exit 1

send_file "[2/4] Sending iBEC..." "iBEC.img4"

# iBEC DEFINITELY can take a sec to come back
wait_for_recovery "iBEC" 30 || exit 1

send_file "[3/4] Sending DeviceTree..." "DeviceTree.img4"
send_cmd "devicetree"

sleep 1

send_file "[4/4] Sending Kernelcache..." "Kernelcache.img4"
send_cmd "bootx"

echo
echo "=================== Done ==================="
echo "If the patches are correct, the device should boot now."