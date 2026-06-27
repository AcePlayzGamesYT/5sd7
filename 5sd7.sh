#!/usr/bin/env bash

#########################################
# iphone 5s ios 7.x 8.0 9.3.4 tether dg
# gsm/cdma ipsw builder + restore + boot
#########################################

VERSION="2.2"

#########################################
# colors 
#########################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

#########################################
# paths
#########################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$SCRIPT_DIR/bin"
BOOT="$SCRIPT_DIR/bin2boot"
ENC_KEYS="$SCRIPT_DIR/enc_keys"
WORK="$SCRIPT_DIR/work"
STATE_FILE="$SCRIPT_DIR/.5sd7_state"


IOS7_IPSW="$BIN/ios7.ipsw"

#########################################
# per version img4 / idevicerestore profiles
#########################################

TOOL_PROFILE_DIR="$SCRIPT_DIR/tool_profiles"
TOOL_SWAP_BACKUP="$SCRIPT_DIR/.5sd7_tool_swap_backup"


IOS9_IMG4_URL="https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4"
IOS9_IDEVICERESTORE_URL="https://github.com/NyanSatan/SundanceInH2A/raw/refs/heads/master/executables/Darwin/idevicerestore"


LEGACY_IMG4_URL="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/img4"
LEGACY_IDEVICERESTORE_URL="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/idevicerestore"

#########################################
# target vars for runtime
#########################################

TARGET_IOS=""
TARGET_IOS_DISPLAY=""
DEVICE_TYPE=""
BOARD=""
BOARD_SHORT=""
IOS7_SRC_DIR=""
IOS12_MOD_DIR=""

IBSS_KEY=""
IBEC_KEY=""
DEVICETREE_KEY=""
KCACHE_KEY=""
RESTORERAMDISK_KEY=""
ROOTFS_KEY=""
IOS7_RESTORERAMDISK_FILENAME=""
IOS12_RESTORERAMDISK_FILENAME=""

#########################################
# ui
#########################################

pause() {
    echo
    read -rp "Press Enter to continue..."
}

header() {
    clear
    echo -e "${BLUE}"
    echo "================================================"
    echo " iPhone 5s iOS 7.x/8.x/9.3.x Tethered Downgrade Tool"
    echo " Version $VERSION"
    echo "================================================"
    echo -e "${NC}"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

die() {
    error "$1"
    echo
    exit 1
}

run_cmd() {
    echo
    echo -e "${PURPLE}>> $*${NC}"
    "$@"

    local status=$?
    if [[ "$status" -ne 0 ]]; then
        error "Command failed (if this is img4 on cannot set convert do not worry, it is normal) with exit code $status"
        return "$status"
    fi

    return 0
}

check_file() {
    if [[ ! -f "$1" ]]; then
        die "Missing file: $1"
    fi
}

check_folder() {
    if [[ ! -d "$1" ]]; then
        die "Missing folder: $1"
    fi
}

read_drag_path() {
    local prompt="$1"
    local out

    read -ep "$prompt" out

    # iff quotes added, remove
    out="${out%\"}"
    out="${out#\"}"
    out="${out%\'}"
    out="${out#\'}"

    # expand the ~
    out="${out/#\~/$HOME}"

    # remove trailing spaces if any
    out="$(printf "%s" "$out" | sed 's/[[:space:]]*$//')"

    printf "%s" "$out"
}

first_file() {
    local base="$1"
    shift
    find "$base" "$@" -type f -print 2>/dev/null | head -n 1
}

get_enc_value() {
    local device="$1"
    local ios="$2"
    local component="$3"

    awk -F'|' -v d="$device" -v i="$ios" -v c="$component" '
        $0 !~ /^#/ && $1 == d && $2 == i && $3 == c { print $4; exit }
    ' "$ENC_KEYS"
}

require_enc_value() {
    local device="$1"
    local ios="$2"
    local component="$3"
    local value

    value="$(get_enc_value "$device" "$ios" "$component")"

    if [[ -z "$value" || "$value" == "MISSING" ]]; then
        die "Missing enc_keys value for $device | $ios | $component"
    fi

    printf "%s" "$value"
}

load_keys_for_target() {
    check_file "$ENC_KEYS"

    IBSS_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "IBSS")"
    IBEC_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "IBEC")"
    DEVICETREE_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "DEVICETREE")"
    KCACHE_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "KCACHE")"
    RESTORERAMDISK_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "RESTORERAMDISK")"
    ROOTFS_KEY=""

    if [[ "$TARGET_IOS" == 9.* ]]; then
        ROOTFS_KEY="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "ROOTFS")"
    fi

    IOS7_RESTORERAMDISK_FILENAME="$(require_enc_value "$DEVICE_TYPE" "$TARGET_IOS" "RESTORERAMDISK_FILENAME")"
    IOS12_RESTORERAMDISK_FILENAME="$(require_enc_value "$DEVICE_TYPE" "12.5.8" "RESTORERAMDISK_FILENAME")"
}

check_dsc64patcher_for_target() {
    if [[ "$TARGET_IOS" == 8.* || "$TARGET_IOS" == 9.* ]]; then
        check_file "$BOOT/dsc64patcher"
    else
        if [[ ! -f "$BOOT/dsc64patcher" ]]; then
            warn "dsc64patcher missing. This is OK for iOS 7, but iOS 8/9 support needs it."
        fi
    fi
}

copy_tool_both_bins() {
    local name="$1"

    mkdir -p "$BIN" "$BOOT"

    if [[ -f "$BOOT/$name" && ! -f "$BIN/$name" ]]; then
        cp "$BOOT/$name" "$BIN/$name"
    elif [[ -f "$BIN/$name" && ! -f "$BOOT/$name" ]]; then
        cp "$BIN/$name" "$BOOT/$name"
    fi

    chmod +x "$BIN/$name" "$BOOT/$name" 2>/dev/null
}


tool_backup_name() {
    printf "%s" "$1" | sed 's#[/ ]#_#g'
}

backup_active_restore_tools_once() {
    mkdir -p "$TOOL_SWAP_BACKUP"

    local item
    for item in "$BOOT/img4" "$BIN/img4" "$BOOT/idevicerestore" "$BIN/idevicerestore"; do
        local backup_name
        backup_name="$(tool_backup_name "$item")"

        if [[ -f "$item" && ! -f "$TOOL_SWAP_BACKUP/$backup_name" ]]; then
            cp "$item" "$TOOL_SWAP_BACKUP/$backup_name"
        fi
    done
}

restore_active_restore_tools_silent() {
    if [[ ! -d "$TOOL_SWAP_BACKUP" ]]; then
        return 0
    fi

    local item
    for item in "$BOOT/img4" "$BIN/img4" "$BOOT/idevicerestore" "$BIN/idevicerestore"; do
        local backup_name
        backup_name="$(tool_backup_name "$item")"

        if [[ -f "$TOOL_SWAP_BACKUP/$backup_name" ]]; then
            mkdir -p "$(dirname "$item")"
            cp "$TOOL_SWAP_BACKUP/$backup_name" "$item" 2>/dev/null || true
            chmod +x "$item" 2>/dev/null || true
        fi
    done

    rm -rf "$TOOL_SWAP_BACKUP" 2>/dev/null || true
}

download_profile_tool() {
    local out="$1"
    local url="$2"
    local label="$3"

    command -v curl >/dev/null 2>&1 || die "curl is required to download $label"

    rm -f "$out"
    run_cmd curl -L -o "$out" "$url" || return
    chmod +x "$out" 2>/dev/null

    if [[ ! -s "$out" ]]; then
        error "$label downloaded as an empty file."
        return 1
    fi
}

refresh_restore_tool_profile_for_target() {
    if [[ "$(uname)" != "Darwin" ]]; then
        die "5sd7 tool-profile switching currently supports Intel macOS only."
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        die "This 5sd7 build is set up for Intel Mac only."
    fi

    local profile img4_url idevicerestore_url

    if [[ "$TARGET_IOS" == 9.* ]]; then
        profile="ios9_surrealra1n"
        img4_url="$IOS9_IMG4_URL"
        idevicerestore_url="$IOS9_IDEVICERESTORE_URL"
        info "Refreshing iOS 9 tool profile: img4 with -J and idevicerestore with -y..."
    else
        profile="legacy_ios7_8"
        img4_url="$LEGACY_IMG4_URL"
        idevicerestore_url="$LEGACY_IDEVICERESTORE_URL"
        info "Refreshing legacy iOS 7/8 tool profile: old img4 and idevicerestore without -y restore usage..."
    fi

    mkdir -p "$TOOL_PROFILE_DIR/$profile"

    download_profile_tool "$TOOL_PROFILE_DIR/$profile/img4" "$img4_url" "$profile img4" || return
    download_profile_tool "$TOOL_PROFILE_DIR/$profile/idevicerestore" "$idevicerestore_url" "$profile idevicerestore" || return
}

apply_restore_tool_profile_for_target() {
    if [[ -z "$TARGET_IOS" ]]; then
        return 0
    fi

    refresh_restore_tool_profile_for_target || return
    backup_active_restore_tools_once

    local profile
    if [[ "$TARGET_IOS" == 9.* ]]; then
        profile="ios9_surrealra1n"
    else
        profile="legacy_ios7_8"
    fi

    info "Applying temporary $profile img4/idevicerestore profile..."

    cp "$TOOL_PROFILE_DIR/$profile/img4" "$BOOT/img4" || return
    cp "$TOOL_PROFILE_DIR/$profile/img4" "$BIN/img4" || return
    cp "$TOOL_PROFILE_DIR/$profile/idevicerestore" "$BIN/idevicerestore" || return
    cp "$TOOL_PROFILE_DIR/$profile/idevicerestore" "$BOOT/idevicerestore" || return

    chmod +x "$BOOT/img4" "$BIN/img4" "$BIN/idevicerestore" "$BOOT/idevicerestore" 2>/dev/null
}

trap restore_active_restore_tools_silent EXIT


download_darwin_tool_both_bins() {
    local name="$1"
    local url="$2"

    mkdir -p "$BIN" "$BOOT"

    if [[ -f "$BOOT/$name" && -f "$BIN/$name" ]]; then
        copy_tool_both_bins "$name"
        return 0
    fi

    if [[ "$(uname)" != "Darwin" ]]; then
        die "$name auto-download currently uses Darwin/macOS binaries only."
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to download $name"

    info "$name missing. Downloading Darwin binary..."
    run_cmd curl -L -o "$BOOT/$name" "$url" || return
    cp "$BOOT/$name" "$BIN/$name"
    chmod +x "$BOOT/$name" "$BIN/$name" 2>/dev/null
}

download_ldid_both_bins() {
    mkdir -p "$BIN" "$BOOT"

    if [[ -f "$BOOT/ldid" && -f "$BIN/ldid" ]]; then
        copy_tool_both_bins "ldid"
        return 0
    fi

    if [[ "$(uname)" != "Darwin" ]]; then
        die "ldid auto-download currently uses Darwin/macOS binaries only."
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to download ldid"

    local arch
    arch="$(uname -m)"

    local url
    if [[ "$arch" == "arm64" ]]; then
        url="https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64"
    else
        url="https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_x86_64"
    fi

    info "ldid missing. Downloading Darwin binary..."
    run_cmd curl -L -o "$BOOT/ldid" "$url" || return
    cp "$BOOT/ldid" "$BIN/ldid"
    chmod +x "$BOOT/ldid" "$BIN/ldid" 2>/dev/null
}

compile_asr64_patcher_both_bins() {
    mkdir -p "$BIN" "$BOOT"

    if [[ -f "$BOOT/asr64_patcher" && -f "$BIN/asr64_patcher" ]]; then
        copy_tool_both_bins "asr64_patcher"
        return 0
    fi

    command -v git >/dev/null 2>&1 || die "git is required to build asr64_patcher"
    command -v make >/dev/null 2>&1 || die "make is required to build asr64_patcher"

    if [[ "$(uname)" == "Darwin" ]] && ! xcode-select -p >/dev/null 2>&1; then
        die "Xcode Command Line Tools are required to build asr64_patcher"
    fi

    local srcdir="$WORK/ios9_tools_src/asr64_patcher"

    info "asr64_patcher missing. Cloning and compiling..."
    rm -rf "$srcdir"
    mkdir -p "$(dirname "$srcdir")"

    run_cmd git clone https://github.com/iSuns9/asr64_patcher --recursive "$srcdir" || return
    (
        cd "$srcdir" || exit 1
        make
    ) || {
        error "Failed to compile asr64_patcher."
        return 1
    }

    if [[ ! -f "$srcdir/asr64_patcher" ]]; then
        error "Compiled asr64_patcher binary not found."
        return 1
    fi

    cp "$srcdir/asr64_patcher" "$BOOT/asr64_patcher"
    cp "$srcdir/asr64_patcher" "$BIN/asr64_patcher"
    chmod +x "$BOOT/asr64_patcher" "$BIN/asr64_patcher" 2>/dev/null
}

ensure_core_build_tools_if_missing() {
    if [[ "$(uname)" == "Darwin" ]]; then
        download_darwin_tool_both_bins "img4" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4" || return
        download_darwin_tool_both_bins "kerneldiff" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kerneldiff" || return
    else
        warn "Auto-download for img4/kerneldiff is currently Darwin/macOS only."
    fi
}

ensure_ios9_tools_if_needed() {
    if [[ "$TARGET_IOS" != 9.* ]]; then
        return 0
    fi

    info "Checking iOS 9.3.4-only tools..."

    ensure_core_build_tools_if_missing || return

    download_darwin_tool_both_bins "kairos" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos" || return
    download_darwin_tool_both_bins "Kernel64Patcher2" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/Kernel64Patcher" || return
    download_darwin_tool_both_bins "dmg" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dmg" || return
    download_darwin_tool_both_bins "hfsplus" "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus" || return
    download_darwin_tool_both_bins "dsc64patcher" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dsc64patcher" || return
    download_ldid_both_bins || return
    compile_asr64_patcher_both_bins || return

    success "iOS 9.3.4-only tools are ready."
}

check_extra_tools_for_target() {
    if [[ "$TARGET_IOS" == 9.* ]]; then
        check_file "$BOOT/kairos"
        check_file "$BOOT/Kernel64Patcher2"
        check_file "$BOOT/asr64_patcher"
        check_file "$BOOT/hfsplus"
        check_file "$BOOT/ldid"
        check_file "$BOOT/dmg"
    fi
}

save_state() {
    {
        printf 'TARGET_IOS=%q\n' "$TARGET_IOS"
        printf 'TARGET_IOS_DISPLAY=%q\n' "$TARGET_IOS_DISPLAY"
        printf 'DEVICE_TYPE=%q\n' "$DEVICE_TYPE"
        printf 'BOARD=%q\n' "$BOARD"
        printf 'BOARD_SHORT=%q\n' "$BOARD_SHORT"
        printf 'IOS7_SRC_DIR=%q\n' "$IOS7_SRC_DIR"
        printf 'IOS12_MOD_DIR=%q\n' "$IOS12_MOD_DIR"
    } > "$STATE_FILE"
}

load_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "No saved target state found."
        echo
        echo "Run option 2 first to build the modified IPSW."
        pause
        return 1
    fi

    # shellcheck source=/dev/null
    . "$STATE_FILE"
    load_keys_for_target
    return 0
}

#########################################
# checks
#########################################

check_base_layout() {
    check_folder "$BIN"

    if [[ ! -d "$BOOT" ]]; then
        warn "bin2boot does not exist. Creating it from bin..."
        cp -R "$BIN" "$BOOT"
    fi

    check_folder "$BOOT"
    check_file "$ENC_KEYS"
}

check_restore_tools() {
    check_base_layout
    check_file "$BIN/gaster"
    check_file "$BIN/idevicerestore"
}

check_build_tools() {
    check_base_layout
    ensure_core_build_tools_if_missing
    check_file "$BOOT/img4"
    check_file "$BOOT/img4tool"
    check_file "$BOOT/ipatcher"
    check_file "$BOOT/Kernel64Patcher"
    check_file "$BOOT/kerneldiff"
}

check_boot_tools() {
    check_base_layout
    check_file "$BOOT/gaster"
    check_file "$BOOT/5sboot.sh"
}

make_executable() {
    chmod +x "$BIN/gaster" 2>/dev/null
    chmod +x "$BIN/idevicerestore" 2>/dev/null

    chmod +x "$BOOT/gaster" 2>/dev/null
    chmod +x "$BOOT/idevicerestore" 2>/dev/null
    chmod +x "$BOOT/img4tool" 2>/dev/null
    chmod +x "$BOOT/img4" 2>/dev/null
    chmod +x "$BOOT/ipatcher" 2>/dev/null
    chmod +x "$BOOT/Kernel64Patcher" 2>/dev/null
    chmod +x "$BOOT/Kernel64Patcher2" 2>/dev/null
    chmod +x "$BOOT/kairos" 2>/dev/null
    chmod +x "$BOOT/kerneldiff" 2>/dev/null
    chmod +x "$BOOT/asr64_patcher" 2>/dev/null
    chmod +x "$BOOT/hfsplus" 2>/dev/null
    chmod +x "$BOOT/ldid" 2>/dev/null
    chmod +x "$BOOT/dmg" 2>/dev/null
    chmod +x "$BOOT/dsc64patcher" 2>/dev/null
    chmod +x "$BOOT/5sboot.sh" 2>/dev/null
}

#########################################
# selectrion
#########################################

select_target() {
    header

    echo "Select iPhone 5s model:"
    echo
    echo "1) GSM  / iPhone6,1 / n51ap"
    echo "2) CDMA / iPhone6,2 / n53ap"
    echo
    read -rp "Choice: " model_choice

    case "$model_choice" in
        1)
            DEVICE_TYPE="GSM"
            BOARD="n51ap"
            BOARD_SHORT="n51"
            ;;
        2)
            DEVICE_TYPE="CDMA"
            BOARD="n53ap"
            BOARD_SHORT="n53"
            ;;
        *)
            error "Invalid model selection."
            pause
            return 1
            ;;
    esac

    header

    echo "Select target iOS version:"
    echo
    echo "1) iOS 7.0.6"
    echo "2) iOS 7.1.0"
    echo "3) iOS 7.1.1"
    echo "4) iOS 7.1.2"
    echo "5) iOS 8.0"
    echo "6) iOS 8.4"
    echo "7) iOS 9.3.2"
    echo "8) iOS 9.3.4"
    echo
    read -rp "Choice: " ios_choice

    case "$ios_choice" in
        1)
            TARGET_IOS="7.0.6"
            TARGET_IOS_DISPLAY="7.0.6"
            ;;
        2)
            TARGET_IOS="7.1"
            TARGET_IOS_DISPLAY="7.1.0"
            ;;
        3)
            TARGET_IOS="7.1.1"
            TARGET_IOS_DISPLAY="7.1.1"
            ;;
        4)
            TARGET_IOS="7.1.2"
            TARGET_IOS_DISPLAY="7.1.2"
            ;;
        5)
            TARGET_IOS="8.0"
            TARGET_IOS_DISPLAY="8.0"
            ;;
        6)
            TARGET_IOS="8.4"
            TARGET_IOS_DISPLAY="8.4"
            ;;
        7)
            TARGET_IOS="9.3.2"
            TARGET_IOS_DISPLAY="9.3.2"
            ;;
        8)
            TARGET_IOS="9.3.4"
            TARGET_IOS_DISPLAY="9.3.4"
            ;;
        *)
            error "Invalid iOS selection."
            pause
            return 1
            ;;
    esac

    load_keys_for_target
    ensure_ios9_tools_if_needed
    check_dsc64patcher_for_target
    check_extra_tools_for_target
    apply_restore_tool_profile_for_target || return

    success "Selected $DEVICE_TYPE / $BOARD / iOS $TARGET_IOS_DISPLAY"
    return 0
}

#########################################
# ipsw pathfind
#########################################

find_ios_component_paths() {
    local src="$1"

    IBSS_IM4P="$(first_file "$src/Firmware/dfu" -name "iBSS.${BOARD}*.im4p")"
    IBEC_IM4P="$(first_file "$src/Firmware/dfu" -name "iBEC.${BOARD}*.im4p")"

    if [[ -z "$IBSS_IM4P" ]]; then
        IBSS_IM4P="$(first_file "$src/Firmware/dfu" -name "iBSS.${BOARD_SHORT}*.im4p")"
    fi

    if [[ -z "$IBEC_IM4P" ]]; then
        IBEC_IM4P="$(first_file "$src/Firmware/dfu" -name "iBEC.${BOARD_SHORT}*.im4p")"
    fi
    DEVICETREE_IM4P="$(first_file "$src/Firmware/all_flash" -path "*all_flash.${BOARD}.production/DeviceTree.${BOARD}.im4p")"
    KCACHE_IM4P="$(first_file "$src" -name "kernelcache.release.${BOARD_SHORT}*")"

    if [[ -z "$IBSS_IM4P" ]]; then die "Could not find target iOS iBSS for $BOARD"; fi
    if [[ -z "$IBEC_IM4P" ]]; then die "Could not find target iOS iBEC for $BOARD"; fi
    if [[ -z "$DEVICETREE_IM4P" ]]; then die "Could not find target iOS DeviceTree for $BOARD"; fi
    if [[ -z "$KCACHE_IM4P" ]]; then die "Could not find target iOS kernelcache for $BOARD_SHORT"; fi

    IOS7_RESTORERAMDISK="$src/$IOS7_RESTORERAMDISK_FILENAME"
    check_file "$IOS7_RESTORERAMDISK"
}

find_ios12_destination_paths() {
    local dst="$1"

    # 12.5.8 uses a different setup for ibss and ibec than 7.
    # 7:  Firmware/dfu/iBSS.n51ap.RELEASE.im4p or iBSS.n53ap.RELEASE.im4p
    # 12: Firmware/dfu/iBSS.iphone6.RELEASE.im4p and iBEC.iphone6.RELEASE.im4p
    IOS12_IBSS_IM4P="$(first_file "$dst/Firmware/dfu" -name "iBSS.iphone6.RELEASE.im4p")"
    IOS12_IBEC_IM4P="$(first_file "$dst/Firmware/dfu" -name "iBEC.iphone6.RELEASE.im4p")"

    #  12 dtre is directly in Firmware/all_flash, not inside all_flash.n51ap.production.
    # GSM  = DeviceTree.n51ap.im4p
    # CDMA = DeviceTree.n53ap.im4p
    IOS12_DEVICETREE_IM4P="$(first_file "$dst/Firmware/all_flash" -name "DeviceTree.${BOARD}.im4p")"

    #  12.5.8 uses a shared 5s kernjelcache name in the ipsw root.
    #   normally kernelcache.release.iphone6, even when the target board is n51ap or n53ap.
    # dont search for n51 or n53 here. that is only for the ios 7 source kernelcache.
    IOS12_KCACHE_IM4P="$(first_file "$dst" -name "kernelcache.release.iphone6*")"

    # fallback
    if [[ -z "$IOS12_KCACHE_IM4P" ]]; then
        IOS12_KCACHE_IM4P="$(first_file "$dst" -maxdepth 1 -name "kernelcache.release.*")"
    fi

    if [[ -z "$IOS12_IBSS_IM4P" ]]; then
        echo
        warn "Could not find iOS 12 iBSS. Expected something like:"
        echo "  $dst/Firmware/dfu/iBSS.iphone6.RELEASE.im4p"
        echo
        warn "Files currently in Firmware/dfu:"
        find "$dst/Firmware/dfu" -maxdepth 1 -type f -print 2>/dev/null
        die "Could not find iOS 12 iBSS destination"
    fi

    if [[ -z "$IOS12_IBEC_IM4P" ]]; then
        echo
        warn "Could not find iOS 12 iBEC. Expected something like:"
        echo "  $dst/Firmware/dfu/iBEC.iphone6.RELEASE.im4p"
        echo
        warn "Files currently in Firmware/dfu:"
        find "$dst/Firmware/dfu" -maxdepth 1 -type f -print 2>/dev/null
        die "Could not find iOS 12 iBEC destination"
    fi

    if [[ -z "$IOS12_DEVICETREE_IM4P" ]]; then
        echo
        warn "Could not find iOS 12 DeviceTree. Expected something like:"
        echo "  $dst/Firmware/all_flash/DeviceTree.${BOARD}.im4p"
        echo
        warn "Files currently in Firmware/all_flash:"
        find "$dst/Firmware/all_flash" -maxdepth 1 -type f -print 2>/dev/null
        die "Could not find iOS 12 DeviceTree destination for $BOARD"
    fi

    if [[ -z "$IOS12_KCACHE_IM4P" ]]; then
        echo
        warn "Could not find iOS 12 kernelcache. Expected something like:"
        echo "  $dst/kernelcache.release.iphone6"
        echo
        warn "Kernelcache files currently in IPSW root:"
        find "$dst" -maxdepth 1 -type f -name "kernelcache*" -print 2>/dev/null
        die "Could not find iOS 12 kernelcache destination"
    fi

    IOS12_RESTORERAMDISK="$dst/$IOS12_RESTORERAMDISK_FILENAME"
    check_file "$IOS12_RESTORERAMDISK"
}

find_rootfs_dmg() {
    local dir="$1"
    local restore_ramdisk_name="$2"

    # exlcude the restore ramdisk filename.
    find "$dir" -maxdepth 1 -type f -name "*.dmg" ! -name "$restore_ramdisk_name" -exec ls -S {} + 2>/dev/null | head -n 1
}

#########################################
# opt 1: return to normal
#########################################

return_to_normal() {
    header

    warn "This will clean generated files and reset bin2boot from bin."
    warn "bin will NOT be changed except generated bin/ios7.ipsw will be removed."
    echo
    read -rp "Return everything to normal? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

       info "Removing generated work folder..."
    rm -rf "$WORK"

    info "Removing state file..."
    rm -f "$STATE_FILE"

    info "Removing generated modified IPSW..."
    rm -f "$IOS7_IPSW"

    info "Removing cached idevicerestore filesystem..."
    sudo rm -rf "$SCRIPT_DIR/ios7" 2>/dev/null

    info "Removing ios7 folder from bin2boot..."
    sudo rm -rf "$BOOT/ios7" 2>/dev/null

    info "Removing ios7 folder from bin..."
    sudo rm -rf "$BIN/ios7" 2>/dev/null

    if [[ -d "$BIN" ]]; then
        info "Resetting bin2boot from bin..."
        rm -rf "$BOOT"
        cp -R "$BIN" "$BOOT"
        make_executable
    fi

    success "Clean state restored."
    pause
}

#########################################
# pwn dfu helper
#########################################

run_with_timeout() {
    local timeout="$1"
    shift

    "$@" &
    local pid=$!
    local elapsed=0

    while kill -0 "$pid" 2>/dev/null; do
        if [[ "$elapsed" -ge "$timeout" ]]; then
            echo
            error "Command timed out after ${timeout}s. Killing stuck process..."

            kill "$pid" 2>/dev/null
            sleep 1

            if kill -0 "$pid" 2>/dev/null; then
                warn "Process ignored normal kill. Force killing..."
                kill -9 "$pid" 2>/dev/null
            fi

            wait "$pid" 2>/dev/null
            return 124
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    wait "$pid"
    return $?
}

pwn_dfu_loop() {
    local location="$1"
    local reset_after_success="${2:-no}"
    local timeout_seconds=25
    local attempt=1

    echo
    warn "Put the iPhone 5s into DFU mode now."
    warn "This will retry gaster pwn until it succeeds."
    warn "If gaster hangs, it will auto kill and retry."
    echo
    read -rp "Press Enter when the device is in DFU..."

    cd "$location" || die "Could not cd to $location"

    while true; do
        echo
        info "Running ./gaster pwn..."
        info "Attempt $attempt"

        run_with_timeout "$timeout_seconds" ./gaster pwn
        local result=$?

        if [[ "$result" -eq 0 ]]; then
            success "pwnDFU succeeded."

            if [[ "$reset_after_success" == "yes" ]]; then
                info "Resetting device with gaster after successful pwnDFU..."
                run_with_timeout 10 ./gaster reset

                local reset_result=$?
                if [[ "$reset_result" -ne 0 ]]; then
                    error "gaster reset failed after pwnDFU."
                    return "$reset_result"
                fi

                info "Waiting 10 seconds after reset..."
                sleep 10
            fi

            break
        fi

        if [[ "$result" -eq 124 ]]; then
            error "gaster hung, probably stuck on second SPRAY."
        else
            error "gaster failed with exit code $result."
        fi

        warn "Trying to reset USB state before retry..."
        run_with_timeout 8 ./gaster reset >/dev/null 2>&1

        warn "Retrying in 3 seconds..."
        sleep 3

        attempt=$((attempt + 1))
    done
}

#########################################
# opt2: build modded ipsw
#########################################

build_modified_ipsw() {
    header
    check_build_tools
    make_executable

    echo -e "${YELLOW}Modified IPSW builder:${NC}"
    echo
    echo "This creates bin/ios7.ipsw from ipsws."
    echo
    echo "Supported targets:"
    echo " - iOS 7.0.6"
    echo " - iOS 7.1.0"
    echo " - iOS 7.1.1"
    echo " - iOS 7.1.2"
    echo " - iOS 8.0"
    echo " - iOS 9.3.4"
    echo
    echo "Supported boards:"
    echo " - GSM  = n51ap"
    echo " - CDMA = n53ap"
    echo
    echo "Unsupported: below 7.0.6, iOS 8.0.1-9.3.3, iOS 9.3.5+, iPhone 5c, and other devices."
    echo
    read -rp "Continue? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    select_target || return

    header
    echo "Drag the $DEVICE_TYPE iPhone 5s iOS $TARGET_IOS_DISPLAY IPSW into Terminal."
    echo
    IOS7_USER_IPSW="$(read_drag_path "iOS $TARGET_IOS_DISPLAY IPSW path: ")"
    echo
    echo "Drag the $DEVICE_TYPE iPhone 5s iOS 12.5.8 IPSW into Terminal."
    echo
    IOS12_USER_IPSW="$(read_drag_path "iOS 12.5.8 IPSW path: ")"

    if [[ ! -f "$IOS7_USER_IPSW" ]]; then
        error "iOS $TARGET_IOS_DISPLAY IPSW not found: $IOS7_USER_IPSW"
        pause
        return
    fi

    if [[ ! -f "$IOS12_USER_IPSW" ]]; then
        error "iOS 12.5.8 IPSW not found: $IOS12_USER_IPSW"
        pause
        return
    fi

    header
    warn "This will delete and recreate the work folder:"
    echo "$WORK"
    echo
    warn "It will also overwrite:"
    echo "$IOS7_IPSW"
    echo
    read -rp "Build modified IPSW now? Type YES: " confirm2

    if [[ "$confirm2" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    rm -rf "$WORK"
    mkdir -p "$WORK"
    mkdir -p "$BIN"

    IOS7_SRC_DIR="$WORK/ios7_${DEVICE_TYPE}_${TARGET_IOS}"
    IOS12_EXTRACT_DIR="$WORK/ios12_${DEVICE_TYPE}_12.5.8"
    IOS12_MOD_DIR="$WORK/modified12ipsw"
    BUILD_DIR="$WORK/build"

    mkdir -p "$IOS7_SRC_DIR" "$IOS12_EXTRACT_DIR" "$IOS12_MOD_DIR" "$BUILD_DIR"

    info "Extracting iOS $TARGET_IOS_DISPLAY IPSW..."
    run_cmd unzip -q "$IOS7_USER_IPSW" -d "$IOS7_SRC_DIR" || return

    info "Extracting iOS 12.5.8 IPSW..."
    run_cmd unzip -q "$IOS12_USER_IPSW" -d "$IOS12_EXTRACT_DIR" || return

    info "Copying iOS 12.5.8 extracted IPSW to modified workspace..."
    rm -rf "$IOS12_MOD_DIR"
    cp -R "$IOS12_EXTRACT_DIR" "$IOS12_MOD_DIR"

    info "Finding target iOS source components for $BOARD..."
    find_ios_component_paths "$IOS7_SRC_DIR"

    info "Finding iOS 12 destination components for $BOARD..."
    find_ios12_destination_paths "$IOS12_MOD_DIR"

    IOS7_ROOTFS="$(find_rootfs_dmg "$IOS7_SRC_DIR" "$IOS7_RESTORERAMDISK_FILENAME")"
    IOS12_ROOTFS="$(find_rootfs_dmg "$IOS12_MOD_DIR" "$IOS12_RESTORERAMDISK_FILENAME")"

    if [[ -z "$IOS7_ROOTFS" ]]; then die "Could not find target iOS root filesystem DMG"; fi
    if [[ -z "$IOS12_ROOTFS" ]]; then die "Could not find iOS 12 root filesystem DMG"; fi

    info "Replacing iOS 12 root filesystem with target iOS root filesystem..."
    echo "Target RootFS: $IOS7_ROOTFS"
    echo "iOS 12 RootFS: $IOS12_ROOTFS"

    if [[ "$TARGET_IOS" == 9.* ]]; then
        info "Rebuilding iOS 9 root filesystem DMG like surrealra1n..."
        rm -f "$BUILD_DIR/rootfs.raw"
        run_cmd "$BOOT/dmg" extract "$IOS7_ROOTFS" "$BUILD_DIR/rootfs.raw" -k "$ROOTFS_KEY" || return
        rm -f "$IOS12_ROOTFS"
        run_cmd "$BOOT/dmg" build "$BUILD_DIR/rootfs.raw" "$IOS12_ROOTFS" || return
    else
        cp "$IOS7_ROOTFS" "$IOS12_ROOTFS"
    fi

    cd "$BUILD_DIR" || die "Could not cd to build dir"

    info "Decrypting iBSS..."
    run_cmd "$BOOT/img4" -i "$IBSS_IM4P" -o iBSS.dec -k "$IBSS_KEY" || return

    info "Decrypting iBEC..."
    run_cmd "$BOOT/img4" -i "$IBEC_IM4P" -o iBEC.dec -k "$IBEC_KEY" || return

    info "Patching iBSS..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd "$BOOT/kairos" iBSS.dec iBSS.patched || return
    else
        run_cmd "$BOOT/ipatcher" iBSS.dec iBSS.patched || return
    fi

    info "Patching iBEC with restore boot args..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd "$BOOT/kairos" iBEC.dec iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" || return
    else
        run_cmd "$BOOT/ipatcher" iBEC.dec iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" || return
    fi

    info "Packing patched iBSS into iOS 12 IPSW destination..."
    run_cmd "$BOOT/img4" -i iBSS.patched -o "$IOS12_IBSS_IM4P" -A -T ibss || return

    info "Packing patched iBEC into iOS 12 IPSW destination..."
    run_cmd "$BOOT/img4" -i iBEC.patched -o "$IOS12_IBEC_IM4P" -A -T ibec || return

    info "Decrypting DeviceTree..."
    run_cmd "$BOOT/img4" -i "$DEVICETREE_IM4P" -o devicetree.raw -k "$DEVICETREE_KEY" || return

    info "Patching DeviceTree content-protect string..."

PATCH_COUNT="$(
python3 - <<'PY'
from pathlib import Path

path = Path("devicetree.raw")

old = b"content-protect"
new = b"content-protecV"

data = path.read_bytes()
count = data.count(old)

if count == 0:
    print(0)
    raise SystemExit(1)

data = data.replace(old, new)
path.write_bytes(data)

print(count)
PY
)"

PATCH_RESULT=$?

if [[ "$PATCH_RESULT" -ne 0 || "$PATCH_COUNT" -eq 0 ]]; then
    error "REQUIRED DeviceTree patch failed."
    error "Could not find content-protect in devicetree.raw."
    error "Resotre will hang at creating system keybags if this is not patched."
    echo
    echo "Debug:"
    echo "  File: $(pwd)/devicetree.raw"
    echo "  Expected string: content-protect"
    echo
    return 1
fi

success "DeviceTree patched. Replaced $PATCH_COUNT occurrence(s) of content-protect."

    info "Packing patched DeviceTree into iOS 12 IPSW destination..."
    run_cmd "$BOOT/img4" -i devicetree.raw -o "$IOS12_DEVICETREE_IM4P" -A -T rdtr || return

    info "Decrypting kernelcache raw..."
    run_cmd "$BOOT/img4" -i "$KCACHE_IM4P" -o kcache.raw -k "$KCACHE_KEY" || return

    info "Creating decrypted kernelcache im4p..."
    run_cmd "$BOOT/img4" -i "$KCACHE_IM4P" -o kcache.im4p -k "$KCACHE_KEY" -D || return

    info "Patching kernelcache..."
    if [[ "$TARGET_IOS" == 8.* ]]; then
        run_cmd "$BOOT/Kernel64Patcher" kcache.raw kcache.patched -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d || return
    elif [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd "$BOOT/Kernel64Patcher2" kcache.raw kcache.patched -u 9 -f 9 -k -v || return
    else
        run_cmd "$BOOT/Kernel64Patcher" kcache.raw kcache.patched -u 7 -m 7 -e 7 -f 7 -k || return
    fi

    info "Creating kernel binary patch..."
    run_cmd "$BOOT/kerneldiff" kcache.raw kcache.patched kcache.bpatch || return

    info "Applying kernel patch to iOS 12 IPSW destination kernelcache without signing..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        info "Packing iOS 9 restore kernelcache with img4 -J like surrealra1n..."
        run_cmd "$BOOT/img4" -i kcache.im4p -o "$IOS12_KCACHE_IM4P" -P kcache.bpatch -T rkrn -J || return
    else
        run_cmd "$BOOT/img4" -i kcache.im4p -o "$IOS12_KCACHE_IM4P" -P kcache.bpatch -T rkrn || return
    fi

    info "Decrypting target iOS restore ramdisk into iOS 12 restore ramdisk destination..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        rm -f ramdisk.raw asr asr_patched ents.plist
        run_cmd "$BOOT/img4" -i "$IOS7_RESTORERAMDISK" -o ramdisk.raw -k "$RESTORERAMDISK_KEY" || return
        info "Patching restore ramdisk ASR for iOS 9..."
        run_cmd "$BOOT/hfsplus" ramdisk.raw grow 40000000 || return
        run_cmd "$BOOT/hfsplus" ramdisk.raw extract usr/sbin/asr asr || return
        run_cmd "$BOOT/asr64_patcher" asr asr_patched || return

        info "Extracting ASR entitlements..."
        "$BOOT/ldid" -e asr > ents.plist || {
            error "Failed to extract ASR entitlements."
            return 1
        }

        if [[ ! -s ents.plist ]] || ! grep -q "<plist" ents.plist; then
            warn "ldid did not output a valid plist. Signing ASR without entitlement plist..."
            run_cmd "$BOOT/ldid" -S asr_patched || return
        else
            run_cmd "$BOOT/ldid" -Sents.plist asr_patched || return
        fi

        run_cmd "$BOOT/hfsplus" ramdisk.raw rm usr/sbin/asr || return
        run_cmd "$BOOT/hfsplus" ramdisk.raw add asr_patched usr/sbin/asr || return
        run_cmd "$BOOT/hfsplus" ramdisk.raw chmod 100755 usr/sbin/asr || return

        run_cmd "$BOOT/img4" -i ramdisk.raw -o "$IOS12_RESTORERAMDISK" -A -T rdsk || return
    else
        run_cmd "$BOOT/img4" -i "$IOS7_RESTORERAMDISK" -o "$IOS12_RESTORERAMDISK" -k "$RESTORERAMDISK_KEY" -D || return
    fi

    info "Zipping modified IPSW..."
    rm -f "$IOS7_IPSW"
    cd "$IOS12_MOD_DIR" || die "Could not cd to modified IPSW dir"
    run_cmd zip -0 -q -r "$IOS7_IPSW" * || return

    save_state

    success "Modified IPSW created successfully:"
    echo "$IOS7_IPSW"
    echo
    success "Saved target state: $DEVICE_TYPE / $BOARD / iOS $TARGET_IOS_DISPLAY"
    pause
}

#########################################
# opt 3: restore generated ipsw
#########################################

restore_ios7() {
    header
    check_restore_tools
    make_executable

    check_file "$IOS7_IPSW"

    if ! load_state; then
        return
    fi

    apply_restore_tool_profile_for_target || return

    echo -e "${YELLOW}WARNING:${NC}"
    echo "This will restore the generated modified IPSW:"
    echo "$IOS7_IPSW"
    echo
    echo "Target: $DEVICE_TYPE / $BOARD / iOS $TARGET_IOS_DISPLAY"
    echo
    read -rp "Continue with restore? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    pwn_dfu_loop "$BIN" "no"

    cd "$BIN" || die "Could not cd to bin"

    info "Resetting device with gaster..."
    run_cmd ./gaster reset || {
        error "gaster reset failed."
        pause
        return
    }

    info "Waiting 10 seconds..."
    sleep 10

if [[ -d "ios7" ]]; then

    info "Removing idevicerestore cached filesystem..."

    run_cmd sudo rm -rf ios7 || {
        error "Failed to remove cached filesystem."
        pause
        return
    }

fi
    info "Starting idevicerestore erase restore..."
    warn "You may be asked for your Mac password because this uses sudo."

    if [[ "$TARGET_IOS" == 9.* ]]; then
        if [[ -d "lib" ]]; then
            run_cmd sudo env LD_LIBRARY_PATH="lib" ./idevicerestore -ey ios7.ipsw || {
                error "Restore failed."
                pause
                return
            }
        else
            run_cmd sudo ./idevicerestore -ey ios7.ipsw || {
                error "Restore failed."
                pause
                return
            }
        fi
    else
        run_cmd sudo ./idevicerestore -e ios7.ipsw || {
            error "Restore failed."
            pause
            return
        }
    fi

    success "Restore command finished."

    if [[ "$TARGET_IOS" == 8.* || "$TARGET_IOS" == 9.* ]]; then
        warn "iOS $TARGET_IOS_DISPLAY restore needs dyld shared cache patched before normal setup/boot."
        warn "Use dsc64patcher with an SSH ramdisk before tethered boot."
    fi

    pause
}

#########################################
# shsh selecrt
#########################################

select_shsh() {
    header

    echo "Select your iPhone 5s iOS 12.5.8 SHSH2 blob."
    echo
    echo "Tip: you can drag the .shsh2 file into Terminal."
    echo

    SHSH_PATH="$(read_drag_path "SHSH2 path: ")"

    if [[ ! -f "$SHSH_PATH" ]]; then
        error "SHSH blob not found:"
        echo "$SHSH_PATH"
        echo
        warn "Try dragging the file again, or manually type the path without backslashes."
        pause
        return 1
    fi

    cp "$SHSH_PATH" "$BOOT/shsh.shsh2"

    success "Copied SHSH blob to:"
    echo "$BOOT/shsh.shsh2"

    return 0
}

#########################################
# opt 4: build tethered boot files
#########################################

build_boot_files() {
    header
    check_build_tools
    make_executable

    if ! load_state; then
        return
    fi

    apply_restore_tool_profile_for_target || return

    ensure_ios9_tools_if_needed
    check_dsc64patcher_for_target
    check_extra_tools_for_target

    echo -e "${YELLOW}Boot file builder:${NC}"
    echo "This builds patched iBSS, iBEC, DeviceTree, and Kernelcache."
    echo
    echo "Target: $DEVICE_TYPE / $BOARD / iOS $TARGET_IOS_DISPLAY"
    echo
    read -rp "Continue? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    select_shsh || return

    find_ios_component_paths "$IOS7_SRC_DIR"

    cd "$BOOT" || die "Could not cd to bin2boot"

    info "Extracting IM4M from SHSH..."
    run_cmd ./img4tool -e -s shsh.shsh2 -m im4m || return

    info "Decrypting iBSS..."
    run_cmd ./img4 -i "$IBSS_IM4P" -o iBSS.dec -k "$IBSS_KEY" || return

    info "Decrypting iBEC..."
    run_cmd ./img4 -i "$IBEC_IM4P" -o iBEC.dec -k "$IBEC_KEY" || return

    info "Patching iBSS..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd ./kairos iBSS.dec iBSS.patched || return
    else
        run_cmd ./ipatcher iBSS.dec iBSS.patched || return
    fi

    info "Patching iBEC with tethered boot args..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd ./kairos iBEC.dec iBEC.patched -b "-v" || return
    elif [[ "$TARGET_IOS" == 8.* ]]; then
        run_cmd ./ipatcher iBEC.dec iBEC.patched -b "-v rd=disk0s1s1 amfi=0xff cs_enforcement_disable=1 keepsyms=1 debug=0x2014e wdt=-1 PE_i_can_has_debugger=1 amfi_get_out_of_my_way=0x1 amfi_unrestrict_task_for_pid=0x0" || return
    else
        run_cmd ./ipatcher iBEC.dec iBEC.patched -b "-v rd=disk0s1s1" || return
    fi

    info "Building iBSS.img4..."
    run_cmd ./img4 -i iBSS.patched -o iBSS.img4 -A -T ibss -M im4m || return

    info "Building iBEC.img4..."
    run_cmd ./img4 -i iBEC.patched -o iBEC.img4 -A -T ibec -M im4m || return

    info "Decrypting DeviceTree..."
    run_cmd ./img4 -i "$DEVICETREE_IM4P" -o devicetree.raw -k "$DEVICETREE_KEY" || return

    info "Building DeviceTree.img4..."
    run_cmd ./img4 -i devicetree.raw -o DeviceTree.img4 -A -T rdtr -M im4m || return

    info "Decrypting kernelcache raw..."
    run_cmd ./img4 -i "$KCACHE_IM4P" -o kcache.raw -k "$KCACHE_KEY" || return

    info "Creating kernelcache im4p..."
    run_cmd ./img4 -i "$KCACHE_IM4P" -o kcache.im4p -k "$KCACHE_KEY" -D || return

    info "Patching kernelcache..."
    if [[ "$TARGET_IOS" == 8.* ]]; then
        run_cmd ./Kernel64Patcher kcache.raw kcache.patched -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d || return
    elif [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd ./Kernel64Patcher2 kcache.raw kcache.patched -u 9 -f 9 -k -v || return
    else
        run_cmd ./Kernel64Patcher kcache.raw kcache.patched -u 7 -m 7 -e 7 -f 7 -k || return
    fi

    info "Creating kernel binary patch..."
    run_cmd ./kerneldiff kcache.raw kcache.patched kcache.bpatch || return

    info "Building Kernelcache.img4..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        info "Packing iOS 9 boot Kernelcache with img4 -J like surrealra1n..."
        run_cmd ./img4 -i kcache.im4p -o Kernelcache.img4 -P kcache.bpatch -T rkrn -M im4m -J || return
    else
        run_cmd ./img4 -i kcache.im4p -o Kernelcache.img4 -P kcache.bpatch -T rkrn -M im4m || return
    fi

    success "Boot files built successfully."
    echo
    echo "Generated:"
    echo " - $BOOT/iBSS.img4"
    echo " - $BOOT/iBEC.img4"
    echo " - $BOOT/DeviceTree.img4"
    echo " - $BOOT/Kernelcache.img4"

    pause
}

#########################################
# opt 5: tehthered boot
#########################################

tethered_boot() {
    header
    check_boot_tools
    make_executable

    if ! load_state; then
        return
    fi

    check_file "$BOOT/iBSS.img4"
    check_file "$BOOT/iBEC.img4"
    check_file "$BOOT/DeviceTree.img4"
    check_file "$BOOT/Kernelcache.img4"

    echo -e "${YELLOW}Tethered boot:${NC}"
    echo "The device will go into pwnDFU mode, gaster reset, then 5sboot.sh will run."
    echo
    echo "Target: $DEVICE_TYPE / $BOARD / iOS $TARGET_IOS_DISPLAY"
    echo
    read -rp "Continue? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    pwn_dfu_loop "$BOOT" "yes" || {
        error "pwnDFU/reset failed."
        pause
        return
    }

    cd "$BOOT" || die "Could not cd to bin2boot"

    info "Running 5sboot.sh..."
    run_cmd ./5sboot.sh || {
        error "5sboot.sh failed."
        pause
        return
    }

    success "Boot script finished."
    pause
}


#########################################
# opt 6: patch ios 8/9 dyld
#########################################

patch_ios8_9_dyld() {
    header
    make_executable

    if ! load_state; then
        return
    fi

    if [[ "$TARGET_IOS" != 8.* && "$TARGET_IOS" != 9.* ]]; then
        error "dyld patching is only required for iOS 8.0 and iOS 9.3.4."
        pause
        return
    fi

    check_file "$BOOT/dsc64patcher"

    command -v git >/dev/null 2>&1 || die "git is required for iOS 8/9 support"

    if [[ ! -d "$BOOT/SSHRD_Script" ]]; then
        info "SSHRD_Script not found. Cloning..."

        run_cmd git clone https://github.com/iPh0ne4s/SSHRD_Script --recursive "$BOOT/SSHRD_Script" || {
            error "Failed to clone SSHRD_Script."
            return
        }
    fi

    check_file "$BOOT/SSHRD_Script/sshrd.sh"
    chmod +x "$BOOT/SSHRD_Script/sshrd.sh"

    cd "$BOOT/SSHRD_Script" || die "Could not cd to SSHRD_Script"

    info "Creating SSH ramdisk..."
    run_cmd ./sshrd.sh 12.0 || return

    info "Booting SSH ramdisk..."
    run_cmd ./sshrd.sh boot || return

    info "Waiting for ramdisk to boot..."
    sleep 15

    info "Starting iproxy..."
    pkill -f "iproxy 2222 22" 2>/dev/null
    iproxy 2222 22 >/dev/null 2>&1 &
    sleep 5

    info "Clearing old SSH host keys..."
    ssh-keygen -R "[localhost]:2222" >/dev/null 2>&1
    ssh-keygen -R "localhost" >/dev/null 2>&1

    info "Testing SSH connection..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "echo SSH_OK" || return

    info "Mounting root filesystem..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "/sbin/mount_hfs /dev/disk0s1s1 /mnt1" || return

    info "Downloading dyld shared cache..."
    scp -P2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost:/mnt1/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64 dyld.raw || return

    info "Patching dyld shared cache..."
    if [[ "$TARGET_IOS" == 9.* ]]; then
        run_cmd "$BOOT/dsc64patcher" dyld.raw dyld.patched -9 || return
    else
        run_cmd "$BOOT/dsc64patcher" dyld.raw dyld.patched -8 || return
    fi

    info "Uploading patched dyld shared cache..."
    scp -P2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null dyld.patched root@localhost:/mnt1/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64 || return

    info "Unmounting filesystem..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "/sbin/umount /mnt1"

    info "Rebooting device..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost "/sbin/reboot"

    success "iOS $TARGET_IOS_DISPLAY dyld shared cache patched."
    pause
}

#########################################
# opt 6: automatic full
#########################################

full_restore_and_boot() {
    header
    check_base_layout
    make_executable

    echo -e "${RED}FULL FLOW${NC}"
    echo
    echo "This will:"
    echo " 1) Build modified IPSW from target iOS + iOS 12.5.8 IPSWs"
    echo " 2) Restore generated bin/ios7.ipsw"
    echo " 3) Patch dyld shared cache for iOS 8/9 if needed"
    echo " 4) Ask for SHSH2 blob"
    echo " 5) Build tethered boot files"
    echo " 6) Enter pwnDFU again"
    echo " 7) Run 5sboot.sh"
    echo
    echo -e "${YELLOW}Supported only for iPhone 5s iOS 7.0.6 through 7.1.2, 8.0, 8.4, 9.3.2, and 9.3.4.${NC}"
    echo
    read -rp "Start full flow? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    build_modified_ipsw
    restore_ios7

    if [[ "$TARGET_IOS" == 8.* || "$TARGET_IOS" == 9.* ]]; then
    patch_ios8_9_dyld
    fi

    build_boot_files
    tethered_boot
}

#########################################
# info gui
#########################################

about_screen() {
    header

    echo "This tool builds a modified restore IPSW locally from IPSWs."
    echo
    echo "Supported devices:"
    echo " - iPhone 5s GSM  / iPhone6,1 / n51ap"
    echo " - iPhone 5s CDMA / iPhone6,2 / n53ap"
    echo
    echo "Supported target versions:"
    echo " - iOS 7.0.6"
    echo " - iOS 7.1.0"
    echo " - iOS 7.1.1"
    echo " - iOS 7.1.2"
    echo " - iOS 8.0"
    echo " - iOS 9.3.4"
    echo
    echo "Unsupported:"
    echo " - Below iOS 7.0.6"
    echo " - iOS 8.0.1-9.3.3"
    echo " - iOS 9.3.5 or newer"
    echo " - iPhone 5c or other devices"
    echo
    echo "Required files/folders:"
    echo " - 5sd7.sh"
    echo " - enc_keys"
    echo " - bin/"
    echo " - bin2boot/"
    echo
    echo "Required tools:"
    echo " - gaster"
    echo " - idevicerestore"
    echo " - iOS 9 temporarily refreshes img4/idevicerestore to the surrealra1n profile (-J/-y)"
    echo " - iOS 7/8 temporarily refreshes img4/idevicerestore to the legacy profile (-e/no -J)"
    echo " - img4"
    echo " - img4tool"
    echo " - ipatcher"
    echo " - Kernel64Patcher"
    echo " - Kernel64Patcher2 (iOS 9 only, auto downloads)"
    echo " - kairos (iOS 9 only, auto downloads)"
    echo " - asr64_patcher (iOS 9 only, auto builds)"
    echo " - hfsplus (iOS 9 only, auto downloads)"
    echo " - ldid (iOS 9 only, auto downloads)"
    echo " - dmg (iOS 9 only, auto downloads)"
    echo " - kerneldiff (auto downloads if missing)"
    echo " - dsc64patcher (iOS 8/9 only)"
    echo " - SSHRD_Script auto downloads (iOS 8/9 only)"
    echo " - 5sboot.sh"
    echo
    echo "Notes:"
    echo " - GSM uses n51ap files."
    echo " - CDMA uses n53ap files."
    echo " - This script does not include Apple firmware files."
    echo " - The user supplies IPSWs and SHSH blobs."

    pause
}

#########################################
# main menui
#########################################

main_menu() {
    while true; do
        header

        echo "WARNING:"
        echo "This tool is for iPhone 5s iOS 7.x/8.x/9.3.x tethered downgrades only."
        echo
        echo "Supported:"
        echo " - GSM  / n51ap / iPhone6,1"
        echo " - CDMA / n53ap / iPhone6,2"
        echo " - iOS 7.0.6, 7.1.0, 7.1.1, 7.1.2, 8.0, 8.4, 9.3.2, 9.3.4"
        echo
        echo "Unsupported: below 7.0.6, iOS 8.0.1-9.3.3, iOS 9.3.5+, iPhone 5c, other devices."
        echo
        echo "Menu"
        echo "----"
        echo "1) Return Everything To Normal"
        echo "2) Build Modified IPSW from IPSWs"
        echo "3) Restore Generated Modified IPSW"
        echo "4) Build Tethered Boot Files"
        echo "5) Tethered Boot Device"
        echo "6) Patch iOS 8/9 dyld Shared Cache"
        echo "7) Full Build + Restore + Boot"
        echo "8) About / Requirements"
        echo "0) Exit"
        echo

        read -rp "Choice: " choice

        case "$choice" in
            1) return_to_normal; restore_active_restore_tools_silent ;;
            2) build_modified_ipsw; restore_active_restore_tools_silent ;;
            3) restore_ios7; restore_active_restore_tools_silent ;;
            4) build_boot_files; restore_active_restore_tools_silent ;;
            5) tethered_boot; restore_active_restore_tools_silent ;;
            6) patch_ios8_9_dyld; restore_active_restore_tools_silent ;;
            7) full_restore_and_boot; restore_active_restore_tools_silent ;;
            8) about_screen; restore_active_restore_tools_silent ;;
            0) restore_active_restore_tools_silent; exit 0 ;;
            *) error "Invalid choice"; sleep 1 ;;
        esac
    done
}

main_menu
