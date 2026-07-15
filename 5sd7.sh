#!/usr/bin/env bash

#########################################
# iphone 5s legacy ios resotre downgrade tool
# gsm/cdma ipsw builder restore and bot
#########################################

VERSION="3.0"

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
    echo " iPhone 5s Legacy Restore / Downgrade Tool"
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


#########################################
#  dylib fucking installer
#########################################

ensure_legacy_ios_kit_macos_libs() {
    local install_dir="/usr/local/lib"
    local archive_url="https://github.com/LukeZGD/Legacy-iOS-Kit/archive/refs/heads/main.zip"
    local tmpdir archive source_dir
    local missing=0
    local lib

    local required_libs=(
        "libgeneral.0.dylib"
        "libideviceactivation-1.0.2.dylib"
        "libimg4tool.0.dylib"
        "libimobiledevice-1.0.6.dylib"
        "libimobiledevice-glue-1.0.0.dylib"
        "libirecovery-1.0.3.dylib"
        "libplist-2.0.4.dylib"
        "libusbmuxd-2.0.6.dylib"
    )

    if [[ "$(uname)" != "Darwin" ]]; then
        die "The Legacy iOS Kit dylib startup check only supports macOS."
    fi

    command -v sudo >/dev/null 2>&1 || die "sudo is required to check and install Legacy iOS Kit dylibs."

    # Authenticate once, then use sudo for every /usr/local/lib check as requested.
    sudo -v || die "sudo authentication failed."

    for lib in "${required_libs[@]}"; do
        if ! sudo test -f "$install_dir/$lib"; then
            missing=1
        fi
    done

    # All eight required dylibs exist, so continue startup without downloading.
    if [[ "$missing" -eq 0 ]]; then
        return 0
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to download Legacy iOS Kit."
    command -v unzip >/dev/null 2>&1 || die "unzip is required to extract Legacy iOS Kit."

    warn "One or more required Legacy iOS Kit dylibs are missing."
    info "Downloading the complete Legacy iOS Kit macOS library folder..."

    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/5sd7-legacy-ios-kit.XXXXXX")" || \
        die "Could not create a temporary download folder."
    archive="$tmpdir/Legacy-iOS-Kit-main.zip"

    if ! curl -fL --retry 3 --connect-timeout 20 -o "$archive" "$archive_url"; then
        rm -rf "$tmpdir"
        die "Failed to download Legacy iOS Kit from GitHub."
    fi

    if ! unzip -q "$archive" -d "$tmpdir"; then
        rm -rf "$tmpdir"
        die "Failed to extract the Legacy iOS Kit archive."
    fi

    source_dir="$(find "$tmpdir" -type d -path '*/bin/macos/lib' -print -quit)"
    if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
        rm -rf "$tmpdir"
        die "Could not find Legacy-iOS-Kit/bin/macos/lib in the downloaded archive."
    fi

    # Refuse to install a partial or incomplete download.
    for lib in "${required_libs[@]}"; do
        if [[ ! -f "$source_dir/$lib" ]]; then
            rm -rf "$tmpdir"
            die "Downloaded Legacy iOS Kit library folder is incomplete. Missing: $lib"
        fi
    done

    info "Installing every file from Legacy-iOS-Kit/bin/macos/lib into $install_dir..."
    sudo mkdir -p "$install_dir" || {
        rm -rf "$tmpdir"
        die "Could not create $install_dir."
    }

    sudo cp -R "$source_dir/." "$install_dir/" || {
        rm -rf "$tmpdir"
        die "Failed to copy Legacy iOS Kit libraries into $install_dir."
    }

    rm -rf "$tmpdir"

    # Verify the complete required set after installation, not merely a partial copy.
    for lib in "${required_libs[@]}"; do
        if ! sudo test -f "$install_dir/$lib"; then
            die "Legacy iOS Kit library installation is incomplete. Missing: $install_dir/$lib"
        fi
    done

    success "All required Legacy iOS Kit dylibs are installed in $install_dir."
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
        profile="ios9_restore_profile"
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
        profile="ios9_restore_profile"
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
    # 7:  firmware/dfu/ibss.n51ap.release.im4p or ibss.n53ap.release.im4p
    # 12: firmware/dfu/ibss.iphone6.release.im4p and ibec.iphone6.release.im4p
    IOS12_IBSS_IM4P="$(first_file "$dst/Firmware/dfu" -name "iBSS.iphone6.RELEASE.im4p")"
    IOS12_IBEC_IM4P="$(first_file "$dst/Firmware/dfu" -name "iBEC.iphone6.RELEASE.im4p")"

    #  12 dtre is directly in firmware/all_flash, not inside all_flash.n51ap.production.
    # gsm  = devicetree.n51ap.im4p
    # cdma = devicetree.n53ap.im4p
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
        info "Rebuilding iOS 9 root filesystem DMG..."
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
        info "Packing iOS 9 restore kernelcache with img4 -J..."
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
        info "Packing iOS 9 boot Kernelcache with img4 -J..."
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

full_old() {
    header
    check_base_layout
    make_executable

    echo -e "${RED}FULL FLOW - LEGACY TETHERED${NC}"
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
    echo -e "${YELLOW}Supported here: iOS 7.0.6 through 7.1.2, 8.0, 8.4, 9.3.2, and 9.3.4.${NC}"
    echo
    read -rp "Start legacy full flow? Type YES: " confirm

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

full_1021() {
    header
    check_base_layout
    make_executable

    echo -e "${RED}FULL FLOW - iOS 10.2.1 TETHERED${NC}"
    echo
    echo "This will:"
    echo " 1) Run the iOS 10.2.1 tethered restore"
    echo " 2) Then run the iOS 10 tether boot option"
    echo
    warn "After restore, put the phone back into DFU when the boot step asks."
    echo
    read -rp "Start iOS 10.2.1 full flow? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    ios10_1021_restore || return
    ios10_boot
}

full_1033() {
    header
    check_base_layout
    make_executable

    echo -e "${RED}FULL FLOW - iOS 10.3.3 OTA UNTETHERED${NC}"
    echo
    echo "This will run the iOS 10.3.3 OTA untethered restore."
    echo
    warn "Signing is OTA-only, but the final restore still uses the normal 10.3.3 Restore IPSW payload."
    echo
    read -rp "Start iOS 10.3.3 OTA flow? Type YES: " confirm

    if [[ "$confirm" != "YES" ]]; then
        warn "Cancelled."
        pause
        return
    fi

    ios10_1033_restore
}

full_restore_and_boot() {
    header

    echo -e "${RED}FULL FLOW${NC}"
    echo
    echo "Pick a full flow:"
    echo
    echo "1) Legacy iOS 7/8/9 tethered flow"
    echo "2) iOS 10.2.1 tethered flow"
    echo "3) iOS 10.3.3 OTA untethered flow"
    echo "4) iOS 11.3 tethered flow"
    echo "5) iOS 12.0 tethered flow"
    echo
    read -rp "Choice: " flow_choice

    case "$flow_choice" in
        1) full_old ;;
        2) full_1021 ;;
        3) full_1033 ;;
        4) ios11_113_restore ;;
        5) ios12_120_restore ;;
        *)
            error "Invalid full flow choice."
            pause
            return 1
            ;;
    esac
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
    echo " - iOS 10.2.1 tethered"
    echo " - iOS 10.3.3 OTA untethered"
    echo " - iOS 11.3 tethered"
    echo " - iOS 12.0 tethered"
    echo
    echo "Unsupported:"
    echo " - Below iOS 7.0.6"
    echo " - random in-between builds this script does not handle"
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
    echo " - iOS 9 temporarily refreshes img4/idevicerestore to the iOS 9 restore profile (-J/-y)"
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
    echo " - The user supplies IPSWs, OTA packages, and SHSH blobs."
    echo " - iOS 10.3.3 uses OTA signing, but still needs the normal restore IPSW as payload."
    echo " - iOS 11.3 tethered uses latest signed 12.5.8 blobs/SEP."
    echo " - iOS 12.0 tethered uses latest signed 12.5.8 blobs/SEP."
    echo " - iOS 10/11/12/12 boot files can be rebuilt from the menu if bin2boot gets wiped."

    pause
}

#########################################
# ios 10 restore paths
#########################################

IOS10_IDENTIFIER=""
IOS10_BUILD=""
IOS10_LATEST_VERSION=""
IOS10_LATEST_BUILD=""
IOS10_TARGET_IPSW=""
IOS10_LATEST_IPSW=""
IOS10_SHSH_PATH=""
IOS10_ECID=""
IOS10_SEP_PATH=""
IOS10_SEP_MANIFEST=""

IOS10_103_IPSW_URL="http://appldnld.apple.com/ios10.3/091-02949-20170327-7584B286-0D86-11E7-A4FA-7ECE122AC769/iPhone_4.0_64bit_10.3_14E277_Restore.ipsw"
IOS10_1033_IPSW_URL="http://appldnld.apple.com/ios10.3.3/091-23133-20170719-CA8E78E6-6977-11E7-968B-2B9100BA0AE3/iPhone_4.0_64bit_10.3.3_14G60_Restore.ipsw"

ios10_stat_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

ios10_find_dmg() {
    local dir="$1"
    local mode="$2"
    local max_size="${3:-}"

    find "$dir" -type f -name "*.dmg" ! -name "._*" -print |
    while IFS= read -r f; do
        local size
        size="$(ios10_stat_size "$f")" || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf "%s %s\n" "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

ios10_parse_plist_value() {
    local ipsw="$1"
    local key="$2"
    unzip -p "$ipsw" BuildManifest.plist 2>/dev/null |
        awk -v k="$key" '
            $0 ~ "<key>" k "</key>" {
                getline
                gsub(/.*<string>/, "")
                gsub(/<\/string>.*/, "")
                print
                exit
            }
        '
}

ios10_set_build_from_ipsw_or_default() {
    local ipsw="$1"
    local default_build="$2"
    local parsed_build=""

    # do not verify/reject ipsws here. only read the build tag for futurerestore's
    # /tmp/futurerestore/ibss.<board>.<build>.patched.img4 naming.
    parsed_build="$(ios10_parse_plist_value "$ipsw" ProductBuildVersion || true)"

    if [[ -z "$parsed_build" ]]; then
        warn "Could not read ProductBuildVersion from IPSW. Using default build $default_build."
        IOS10_BUILD="$default_build"
    else
        IOS10_BUILD="$parsed_build"
    fi

    info "Using build tag for futurerestore prepatched iBSS/iBEC: $IOS10_BUILD"
}


ios10_select_5s_model() {
    header
    echo "Select iPhone 5s model for iOS 10:"
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
            IOS10_IDENTIFIER="iPhone6,1"
            ;;
        2)
            DEVICE_TYPE="CDMA"
            BOARD="n53ap"
            BOARD_SHORT="n53"
            IOS10_IDENTIFIER="iPhone6,2"
            ;;
        *)
            error "Invalid model selection."
            pause
            return 1
            ;;
    esac
}

ios10_enc_key() {
    local ios="$1"
    local component="$2"
    require_enc_value "$DEVICE_TYPE" "$ios" "$component"
}

ensure_ios10_tools() {
    check_base_layout
    make_executable

    if [[ "$(uname)" != "Darwin" ]]; then
        die "The iOS 10 helpers in this 5sd7 build are set up for macOS only."
    fi

    ensure_core_build_tools_if_missing || return

    download_darwin_tool_both_bins "img4tool" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4tool" || return
    download_darwin_tool_both_bins "pzb" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/pzb" || return
    download_darwin_tool_both_bins "irecovery" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/irecovery" || return
    download_darwin_tool_both_bins "kairos" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos" || return
    download_darwin_tool_both_bins "KPlooshFinder" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/KPlooshFinder" || return
    download_darwin_tool_both_bins "iBoot64Patcher" "https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/iBoot64Patcher" || return
    download_darwin_tool_both_bins "hfsplus" "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus" || return
    download_darwin_tool_both_bins "tsschecker" "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/tsschecker" || return
    download_ldid_both_bins || return
    compile_asr64_patcher_both_bins || return
    ensure_futurerestore_macos || return

    chmod +x "$BIN"/* "$BOOT"/* 2>/dev/null || true
}

ensure_futurerestore_macos() {
    mkdir -p "$SCRIPT_DIR/futurerestore"

    if [[ -x "$SCRIPT_DIR/futurerestore/futurerestore" ]]; then
        return 0
    fi

    command -v curl >/dev/null 2>&1 || die "curl is required to download futurerestore"
    command -v unzip >/dev/null 2>&1 || die "unzip is required to install futurerestore"
    command -v tar >/dev/null 2>&1 || die "tar is required to install futurerestore"

    info "futurerestore missing. Downloading macOS release..."
    rm -rf "$WORK/futurerestore_dl"
    mkdir -p "$WORK/futurerestore_dl"

    run_cmd curl -L -o "$WORK/futurerestore_dl/futurerestore.zip" "https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-macOS-RELEASE-main.zip" || return

    (
        cd "$WORK/futurerestore_dl" || exit 1
        unzip -q -o futurerestore.zip
        found_tar="$(find . -name "*.tar.xz" -type f | head -n 1)"
        if [[ -z "$found_tar" ]]; then
            echo "Could not find futurerestore tarball inside zip."
            exit 1
        fi
        tar -xf "$found_tar"
    ) || return

    found_fr="$(find "$WORK/futurerestore_dl" -type f -name futurerestore | head -n 1)"
    if [[ -z "$found_fr" ]]; then
        error "Could not find futurerestore binary after extraction."
        return 1
    fi

    cp "$found_fr" "$SCRIPT_DIR/futurerestore/futurerestore"
    chmod +x "$SCRIPT_DIR/futurerestore/futurerestore"
}

ios10_detect_or_prompt_ecid() {
    IOS10_ECID=""

    if command -v ideviceinfo >/dev/null 2>&1; then
        IOS10_ECID="$(ideviceinfo -k UniqueChipID 2>/dev/null | tr -d '\r\n ' || true)"
    fi

    if [[ -z "$IOS10_ECID" && -x "$BIN/irecovery" ]]; then
        IOS10_ECID="$("$BIN/irecovery" -q 2>/dev/null | awk -F': ' '/^ECID:/ {print $2; exit}' | tr -d '\r\n ' || true)"
    fi

    if [[ -z "$IOS10_ECID" ]]; then
        echo
        warn "Could not auto-detect ECID."
        echo "Enter the device ECID. Decimal or 0x hex usually works with tsschecker."
        read -rp "ECID: " IOS10_ECID
        IOS10_ECID="$(printf "%s" "$IOS10_ECID" | tr -d '[:space:]')"
    fi

    if [[ -z "$IOS10_ECID" ]]; then
        error "ECID is required."
        return 1
    fi

    success "Using ECID: $IOS10_ECID"
}

ios10_download_1033_ota_sep() {
    local tmpdir="$WORK/ios10_sep"
    local sep_name="sep-firmware.${BOARD_SHORT}.RELEASE.im4p"

    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"

    IOS10_SEP_PATH="$tmpdir/$sep_name"
    IOS10_SEP_MANIFEST="$tmpdir/BuildManifest-SEP.plist"

    info "Downloading iOS 10.3.3 OTA SEP manifest for $IOS10_IDENTIFIER..."
    run_cmd curl -L -o "$IOS10_SEP_MANIFEST" "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/manifest/BuildManifest_${IOS10_IDENTIFIER}_10.3.3.plist" || return

    info "Fetching $sep_name from iOS 10.3.3 OTA IPSW..."
    (
        cd "$tmpdir" || exit 1
        "$BIN/pzb" -g "Firmware/all_flash/$sep_name" "$IOS10_1033_IPSW_URL"
    ) || return

    if [[ ! -f "$IOS10_SEP_PATH" ]]; then
        error "SEP download failed. Missing $IOS10_SEP_PATH"
        return 1
    fi
}

ios10_fetch_shsh_for_latest() {
    local outdir="$WORK/ios10_shsh_latest"
    rm -rf "$outdir"
    mkdir -p "$outdir"

    info "Fetching SHSH for iOS $IOS10_LATEST_VERSION..."
    run_cmd sudo "$BIN/tsschecker" -d "$IOS10_IDENTIFIER" -s -e "$IOS10_ECID" -i "$IOS10_LATEST_VERSION" --save-path "$outdir" || return

    IOS10_SHSH_PATH="$(find "$outdir" -type f -name "*.shsh2" | head -n 1)"
    if [[ -z "$IOS10_SHSH_PATH" ]]; then
        error "No SHSH2 file was saved."
        return 1
    fi

    if ! grep -q "<key>generator</key>" "$IOS10_SHSH_PATH" 2>/dev/null; then
        error "Saved SHSH2 does not contain a generator."
        warn "Delete $outdir and try again, or use a latest SHSH2 blob that contains a generator."
        return 1
    fi
}

ios10_fetch_1033_ota_shsh() {
    local outdir="$WORK/ios10_shsh_1033"
    rm -rf "$outdir"
    mkdir -p "$outdir"

    info "Fetching iOS 10.3.3 OTA SHSH..."
    run_cmd sudo "$BIN/tsschecker" -d "$IOS10_IDENTIFIER" -i 10.3.3 -e "$IOS10_ECID" -o -m "$IOS10_SEP_MANIFEST" -s --save-path "$outdir" || return

    IOS10_SHSH_PATH="$(find "$outdir" -type f -name "*.shsh2" | head -n 1)"
    if [[ -z "$IOS10_SHSH_PATH" ]]; then
        error "No iOS 10.3.3 OTA SHSH2 file was saved."
        return 1
    fi
}


ios10_copy_if_different() {
    local src="$1"
    local dst="$2"

    if [[ "$src" == "$dst" ]]; then
        return 0
    fi

    sudo cp -f "$src" "$dst" || return
}

ios10_copy_prepatched_iboot_aliases() {
    local primary_ibss="$1"
    local primary_ibec="$2"
    local build="$3"
    local target_build="${4:-}"
    local b=""
    local tag=""
    local seen=" "

    for b in "$BOARD" "$BOARD_SHORT"; do
        [[ -n "$b" ]] || continue

        for tag in "$build" "$target_build" "$IOS10_BUILD" "$IOS10_LATEST_BUILD" "14D27" "16H88"; do
            [[ -n "$tag" ]] || continue
            case "$seen" in
                *" $b:$tag "*) continue ;;
            esac
            seen="$seen$b:$tag "

            ios10_copy_if_different "$primary_ibss" "/tmp/futurerestore/ibss.$b.$tag.patched.img4" || return
            ios10_copy_if_different "$primary_ibec" "/tmp/futurerestore/ibec.$b.$tag.patched.img4" || return
        done
    done
}


ios10_extract_ota_file_by_basename() {
    local archive="$1"
    local basename="$2"
    local outdir="$3"
    local found=""

    found="$(unzip -Z1 "$archive" 2>/dev/null | awk -v b="$basename" '
        $0 == b || $0 ~ "/" b "$" { print; exit }
    ')"

    if [[ -z "$found" ]]; then
        error "Could not find $basename inside the signed 10.3.3 OTA package."
        warn "This option expects the signed iOS 10.3.3 OTA zip/package, not a normal IPSW."
        warn "Showing possible DFU/iBSS/iBEC paths from the archive:"
        unzip -Z1 "$archive" 2>/dev/null | grep -Ei 'iBSS|iBEC|Firmware/dfu|AssetData' | head -n 40 || true
        return 1
    fi

    info "Extracting $basename from $found..."
    unzip -j "$archive" "$found" -d "$outdir" >/dev/null || return
}


ios10_prepatch_restore_iboots() {
    local target_ipsw="$1"
    local target_ios="$2"
    local build="$3"
    local w="$WORK/ios10_iboot_patch"
    local im4m="$w/${IOS10_IDENTIFIER}.im4m"
    local target_ibss_file="iBSS.${BOARD_SHORT}.RELEASE.im4p"
    local target_ibec_file="iBEC.${BOARD_SHORT}.RELEASE.im4p"
    local source_ibss_file="$target_ibss_file"
    local source_ibec_file="$target_ibec_file"
    local key_ios="$target_ios"
    local ibss_src=""
    local ibec_src=""
    local ibss_key ibec_key

   
    if [[ "$target_ios" == "10.3.3" || "$target_ios" == 11.* || "$target_ios" == 12.* ]]; then
        target_ibss_file="iBSS.iphone6.RELEASE.im4p"
        target_ibec_file="iBEC.iphone6.RELEASE.im4p"
        source_ibss_file="$target_ibss_file"
        source_ibec_file="$target_ibec_file"
    fi

    rm -rf "$w"
    mkdir -p "$w"
    sudo mkdir -p /tmp/futurerestore

    run_cmd "$BOOT/img4tool" -s "$IOS10_SHSH_PATH" -e -m "$im4m" || return

    if [[ "$target_ios" == 10.1* || "$target_ios" == 10.2* ]]; then
        key_ios="10.3"
        source_ibss_file="iBSS.iphone6.RELEASE.im4p"
        source_ibec_file="iBEC.iphone6.RELEASE.im4p"
        info "Preparing iBSS/iBEC..."
        (
            cd "$w" || exit 1
            "$BIN/pzb" -g "Firmware/dfu/$source_ibss_file" "$IOS10_103_IPSW_URL"
            "$BIN/pzb" -g "Firmware/dfu/$source_ibec_file" "$IOS10_103_IPSW_URL"
        ) || return
    else
        if [[ "$target_ios" == "10.3.3" ]]; then
            ios10_extract_ota_file_by_basename "$target_ipsw" "$target_ibss_file" "$w" || return
            ios10_extract_ota_file_by_basename "$target_ipsw" "$target_ibec_file" "$w" || return
        else
            info "Extracting $target_ibss_file..."
            unzip -j "$target_ipsw" "Firmware/dfu/$target_ibss_file" -d "$w" >/dev/null || return
            info "Extracting $target_ibec_file..."
            unzip -j "$target_ipsw" "Firmware/dfu/$target_ibec_file" -d "$w" >/dev/null || return
        fi
    fi

    # pzb may save files either in the current directory or inside the original ipsw path.
    # example:
    #   $w/ibss.iphone6.release.im4p
    # or:
    #   $w/firmware/dfu/ibss.iphone6.release.im4p
    if [[ -f "$w/$source_ibss_file" ]]; then
        ibss_src="$w/$source_ibss_file"
    elif [[ -f "$w/Firmware/dfu/$source_ibss_file" ]]; then
        ibss_src="$w/Firmware/dfu/$source_ibss_file"
    else
        ibss_src="$(find "$w" -type f -name "$source_ibss_file" | head -n 1)"
    fi

    if [[ -f "$w/$source_ibec_file" ]]; then
        ibec_src="$w/$source_ibec_file"
    elif [[ -f "$w/Firmware/dfu/$source_ibec_file" ]]; then
        ibec_src="$w/Firmware/dfu/$source_ibec_file"
    else
        ibec_src="$(find "$w" -type f -name "$source_ibec_file" | head -n 1)"
    fi

    check_file "$ibss_src"
    check_file "$ibec_src"

    info "Found iBSS."
    info "Found iBEC."

    # do not use ios10_enc_key inside command substitution here.
    # if a key is missing, require_enc_value/die output gets swallowed by $(...).
    ibss_key="$(get_enc_value "$DEVICE_TYPE" "$key_ios" "IBSS")"
    ibec_key="$(get_enc_value "$DEVICE_TYPE" "$key_ios" "IBEC")"

    if [[ -z "$ibss_key" || "$ibss_key" == "MISSING" ]]; then
        error "Missing enc_keys value for $DEVICE_TYPE | $key_ios | IBSS"
        if [[ "$key_ios" == "10.3" ]]; then
            warn "iOS 10.2.1 restore uses the iOS 10.3 shared iphone6 iBSS/iBEC workaround."
            warn "Add the iOS 10.3 iBSS.iphone6.RELEASE.im4p key to enc_keys."
        fi
        return 1
    fi

    if [[ -z "$ibec_key" || "$ibec_key" == "MISSING" ]]; then
        error "Missing enc_keys value for $DEVICE_TYPE | $key_ios | IBEC"
        if [[ "$key_ios" == "10.3" ]]; then
            warn "iOS 10.2.1 restore uses the iOS 10.3 shared iphone6 iBSS/iBEC workaround."
            warn "Add the iOS 10.3 iBEC.iphone6.RELEASE.im4p key to enc_keys."
        fi
        return 1
    fi

    info "Patching iBSS..."
    run_cmd "$BOOT/img4" -i "$ibss_src" -o "$w/iBSS.raw" -k "$ibss_key" || return
    info "Patching iBEC..."
    run_cmd "$BOOT/img4" -i "$ibec_src" -o "$w/iBEC.raw" -k "$ibec_key" || return

    run_cmd "$BIN/iBoot64Patcher" "$w/iBSS.raw" "$w/iBSS.patched" || return
    run_cmd "$BIN/iBoot64Patcher" "$w/iBEC.raw" "$w/iBEC.patched" -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" -n || return

    sudo mkdir -p /tmp/futurerestore
    sudo rm -f "/tmp/futurerestore/ibss.${BOARD}."*.patched.img4 "/tmp/futurerestore/ibec.${BOARD}."*.patched.img4 2>/dev/null || true
    sudo rm -f "/tmp/futurerestore/ibss.${BOARD_SHORT}."*.patched.img4 "/tmp/futurerestore/ibec.${BOARD_SHORT}."*.patched.img4 2>/dev/null || true

    run_cmd sudo "$BOOT/img4" -i "$w/iBSS.patched" -o "/tmp/futurerestore/ibss.${BOARD}.${build}.patched.img4" -A -T ibss -M "$im4m" || return
    run_cmd sudo "$BOOT/img4" -i "$w/iBEC.patched" -o "/tmp/futurerestore/ibec.${BOARD}.${build}.patched.img4" -A -T ibec -M "$im4m" || return

    ios10_copy_prepatched_iboot_aliases \
        "/tmp/futurerestore/ibss.${BOARD}.${build}.patched.img4" \
        "/tmp/futurerestore/ibec.${BOARD}.${build}.patched.img4" \
        "$build" "$IOS10_BUILD" || return

    info "Ready files:"
    find /tmp/futurerestore -maxdepth 1 -type f \( -name "ibss.*.patched.img4" -o -name "ibec.*.patched.img4" \) -print 2>/dev/null | sort
}

ios10_patch_asr_ramdisk_to_path() {
    local src_dmg="$1"
    local out_im4p="$2"
    local grow_size="$3"
    local work_tag="$4"
    local w="$WORK/ios10_ramdisk_${work_tag}"

    rm -rf "$w"
    mkdir -p "$w"

    run_cmd "$BOOT/img4" -i "$src_dmg" -o "$w/ramdisk.raw" || return
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" grow "$grow_size" || return
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" extract usr/sbin/asr "$w/asr" || return
    run_cmd "$BOOT/asr64_patcher" "$w/asr" "$w/asr_patched" || return

    "$BOOT/ldid" -e "$w/asr" > "$w/ents.plist" || true
    if [[ -s "$w/ents.plist" ]] && grep -q "<plist" "$w/ents.plist"; then
        run_cmd "$BOOT/ldid" -S"$w/ents.plist" "$w/asr_patched" || return
    else
        run_cmd "$BOOT/ldid" -S "$w/asr_patched" || return
    fi

    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" rm usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" add "$w/asr_patched" usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" chmod 100755 usr/sbin/asr || return
    run_cmd "$BOOT/img4" -i "$w/ramdisk.raw" -o "$out_im4p" -T rdsk -A || return
}

ios10_get_custom_manifest_1021() {
    local outdir="$WORK/ios10_manifest"
    local out="$outdir/BuildManifest.plist"
    local local_manifest="$SCRIPT_DIR/manifest/$IOS10_IDENTIFIER/10.2.1-Manifest.plist"

    mkdir -p "$outdir"

    if [[ -f "$local_manifest" ]]; then
        printf "%s" "$local_manifest"
        return 0
    fi

    echo -e "${BLUE}[INFO]${NC} Getting custom manifest..." >&2
    echo >&2
    echo -e "${PURPLE}>> curl -fL -o $out https://github.com/pwnerblu/surrealra1n/raw/refs/heads/main/manifest/$IOS10_IDENTIFIER/10.2.1-Manifest.plist${NC}" >&2

    if curl -fL -o "$out" "https://github.com/pwnerblu/surrealra1n/raw/refs/heads/main/manifest/$IOS10_IDENTIFIER/10.2.1-Manifest.plist" >&2; then
        printf "%s" "$out"
        return 0
    fi

    echo -e "${RED}[ERROR]${NC} Could not get custom 10.2.1 manifest for $IOS10_IDENTIFIER." >&2
    echo -e "${YELLOW}[WARN]${NC} Put it here if you already have local manifest files:" >&2
    echo -e "${YELLOW}[WARN]${NC} $local_manifest" >&2
    return 1
}

ios10_patch_asr_ramdisk_file() {
    local src_dmg="$1"
    local out_im4p="$2"
    local w="$WORK/ios10_ramdisk"

    rm -rf "$w"
    mkdir -p "$w"

    run_cmd "$BOOT/img4" -i "$src_dmg" -o "$w/ramdisk.raw" || return
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" grow 60000000 || return
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" extract usr/sbin/asr "$w/asr" || return
    run_cmd "$BOOT/asr64_patcher" "$w/asr" "$w/asr_patched" || return

    "$BOOT/ldid" -e "$w/asr" > "$w/ents.plist" || true
    if [[ -s "$w/ents.plist" ]] && grep -q "<plist" "$w/ents.plist"; then
        run_cmd "$BOOT/ldid" -S"$w/ents.plist" "$w/asr_patched" || return
    else
        run_cmd "$BOOT/ldid" -S "$w/asr_patched" || return
    fi

    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" rm usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" add "$w/asr_patched" usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" chmod 100755 usr/sbin/asr || return
    run_cmd "$BOOT/img4" -i "$w/ramdisk.raw" -o "$out_im4p" -A -T rdsk || return
}

ios10_make_tether_restore_files() {
    local target_ipsw="$1"
    local latest_ipsw="$2"
    local restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/10.2.1"
    local w="$WORK/ios10_make"
    local target="$w/target"
    local latest="$w/latest"
    local allflash="all_flash.${BOARD}.production"
    local target_llb="LLB.${BOARD_SHORT}.RELEASE.im4p"
    local target_iboot="iBoot.${BOARD_SHORT}.RELEASE.im4p"
    local latest_llb="$latest/Firmware/all_flash/LLB.iphone6.RELEASE.im4p"
    local latest_iboot="$latest/Firmware/all_flash/iBoot.iphone6.RELEASE.im4p"
    local target_kernel="$target/kernelcache.release.${BOARD_SHORT}"
    local restore_ramdisk=""

    rm -rf "$w"
    mkdir -p "$target" "$latest" "$restoredir"

    info "Unpacking IPSWs..."
    run_cmd unzip -q "$target_ipsw" -d "$target" || return
    run_cmd unzip -q "$latest_ipsw" -d "$latest" || return

    check_file "$latest_llb"
    check_file "$latest_iboot"
    check_file "$target/Firmware/all_flash/$allflash/$target_llb"
    check_file "$target/Firmware/all_flash/$allflash/$target_iboot"
    check_file "$target_kernel"

    info "Adding LLB/iBoot..."
    cp "$latest_llb" "$target/Firmware/all_flash/$allflash/$target_llb" || return
    cp "$latest_iboot" "$target/Firmware/all_flash/$allflash/$target_iboot" || return

    info "Building custom IPSW..."
    rm -f "$restoredir/custom.ipsw"
    (
        cd "$target" || exit 1
        zip -0 -q -r "$restoredir/custom.ipsw" *
    ) || return

    restore_ramdisk="$(ios10_find_dmg "$target" smallest)"
    if [[ -z "$restore_ramdisk" ]]; then
        error "Could not find restore ramdisk DMG."
        return 1
    fi

    info "Making kernel file..."
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$w/kernel.raw" || return
    run_cmd "$BIN/KPlooshFinder" "$w/kernel.raw" "$w/kernel.patched" || return
    run_cmd "$BOOT/kerneldiff" "$w/kernel.raw" "$w/kernel.patched" "$w/kernel.diff" || return
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" -J || \
        run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" || return

    info "Making ramdisk file..."
    ios10_patch_asr_ramdisk_file "$restore_ramdisk" "$restoredir/ramdisk.im4p" || return

    rm -f "$restoredir/updateramdisk.im4p"
    echo "v5_target_base_restore" > "$restoredir/.5sd7_ios10_custom_method"

    success "iOS 10.2.1 restore files ready in $restoredir"
}

ios10_prepare_custom_restore_mode() {
    local custom_ipsw="$1"
    local shsh_path="$2"
    local w="$WORK/ios10_custom_restore_boot"
    local ibss_file="iBSS.iphone6.RELEASE.im4p"
    local ibec_file="iBEC.iphone6.RELEASE.im4p"
    local mode=""

    rm -rf "$w"
    mkdir -p "$w"

    info "Preparing restore mode..."
    run_cmd "$BOOT/img4tool" -s "$shsh_path" -e -m "$w/im4m" || return

    unzip -j "$custom_ipsw" "Firmware/dfu/$ibss_file" -d "$w" >/dev/null || return
    unzip -j "$custom_ipsw" "Firmware/dfu/$ibec_file" -d "$w" >/dev/null || return

    run_cmd "$BOOT/img4" -i "$w/$ibss_file" -o "$w/iBSS.img4" -M "$w/im4m" -T ibss || return
    run_cmd "$BOOT/img4" -i "$w/$ibec_file" -o "$w/iBEC.img4" -M "$w/im4m" -T ibec || return

    run_cmd "$BIN/irecovery" -f "$w/iBSS.img4" || return
    run_cmd "$BIN/irecovery" -f "$w/iBEC.img4" || return

    sleep 3
    mode="$("$BIN/irecovery" -q 2>/dev/null | awk -F': ' '/^MODE:/ {print $2; exit}' | tr -d '\r\n ' || true)"

    if [[ "$mode" != "Recovery" ]]; then
        error "Device did not enter Recovery after sending custom iBSS/iBEC. Current mode: ${mode:-unknown}"
        return 1
    fi

    success "Device is in Recovery mode for custom futurerestore."
}

ios10_run_futurerestore_plain() {
    local exit_code=0

    info "Starting futurerestore custom restore..."
    echo
    echo -e "${PURPLE}>> sudo $SCRIPT_DIR/futurerestore/futurerestore $*${NC}"

    set +e
    sudo "$SCRIPT_DIR/futurerestore/futurerestore" "$@"
    exit_code=$?
    set -e

    return "$exit_code"
}


ios_bootset_save() {
    local tag="$1"
    local device="$2"
    local board="$3"
    local dir="$BOOT/bootsets/$tag"

    mkdir -p "$dir"

    cp -f "$BOOT/iBSS.img4" "$dir/iBSS.img4" || return
    cp -f "$BOOT/iBEC.img4" "$dir/iBEC.img4" || return
    cp -f "$BOOT/DeviceTree.img4" "$dir/DeviceTree.img4" || return
    cp -f "$BOOT/Kernelcache.img4" "$dir/Kernelcache.img4" || return

    {
        echo "ios=$tag"
        echo "device=$device"
        echo "board=$board"
        echo "created=$(date '+%Y-%m-%d %H:%M:%S')"
    } > "$dir/info"

    echo "$tag:$device:$board" > "$BOOT/.5sd7_boot_target"
    success "Saved marked boot set: iOS $tag / $device / $board"
}

ios_bootset_load() {
    local tag="$1"
    local dir="$BOOT/bootsets/$tag"

    check_file "$dir/iBSS.img4"
    check_file "$dir/iBEC.img4"
    check_file "$dir/DeviceTree.img4"
    check_file "$dir/Kernelcache.img4"

    cp -f "$dir/iBSS.img4" "$BOOT/iBSS.img4" || return
    cp -f "$dir/iBEC.img4" "$BOOT/iBEC.img4" || return
    cp -f "$dir/DeviceTree.img4" "$BOOT/DeviceTree.img4" || return
    cp -f "$dir/Kernelcache.img4" "$BOOT/Kernelcache.img4" || return

    if [[ -f "$dir/info" ]]; then
        local device board
        device="$(awk -F= '/^device=/{print $2; exit}' "$dir/info")"
        board="$(awk -F= '/^board=/{print $2; exit}' "$dir/info")"
        echo "$tag:${device:-unknown}:${board:-unknown}" > "$BOOT/.5sd7_boot_target"
    else
        echo "$tag:unknown:unknown" > "$BOOT/.5sd7_boot_target"
    fi
}

ios_bootset_pick() {
    local sets=()
    local dir tag i choice

    if [[ -d "$BOOT/bootsets" ]]; then
        while IFS= read -r dir; do
            tag="$(basename "$dir")"
            [[ -f "$dir/iBSS.img4" && -f "$dir/iBEC.img4" && -f "$dir/DeviceTree.img4" && -f "$dir/Kernelcache.img4" ]] || continue
            sets+=("$tag")
        done < <(find "$BOOT/bootsets" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    if [[ "${#sets[@]}" -eq 0 ]]; then
        if [[ -f "$BOOT/.5sd7_boot_target" ]]; then
            tag="$(cut -d: -f1 "$BOOT/.5sd7_boot_target")"
            [[ -n "$tag" ]] && sets+=("$tag")
        fi
    fi

    if [[ "${#sets[@]}" -eq 0 ]]; then
        error "No marked iOS 10/11/12 boot sets found." >&2
        warn "Run an iOS 10/11/12 restore or build boot files option first." >&2
        return 1
    fi

    if [[ "${#sets[@]}" -eq 1 ]]; then
        printf "%s" "${sets[0]}"
        return 0
    fi

    echo "Marked boot sets:" >&2
    echo >&2
    i=1
    for tag in "${sets[@]}"; do
        if [[ -f "$BOOT/bootsets/$tag/info" ]]; then
            echo "$i) iOS $tag  ($(tr '\n' ' ' < "$BOOT/bootsets/$tag/info"))" >&2
        else
            echo "$i) iOS $tag" >&2
        fi
        i=$((i + 1))
    done
    echo >&2
    read -rp "Boot which iOS? " choice < /dev/tty

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 || "$choice" -gt "${#sets[@]}" ]]; then
        error "Invalid boot set choice." >&2
        return 1
    fi

    printf "%s" "${sets[$((choice - 1))]}"
}

ios_boot_marked() {
    header
    check_boot_tools
    make_executable

    local tag

    tag="$(ios_bootset_pick)" || { pause; return; }

    if [[ -d "$BOOT/bootsets/$tag" ]]; then
        info "Loading marked iOS $tag boot files into bin2boot..."
        ios_bootset_load "$tag" || { pause; return; }
    else
        warn "Using current bin2boot files marked as iOS $tag."
    fi

    check_file "$BOOT/iBSS.img4"
    check_file "$BOOT/iBEC.img4"
    check_file "$BOOT/DeviceTree.img4"
    check_file "$BOOT/Kernelcache.img4"

    warn "This boots the marked iOS $tag boot files currently in bin2boot."
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    pwn_dfu_loop "$BOOT" "yes" || {
        error "pwnDFU/reset failed."
        pause
        return
    }

    cd "$BOOT" || die "Could not cd to bin2boot"
    run_cmd ./5sboot.sh || {
        error "5sboot.sh failed."
        pause
        return
    }

    success "iOS $tag boot script finished."
    pause
}


ios10_prepare_tether_boot_files() {
    local target_ipsw="$1"
    local shsh_path="$2"
    local w="$WORK/ios10_boot"
    local ibss_file="iBSS.${BOARD_SHORT}.RELEASE.im4p"
    local ibec_file="iBEC.${BOARD_SHORT}.RELEASE.im4p"
    local dtree_file="DeviceTree.${BOARD}.im4p"
    local kernel_file="kernelcache.release.${BOARD_SHORT}"
    local ibss_key ibec_key

    rm -rf "$w"
    mkdir -p "$w"

    # ios 10.2.1 regular boot path only decrypts ibss/ibec. devicetree and kernel are wrapped as img4 as-is.
    ibss_key="$(ios10_enc_key "10.2.1" "IBSS")" || return
    ibec_key="$(ios10_enc_key "10.2.1" "IBEC")" || return

    run_cmd "$BOOT/img4tool" -s "$shsh_path" -e -m "$w/im4m" || return

    unzip -j "$target_ipsw" "Firmware/dfu/$ibss_file" -d "$w" >/dev/null || return
    unzip -j "$target_ipsw" "Firmware/dfu/$ibec_file" -d "$w" >/dev/null || return
    unzip -j "$target_ipsw" "Firmware/all_flash/all_flash.${BOARD}.production/$dtree_file" -d "$w" >/dev/null || return
    unzip -j "$target_ipsw" "$kernel_file" -d "$w" >/dev/null || return

    run_cmd "$BOOT/img4" -i "$w/$ibss_file" -o "$w/iBSS.raw" -k "$ibss_key" || return
    run_cmd "$BOOT/img4" -i "$w/$ibec_file" -o "$w/iBEC.raw" -k "$ibec_key" || return

    run_cmd "$BOOT/kairos" "$w/iBSS.raw" "$w/iBSS.patched" || return
    run_cmd "$BOOT/kairos" "$w/iBEC.raw" "$w/iBEC.patched" -n -b "-v debug=0x09" -c "go" 0x830000300 || return

    run_cmd "$BOOT/img4" -i "$w/iBSS.patched" -o "$BOOT/iBSS.img4" -A -T ibss -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/iBEC.patched" -o "$BOOT/iBEC.img4" -A -T ibec -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/$dtree_file" -o "$BOOT/DeviceTree.img4" -T rdtr -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$BOOT/Kernelcache.img4" -T rkrn -M "$w/im4m" || return

    ios_bootset_save "10.2.1" "$DEVICE_TYPE" "$BOARD" || return
    success "iOS 10.2.1 tether boot files were written to bin2boot."
}


ios10_shsh_generator() {
    awk '
        /<key>generator<\/key>/ {
            getline
            gsub(/.*<string>/, "")
            gsub(/<\/string>.*/, "")
            print
            exit
        }
    ' "$IOS10_SHSH_PATH"
}

ios10_wait_mode() {
    local wanted="$1"
    local i
    local mode=""

    for i in {1..25}; do
        mode="$("$BIN/irecovery" -q 2>/dev/null | awk -F": " "/^MODE:/ {print \$2; exit}" | tr -d "\r\n " || true)"
        if [[ "$mode" == "$wanted" ]]; then
            return 0
        fi
        sleep 1
    done

    error "Timed out waiting for $wanted mode. Last mode: ${mode:-unknown}"
    return 1
}

ios10_enter_pwnrecovery_manual() {
    local build="$1"
    local ibss="/tmp/futurerestore/ibss.${BOARD}.${build}.patched.img4"
    local ibec="/tmp/futurerestore/ibec.${BOARD}.${build}.patched.img4"
    local generator=""

    check_file "$ibss"
    check_file "$ibec"

    generator="$(ios10_shsh_generator)"
    if [[ -z "$generator" ]]; then
        error "Could not read generator from SHSH2."
        return 1
    fi

    info "Booting restore chain..."

    run_cmd "$BIN/irecovery" -f "$ibss" || return
    sleep 5
    ios10_wait_mode "DFU" || return

    run_cmd "$BIN/irecovery" -f "$ibec" || return
    sleep 7
    ios10_wait_mode "Recovery" || return

    info "Setting nonce..."
    run_cmd "$BIN/irecovery" -c "setenv com.apple.System.boot-nonce $generator" || return
    run_cmd "$BIN/irecovery" -c "saveenv" || return
    sleep 2

    info "Restarting iBEC..."
    run_cmd "$BIN/irecovery" -f "$ibec" || return
    run_cmd "$BIN/irecovery" -c "go" || return
    sleep 7
    ios10_wait_mode "Recovery" || return

    success "Device is in pwnRecovery."
}


ios10_run_futurerestore_retry() {
    local exit_code=0
    local attempt=1
    local log="$WORK/ios10_futurerestore.log"

    mkdir -p "$WORK"

    while true; do
        info "Starting futurerestore attempt $attempt..."
        echo
        echo -e "${PURPLE}>> sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 $SCRIPT_DIR/futurerestore/futurerestore $*${NC}"

        rm -f "$log"

        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 "$SCRIPT_DIR/futurerestore/futurerestore" "$@" > >(tee "$log") 2> >(tee -a "$log" >&2)
        exit_code=$?
        set -e

        if grep -Fq "Done: restoring failed" "$log" 2>/dev/null || \
           grep -Fq "[exception]:" "$log" 2>/dev/null || \
           grep -Fq "assure failed" "$log" 2>/dev/null; then
            exit_code=1
        fi

        if grep -Fq "Patching iBEC" "$log" 2>/dev/null && grep -Fq "assure failed" "$log" 2>/dev/null; then
            warn "futurerestore tried to patch iBEC itself. The prepatched cache was not used."
            warn "Check that the printed /tmp/futurerestore list includes both 14D27 and 16H88."
        fi

        if [[ "$exit_code" -eq 139 ]]; then
            warn "futurerestore segfaulted. Retrying..."
            attempt=$((attempt + 1))
            sleep 2
            continue
        fi

        return "$exit_code"
    done
}


ios10_run_futurerestore_recovery() {
    local exit_code=0
    local log="$WORK/ios10_futurerestore.log"

    mkdir -p "$WORK"
    rm -f "$log"

    info "Starting futurerestore..."
    echo
    echo -e "${PURPLE}>> sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 $SCRIPT_DIR/futurerestore/futurerestore $*${NC}"

    set +e
    sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 "$SCRIPT_DIR/futurerestore/futurerestore" "$@" > >(tee "$log") 2> >(tee -a "$log" >&2)
    exit_code=$?
    set -e

    if grep -Fq "Done: restoring failed" "$log" 2>/dev/null || \
       grep -Fq "[exception]:" "$log" 2>/dev/null || \
       grep -Fq "assure failed" "$log" 2>/dev/null; then
        exit_code=1
    fi

    return "$exit_code"
}



ios11_patch_asr_ramdisk_file() {
    local src_dmg="$1"
    local out_im4p="$2"
    local w="$WORK/ios11_ramdisk"

    rm -rf "$w"
    mkdir -p "$w"

    run_cmd "$BOOT/img4" -i "$src_dmg" -o "$w/ramdisk.raw" || return
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" extract usr/sbin/asr "$w/asr" || return
    run_cmd "$BOOT/asr64_patcher" "$w/asr" "$w/asr_patched" || return

    "$BOOT/ldid" -e "$w/asr" > "$w/ents.plist" || true
    if [[ -s "$w/ents.plist" ]] && grep -q "<plist" "$w/ents.plist"; then
        run_cmd "$BOOT/ldid" -S"$w/ents.plist" "$w/asr_patched" || return
    else
        run_cmd "$BOOT/ldid" -S "$w/asr_patched" || return
    fi

    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" rm usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" add "$w/asr_patched" usr/sbin/asr || return
    sleep 2
    run_cmd "$BOOT/hfsplus" "$w/ramdisk.raw" chmod 100755 usr/sbin/asr || return
    run_cmd "$BOOT/img4" -i "$w/ramdisk.raw" -o "$out_im4p" -A -T rdsk || return
}

ios11_make_tether_restore_files() {
    local target_ipsw="$1"
    local latest_ipsw="$2"
    local restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/11.3"
    local w="$WORK/ios11_make"
    local target="$w/target"
    local latest="$w/latest"
    local target_kernel="$target/kernelcache.release.iphone6"
    local restore_ramdisk=""

    rm -rf "$w"
    mkdir -p "$target" "$latest" "$restoredir"

    info "Unpacking IPSWs..."
    run_cmd unzip -q "$target_ipsw" -d "$target" || return
    run_cmd unzip -q "$latest_ipsw" -d "$latest" || return

    if [[ ! -f "$target_kernel" ]]; then
        target_kernel="$(find "$target" -maxdepth 1 -type f -name "kernelcache.release.*" | head -n 1)"
    fi
    check_file "$target_kernel"

    info "Adding latest all_flash files..."
    find "$target/Firmware/all_flash/" -type f ! -name "*DeviceTree*" -exec rm -f {} + 2>/dev/null || true
    find "$latest/Firmware/all_flash/" -type f ! -name "*DeviceTree*" -exec cp {} "$target/Firmware/all_flash/" \; || return

    info "Building custom IPSW..."
    rm -f "$restoredir/custom.ipsw"
    (
        cd "$target" || exit 1
        zip -0 -q -r "$restoredir/custom.ipsw" *
    ) || return

    restore_ramdisk="$(ios10_find_dmg "$target" smallest)"
    if [[ -z "$restore_ramdisk" ]]; then
        error "Could not find restore ramdisk DMG."
        return 1
    fi

    info "Making kernel file..."
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$w/kernel.raw" || return
    run_cmd "$BIN/KPlooshFinder" "$w/kernel.raw" "$w/kernel.patched" || return
    run_cmd "$BOOT/kerneldiff" "$w/kernel.raw" "$w/kernel.patched" "$w/kernel.diff" || return
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" -J || \
        run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" || return

    info "Making ramdisk file..."
    ios11_patch_asr_ramdisk_file "$restore_ramdisk" "$restoredir/ramdisk.im4p" || return

    rm -f "$restoredir/updateramdisk.im4p"
    echo "v1_ios11_target_base" > "$restoredir/.5sd7_ios11_custom_method"

    success "iOS 11.3 restore files ready in $restoredir"
}

ios11_unzip_first() {
    local ipsw="$1"
    local outdir="$2"
    shift 2
    local p

    for p in "$@"; do
        if unzip -l "$ipsw" "$p" >/dev/null 2>&1; then
            unzip -j "$ipsw" "$p" -d "$outdir" >/dev/null && return 0
        fi
    done

    return 1
}

ios11_prepare_tether_boot_files() {
    local target_ipsw="$1"
    local shsh_path="$2"
    local w="$WORK/ios11_boot"
    local restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/11.3"
    local ibss_file="iBSS.iphone6.RELEASE.im4p"
    local ibec_file="iBEC.iphone6.RELEASE.im4p"
    local dtree_file="DeviceTree.${BOARD}.im4p"
    local kernel_file="kernelcache.release.iphone6"
    local ibss_key ibec_key

    rm -rf "$w"
    mkdir -p "$w"

    ibss_key="$(ios10_enc_key "11.3" "IBSS")" || return
    ibec_key="$(ios10_enc_key "11.3" "IBEC")" || return

    run_cmd "$BOOT/img4tool" -s "$shsh_path" -e -m "$w/im4m" || return

    unzip -j "$target_ipsw" "Firmware/dfu/$ibss_file" -d "$w" >/dev/null || return
    unzip -j "$target_ipsw" "Firmware/dfu/$ibec_file" -d "$w" >/dev/null || return
    ios11_unzip_first "$target_ipsw" "$w" \
        "Firmware/all_flash/$dtree_file" \
        "Firmware/all_flash/all_flash.${BOARD}.production/$dtree_file" || return

    unzip -j "$target_ipsw" "$kernel_file" -d "$w" >/dev/null || {
        kernel_file="$(unzip -Z1 "$target_ipsw" 2>/dev/null | grep -E '^kernelcache\.release\.' | head -n 1)"
        [[ -n "$kernel_file" ]] || return 1
        unzip -j "$target_ipsw" "$kernel_file" -d "$w" >/dev/null || return
        kernel_file="$(basename "$kernel_file")"
    }

    run_cmd "$BOOT/img4" -i "$w/$ibss_file" -o "$w/iBSS.raw" -k "$ibss_key" || return
    run_cmd "$BOOT/img4" -i "$w/$ibec_file" -o "$w/iBEC.raw" -k "$ibec_key" || return

    run_cmd "$BOOT/kairos" "$w/iBSS.raw" "$w/iBSS.patched" || return
    run_cmd "$BOOT/kairos" "$w/iBEC.raw" "$w/iBEC.patched" -b "-v" || return

    rm -f "$BOOT/iBSS.img4" "$BOOT/iBEC.img4" "$BOOT/DeviceTree.img4" "$BOOT/Kernelcache.img4"

    run_cmd "$BOOT/img4" -i "$w/iBSS.patched" -o "$BOOT/iBSS.img4" -A -T ibss -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/iBEC.patched" -o "$BOOT/iBEC.img4" -A -T ibec -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/$dtree_file" -o "$BOOT/DeviceTree.img4" -T rdtr -M "$w/im4m" || return

    if [[ -f "$restoredir/kernel.im4p" ]]; then
        info "Using patched iOS 11 restore kernel for tether boot."
        run_cmd "$BOOT/img4" -i "$restoredir/kernel.im4p" -o "$BOOT/Kernelcache.img4" -T rkrn -M "$w/im4m" || return
    else
        warn "Patched restore kernel missing. Building patched iOS 11 boot kernel now."
        run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$w/kernel.raw" || return
        run_cmd "$BIN/KPlooshFinder" "$w/kernel.raw" "$w/kernel.patched" || return
        run_cmd "$BOOT/kerneldiff" "$w/kernel.raw" "$w/kernel.patched" "$w/kernel.diff" || return
        run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$BOOT/Kernelcache.img4" -T rkrn -P "$w/kernel.diff" -M "$w/im4m" -J || \
            run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$BOOT/Kernelcache.img4" -T rkrn -P "$w/kernel.diff" -M "$w/im4m" || return
    fi

    ios_bootset_save "11.3" "$DEVICE_TYPE" "$BOARD" || return
    success "iOS 11.3 tether boot files were written to bin2boot."
}

ios11_113_restore() {
    header
    warn "iPhone 5s iOS 11.3 tethered restore path."
    warn "This uses latest signed 12.5.8 blobs/SEP with an 11.3 custom restore payload."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="11.3"
    TARGET_IOS_DISPLAY="11.3"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 11.3 IPSW: ")"
    echo
    IOS10_LATEST_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.5.8/latest IPSW: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_LATEST_IPSW"

    ios10_set_build_from_ipsw_or_default "$IOS10_TARGET_IPSW" "15E216"
    IOS10_LATEST_VERSION="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductVersion)"
    [[ -n "$IOS10_LATEST_VERSION" ]] || IOS10_LATEST_VERSION="12.5.8"
    IOS10_LATEST_BUILD="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductBuildVersion)"
    [[ -n "$IOS10_LATEST_BUILD" ]] || IOS10_LATEST_BUILD="16H88"

    ios10_detect_or_prompt_ecid || { pause; return; }

    pwn_dfu_loop "$BIN" "yes" || { pause; return; }
    cd "$SCRIPT_DIR" || return

    ios10_fetch_shsh_for_latest || { pause; return; }

    restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/11.3"
    if [[ ! -f "$restoredir/custom.ipsw" || ! -f "$restoredir/ramdisk.im4p" || ! -f "$restoredir/kernel.im4p" || ! -f "$restoredir/.5sd7_ios11_custom_method" ]] || ! grep -q "v1_ios11_target_base" "$restoredir/.5sd7_ios11_custom_method" 2>/dev/null; then
        warn "Rebuilding iOS 11.3 restore files."
        rm -rf "$restoredir"
        ios11_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
    else
        warn "Existing iOS 11.3 restore files found."
        read -rp "Rebuild them? (y/n): " rebuild
        if [[ "$rebuild" == "y" || "$rebuild" == "Y" ]]; then
            rm -rf "$restoredir"
            ios11_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
        fi
    fi

    IOS10_RESTORE_BUILD="$(ios10_parse_plist_value "$restoredir/custom.ipsw" ProductBuildVersion)"
    [[ -n "$IOS10_RESTORE_BUILD" ]] || IOS10_RESTORE_BUILD="$IOS10_BUILD"
    info "Using iBoot tag: $IOS10_RESTORE_BUILD"

    ios10_prepatch_restore_iboots "$IOS10_TARGET_IPSW" "11.3" "$IOS10_RESTORE_BUILD" || { pause; return; }

    ios10_run_futurerestore_retry \
        -t "$IOS10_SHSH_PATH" --use-pwndfu --skip-blob \
        --rdsk "$restoredir/ramdisk.im4p" \
        --custom-latest "$IOS10_LATEST_VERSION" \
        --rkrn "$restoredir/kernel.im4p" --latest-sep \
        --latest-baseband --no-rsep "$restoredir/custom.ipsw"

    fr_status=$?
    if [[ "$fr_status" -ne 0 ]]; then
        error "futurerestore failed with exit code $fr_status"
        warn "Not building boot files because the restore did not finish."
        pause
        return
    fi

    success "iOS 11.3 tethered restore finished."
    ios11_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || {
        warn "Restore finished, but boot file build failed."
        pause
        return
    }

    warn "You can now use the iOS 11 tether boot option, or run it now."
    read -rp "Boot now? (y/n): " bootnow
    if [[ "$bootnow" == "y" || "$bootnow" == "Y" ]]; then
        ios11_boot
    else
        pause
    fi
}

ios11_boot() {
    ios_boot_marked
}

ios10_build_boot_only() {
    header
    warn "Build iOS 10.2.1 tether boot files only."
    warn "This does not restore. It only rebuilds and marks the boot files."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="10.2.1"
    TARGET_IOS_DISPLAY="10.2.1"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 10.2.1 IPSW: ")"
    echo
    IOS10_SHSH_PATH="$(read_drag_path "Drag the latest signed iOS 12.5.8 SHSH2 used for tether boot: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_SHSH_PATH"

    ios10_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || { pause; return; }

    success "iOS 10.2.1 boot files rebuilt and marked."
    pause
}

ios11_build_boot_only() {
    header
    warn "Build iOS 11.3 tether boot files only."
    warn "This does not restore. It only rebuilds and marks the boot files."
    warn "If restorefiles are still present, it will use the patched restore kernel."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="11.3"
    TARGET_IOS_DISPLAY="11.3"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 11.3 IPSW: ")"
    echo
    IOS10_SHSH_PATH="$(read_drag_path "Drag the latest signed iOS 12.5.8 SHSH2 used for tether boot: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_SHSH_PATH"

    ios11_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || { pause; return; }

    success "iOS 11.3 boot files rebuilt and marked."
    pause
}


ios12_make_tether_restore_files() {
    local target_ipsw="$1"
    local latest_ipsw="$2"
    local restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/12.0"
    local w="$WORK/ios12_make"
    local target="$w/target"
    local latest="$w/latest"
    local target_kernel="$target/kernelcache.release.iphone6"
    local restore_ramdisk=""

    rm -rf "$w"
    mkdir -p "$target" "$latest" "$restoredir"

    info "Unpacking IPSWs..."
    run_cmd unzip -q "$target_ipsw" -d "$target" || return
    run_cmd unzip -q "$latest_ipsw" -d "$latest" || return

    if [[ ! -f "$target_kernel" ]]; then
        target_kernel="$(find "$target" -maxdepth 1 -type f -name "kernelcache.release.*" | head -n 1)"
    fi
    check_file "$target_kernel"

    info "Adding latest all_flash files..."
    find "$target/Firmware/all_flash/" -type f ! -name "*DeviceTree*" -exec rm -f {} + 2>/dev/null || true
    find "$latest/Firmware/all_flash/" -type f ! -name "*DeviceTree*" -exec cp {} "$target/Firmware/all_flash/" \; || return

    info "Building custom IPSW..."
    rm -f "$restoredir/custom.ipsw"
    (
        cd "$target" || exit 1
        zip -0 -q -r "$restoredir/custom.ipsw" *
    ) || return

    restore_ramdisk="$(ios10_find_dmg "$target" smallest)"
    if [[ -z "$restore_ramdisk" ]]; then
        error "Could not find restore ramdisk DMG."
        return 1
    fi

    info "Making kernel file..."
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$w/kernel.raw" || return
    run_cmd "$BIN/KPlooshFinder" "$w/kernel.raw" "$w/kernel.patched" || return
    run_cmd "$BOOT/kerneldiff" "$w/kernel.raw" "$w/kernel.patched" "$w/kernel.diff" || return
    run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" -J || \
        run_cmd "$BOOT/img4" -i "$target_kernel" -o "$restoredir/kernel.im4p" -T rkrn -P "$w/kernel.diff" || return

    info "Making ramdisk file..."
    ios11_patch_asr_ramdisk_file "$restore_ramdisk" "$restoredir/ramdisk.im4p" || return

    rm -f "$restoredir/updateramdisk.im4p"
    echo "v1_ios12_target_base" > "$restoredir/.5sd7_ios12_custom_method"

    success "iOS 12.0 restore files ready in $restoredir"
}

ios12_prepare_tether_boot_files() {
    local target_ipsw="$1"
    local shsh_path="$2"
    local w="$WORK/ios12_boot"
    local restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/12.0"
    local ibss_file="iBSS.iphone6.RELEASE.im4p"
    local ibec_file="iBEC.iphone6.RELEASE.im4p"
    local dtree_file="DeviceTree.${BOARD}.im4p"
    local kernel_file="kernelcache.release.iphone6"
    local ibss_key ibec_key

    rm -rf "$w"
    mkdir -p "$w"

    ibss_key="$(ios10_enc_key "12.0" "IBSS")" || return
    ibec_key="$(ios10_enc_key "12.0" "IBEC")" || return

    run_cmd "$BOOT/img4tool" -s "$shsh_path" -e -m "$w/im4m" || return

    unzip -j "$target_ipsw" "Firmware/dfu/$ibss_file" -d "$w" >/dev/null || return
    unzip -j "$target_ipsw" "Firmware/dfu/$ibec_file" -d "$w" >/dev/null || return
    ios11_unzip_first "$target_ipsw" "$w" \
        "Firmware/all_flash/$dtree_file" \
        "Firmware/all_flash/all_flash.${BOARD}.production/$dtree_file" || return

    unzip -j "$target_ipsw" "$kernel_file" -d "$w" >/dev/null || {
        kernel_file="$(unzip -Z1 "$target_ipsw" 2>/dev/null | grep -E '^kernelcache\.release\.' | head -n 1)"
        [[ -n "$kernel_file" ]] || return 1
        unzip -j "$target_ipsw" "$kernel_file" -d "$w" >/dev/null || return
        kernel_file="$(basename "$kernel_file")"
    }

    run_cmd "$BOOT/img4" -i "$w/$ibss_file" -o "$w/iBSS.raw" -k "$ibss_key" || return
    run_cmd "$BOOT/img4" -i "$w/$ibec_file" -o "$w/iBEC.raw" -k "$ibec_key" || return

    run_cmd "$BOOT/kairos" "$w/iBSS.raw" "$w/iBSS.patched" || return
    run_cmd "$BOOT/kairos" "$w/iBEC.raw" "$w/iBEC.patched" -b "-v" || return

    rm -f "$BOOT/iBSS.img4" "$BOOT/iBEC.img4" "$BOOT/DeviceTree.img4" "$BOOT/Kernelcache.img4"

    run_cmd "$BOOT/img4" -i "$w/iBSS.patched" -o "$BOOT/iBSS.img4" -A -T ibss -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/iBEC.patched" -o "$BOOT/iBEC.img4" -A -T ibec -M "$w/im4m" || return
    run_cmd "$BOOT/img4" -i "$w/$dtree_file" -o "$BOOT/DeviceTree.img4" -T rdtr -M "$w/im4m" || return

    if [[ -f "$restoredir/kernel.im4p" ]]; then
        info "Using patched iOS 12 restore kernel for tether boot."
        run_cmd "$BOOT/img4" -i "$restoredir/kernel.im4p" -o "$BOOT/Kernelcache.img4" -T rkrn -M "$w/im4m" || return
    else
        warn "Patched restore kernel missing. Building patched iOS 12 boot kernel now."
        run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$w/kernel.raw" || return
        run_cmd "$BIN/KPlooshFinder" "$w/kernel.raw" "$w/kernel.patched" || return
        run_cmd "$BOOT/kerneldiff" "$w/kernel.raw" "$w/kernel.patched" "$w/kernel.diff" || return
        run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$BOOT/Kernelcache.img4" -T rkrn -P "$w/kernel.diff" -M "$w/im4m" -J || \
            run_cmd "$BOOT/img4" -i "$w/$kernel_file" -o "$BOOT/Kernelcache.img4" -T rkrn -P "$w/kernel.diff" -M "$w/im4m" || return
    fi

    ios_bootset_save "12.0" "$DEVICE_TYPE" "$BOARD" || return
    success "iOS 12.0 tether boot files were written to bin2boot."
}

ios12_120_restore() {
    header
    warn "iPhone 5s iOS 12.0 tethered restore path."
    warn "This uses latest signed 12.5.8 blobs/SEP with a 12.0 custom restore payload."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="12.0"
    TARGET_IOS_DISPLAY="12.0"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.0 IPSW: ")"
    echo
    IOS10_LATEST_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.5.8/latest IPSW: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_LATEST_IPSW"

    ios10_set_build_from_ipsw_or_default "$IOS10_TARGET_IPSW" "16A366"
    IOS10_LATEST_VERSION="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductVersion)"
    [[ -n "$IOS10_LATEST_VERSION" ]] || IOS10_LATEST_VERSION="12.5.8"
    IOS10_LATEST_BUILD="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductBuildVersion)"
    [[ -n "$IOS10_LATEST_BUILD" ]] || IOS10_LATEST_BUILD="16H88"

    ios10_detect_or_prompt_ecid || { pause; return; }

    pwn_dfu_loop "$BIN" "yes" || { pause; return; }
    cd "$SCRIPT_DIR" || return

    ios10_fetch_shsh_for_latest || { pause; return; }

    restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/12.0"
    if [[ ! -f "$restoredir/custom.ipsw" || ! -f "$restoredir/ramdisk.im4p" || ! -f "$restoredir/kernel.im4p" || ! -f "$restoredir/.5sd7_ios12_custom_method" ]] || ! grep -q "v1_ios12_target_base" "$restoredir/.5sd7_ios12_custom_method" 2>/dev/null; then
        warn "Rebuilding iOS 12.0 restore files."
        rm -rf "$restoredir"
        ios12_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
    else
        warn "Existing iOS 12.0 restore files found."
        read -rp "Rebuild them? (y/n): " rebuild
        if [[ "$rebuild" == "y" || "$rebuild" == "Y" ]]; then
            rm -rf "$restoredir"
            ios12_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
        fi
    fi

    IOS10_RESTORE_BUILD="$(ios10_parse_plist_value "$restoredir/custom.ipsw" ProductBuildVersion)"
    [[ -n "$IOS10_RESTORE_BUILD" ]] || IOS10_RESTORE_BUILD="$IOS10_BUILD"
    info "Using iBoot tag: $IOS10_RESTORE_BUILD"

    ios10_prepatch_restore_iboots "$IOS10_TARGET_IPSW" "12.0" "$IOS10_RESTORE_BUILD" || { pause; return; }

    ios10_run_futurerestore_retry \
        -t "$IOS10_SHSH_PATH" --use-pwndfu --skip-blob \
        --rdsk "$restoredir/ramdisk.im4p" \
        --custom-latest "$IOS10_LATEST_VERSION" \
        --rkrn "$restoredir/kernel.im4p" --latest-sep \
        --latest-baseband --no-rsep "$restoredir/custom.ipsw"

    fr_status=$?
    if [[ "$fr_status" -ne 0 ]]; then
        error "futurerestore failed with exit code $fr_status"
        warn "Not building boot files because the restore did not finish."
        pause
        return
    fi

    success "iOS 12.0 tethered restore finished."
    ios12_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || {
        warn "Restore finished, but boot file build failed."
        pause
        return
    }

    warn "You can now use the marked tether boot option, or run it now."
    read -rp "Boot now? (y/n): " bootnow
    if [[ "$bootnow" == "y" || "$bootnow" == "Y" ]]; then
        ios_boot_marked
    else
        pause
    fi
}

ios12_build_boot_only() {
    header
    warn "Build iOS 12.0 tether boot files only."
    warn "This does not restore. It only rebuilds and marks the boot files."
    warn "If restorefiles are still present, it will use the patched restore kernel."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="12.0"
    TARGET_IOS_DISPLAY="12.0"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.0 IPSW: ")"
    echo
    IOS10_SHSH_PATH="$(read_drag_path "Drag the latest signed iOS 12.5.8 SHSH2 used for tether boot: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_SHSH_PATH"

    ios12_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || { pause; return; }

    success "iOS 12.0 boot files rebuilt and marked."
    pause
}


ios10_1021_restore() {
    header
    warn "iPhone 5s iOS 10.2.1 tethered restore path."
    warn "This makes restore files, then runs futurerestore."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="10.2.1"
    TARGET_IOS_DISPLAY="10.2.1"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 10.2.1 IPSW: ")"
    echo
    IOS10_LATEST_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.5.8/latest IPSW: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_LATEST_IPSW"

    ios10_set_build_from_ipsw_or_default "$IOS10_TARGET_IPSW" "14D27"
    IOS10_LATEST_VERSION="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductVersion)"
    [[ -n "$IOS10_LATEST_VERSION" ]] || IOS10_LATEST_VERSION="12.5.8"
    IOS10_LATEST_BUILD="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductBuildVersion)"
    [[ -n "$IOS10_LATEST_BUILD" ]] || IOS10_LATEST_BUILD="16H88"
    IOS10_LATEST_BUILD="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductBuildVersion)"
    [[ -n "$IOS10_LATEST_BUILD" ]] || IOS10_LATEST_BUILD="16H88"

    ios10_detect_or_prompt_ecid || { pause; return; }

    pwn_dfu_loop "$BIN" "yes" || { pause; return; }
    cd "$SCRIPT_DIR" || return

    ios10_download_1033_ota_sep || { pause; return; }
    ios10_fetch_shsh_for_latest || { pause; return; }

    restoredir="$SCRIPT_DIR/restorefiles/$IOS10_IDENTIFIER/10.2.1"
    if [[ ! -f "$restoredir/custom.ipsw" || ! -f "$restoredir/ramdisk.im4p" || ! -f "$restoredir/kernel.im4p" || ! -f "$restoredir/.5sd7_ios10_custom_method" ]] || ! grep -q "v5_target_base_restore" "$restoredir/.5sd7_ios10_custom_method" 2>/dev/null; then
        warn "Rebuilding iOS 10 restore files."
        rm -rf "$restoredir"
        ios10_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
    else
        warn "Existing iOS 10.2.1 restore files found."
        read -rp "Rebuild them? (y/n): " rebuild
        if [[ "$rebuild" == "y" || "$rebuild" == "Y" ]]; then
            rm -rf "$restoredir"
            ios10_make_tether_restore_files "$IOS10_TARGET_IPSW" "$IOS10_LATEST_IPSW" || { pause; return; }
        fi
    fi

    IOS10_RESTORE_BUILD="$(ios10_parse_plist_value "$restoredir/custom.ipsw" ProductBuildVersion)"
    [[ -n "$IOS10_RESTORE_BUILD" ]] || IOS10_RESTORE_BUILD="$IOS10_BUILD"
    info "Using iBoot tag: $IOS10_RESTORE_BUILD"

    ios10_prepatch_restore_iboots "$IOS10_TARGET_IPSW" "10.2.1" "$IOS10_RESTORE_BUILD" || { pause; return; }

    ios10_run_futurerestore_retry \
        -t "$IOS10_SHSH_PATH" --skip-blob --use-pwndfu \
        --rdsk "$restoredir/ramdisk.im4p" \
        --rkrn "$restoredir/kernel.im4p" \
        --custom-latest "$IOS10_LATEST_VERSION" \
        --latest-baseband --sep "$IOS10_SEP_PATH" --sep-manifest "$IOS10_SEP_MANIFEST" \
        --no-rsep "$restoredir/custom.ipsw"

    fr_status=$?
    if [[ "$fr_status" -ne 0 ]]; then
        error "futurerestore failed with exit code $fr_status"
        warn "Not building boot files because the restore did not finish."
        pause
        return
    fi

    success "iOS 10.2.1 tethered restore finished."
    ios10_prepare_tether_boot_files "$IOS10_TARGET_IPSW" "$IOS10_SHSH_PATH" || {
        warn "Restore finished, but boot file build failed."
        pause
        return
    }

    warn "You can now use the new iOS 10 tether boot option, or run it now."
    read -rp "Boot now? (y/n): " bootnow
    if [[ "$bootnow" == "y" || "$bootnow" == "Y" ]]; then
        ios10_boot
    else
        pause
    fi
}


ios10_1033_restore() {
    header
    warn "iPhone 5s iOS 10.3.3 OTA untethered restore path."
    warn "Signing is OTA-only, but futurerestore still needs a normal 10.3.3 Restore IPSW as the restore payload."
    warn "This fetches 10.3.3 OTA blobs using tsschecker and restores with futurerestore."
    echo
    read -rp "Continue? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    ios10_select_5s_model || return
    ensure_ios10_tools || return

    TARGET_IOS="10.3.3"
    TARGET_IOS_DISPLAY="10.3.3"

    echo
    IOS10_TARGET_IPSW="$(read_drag_path "Drag the signed $DEVICE_TYPE iPhone 5s iOS 10.3.3 OTA zip/package: ")"
    echo
    IOS10_1033_IPSW="$(read_drag_path "Drag the normal $DEVICE_TYPE iPhone 5s iOS 10.3.3 Restore IPSW payload: ")"
    echo
    IOS10_LATEST_IPSW="$(read_drag_path "Drag the $DEVICE_TYPE iPhone 5s iOS 12.5.8/latest IPSW for baseband version detection: ")"

    check_file "$IOS10_TARGET_IPSW"
    check_file "$IOS10_1033_IPSW"
    check_file "$IOS10_LATEST_IPSW"

    # the signing path is ota, but futurerestore's final ipsw argument still needs a normal restore ipsw.
    # the ota zip is used for ota shsh/manifest/ibss/ibec handling only.
    ios10_set_build_from_ipsw_or_default "$IOS10_1033_IPSW" "14G60"
    IOS10_LATEST_VERSION="$(ios10_parse_plist_value "$IOS10_LATEST_IPSW" ProductVersion)"
    [[ -n "$IOS10_LATEST_VERSION" ]] || IOS10_LATEST_VERSION="12.5.8"

    ios10_detect_or_prompt_ecid || { pause; return; }

    pwn_dfu_loop "$BIN" "yes" || { pause; return; }
    cd "$SCRIPT_DIR" || return

    ios10_download_1033_ota_sep || { pause; return; }
    ios10_fetch_1033_ota_shsh || { pause; return; }
    ios10_prepatch_restore_iboots "$IOS10_TARGET_IPSW" "10.3.3" "$IOS10_BUILD" || { pause; return; }

    info "Using OTA SHSH/manifest with normal 10.3.3 Restore IPSW payload."
    info "OTA package: $IOS10_TARGET_IPSW"
    info "Restore IPSW payload: $IOS10_1033_IPSW"

    ios10_run_futurerestore_retry \
        -t "$IOS10_SHSH_PATH" --use-pwndfu \
        --sep "$IOS10_SEP_PATH" --sep-manifest "$IOS10_SEP_MANIFEST" \
        --custom-latest "$IOS10_LATEST_VERSION" \
        --latest-baseband --no-rsep "$IOS10_1033_IPSW"

    fr_status=$?
    if [[ "$fr_status" -ne 0 ]]; then
        error "futurerestore failed with exit code $fr_status"
        pause
        return
    fi

    success "iOS 10.3.3 untethered restore finished."
    pause
}

ios10_boot() {
    ios_boot_marked
}

update_latest_signed_ios() {
    header
    check_restore_tools
    make_executable

    warn "This updates to the latest signed iOS and is untethered."
    echo
    LATEST_SIGNED_IPSW="$(read_drag_path "Drag the latest signed iOS IPSW: ")"

    check_file "$LATEST_SIGNED_IPSW"

    echo
    read -rp "Run idevicerestore now? Type YES: " confirm
    [[ "$confirm" == "YES" ]] || { warn "Cancelled."; pause; return; }

    cd "$BIN" || die "Could not cd to bin"

    run_cmd ./idevicerestore "$LATEST_SIGNED_IPSW" || {
        error "Update failed."
        pause
        return
    }

    success "Update command finished."
    pause
}


main_menu() {
    while true; do
        header

        echo "WARNING:"
        echo "This tool is for iPhone 5s legacy restores and downgrades only."
        echo
        echo "Supported:"
        echo " - GSM  / n51ap / iPhone6,1"
        echo " - CDMA / n53ap / iPhone6,2"
        echo " - iOS 7.0.6, 7.1.0, 7.1.1, 7.1.2, 8.0, 8.4, 9.3.2, 9.3.4"
        echo " - iOS 10.2.1 tethered restore"
        echo " - iOS 10.3.3 OTA untethered restore"
        echo " - iOS 11.3 tethered restore"
        echo " - iOS 12.0 tethered restore"
        echo
        echo "Unsupported: below 7.0.6, iPhone 5c, other devices, and random in-between builds this script does not handle."
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
        echo "9) iOS 10.2.1 Tethered Restore"
        echo "10) iOS 10.3.3 OTA Untethered Restore"
        echo "11) Tether Boot Marked iOS 10/11/12 Files"
        echo "12) iOS 11.3 Tethered Restore"
        echo "13) Build iOS 10.2.1 Boot Files Only"
        echo "14) Build iOS 11.3 Boot Files Only"
        echo "15) iOS 12.0 Tethered Restore"
        echo "16) Build iOS 12.0 Boot Files Only"
        echo "17) Update To Latest Signed iOS"
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
            9) ios10_1021_restore; restore_active_restore_tools_silent ;;
            10) ios10_1033_restore; restore_active_restore_tools_silent ;;
            11) ios_boot_marked; restore_active_restore_tools_silent ;;
            12) ios11_113_restore; restore_active_restore_tools_silent ;;
            13) ios10_build_boot_only; restore_active_restore_tools_silent ;;
            14) ios11_build_boot_only; restore_active_restore_tools_silent ;;
            15) ios12_120_restore; restore_active_restore_tools_silent ;;
            16) ios12_build_boot_only; restore_active_restore_tools_silent ;;
            17) update_latest_signed_ios; restore_active_restore_tools_silent ;;
            0) restore_active_restore_tools_silent; exit 0 ;;
            *) error "Invalid choice"; sleep 1 ;;
        esac
    done
}

ensure_legacy_ios_kit_macos_libs
main_menu
