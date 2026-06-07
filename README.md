# 5sd7

**5sd7 (5s Downgrade 7)** is a utility for creating, restoring, and tether-booting iOS 7 on the iPhone 5s.

The goal of this project is to automate the process of tether downgrading the iPhone 5s.

Third-party software licenses can be found in the THIRD_PARTY_LICENSES directory.
IMPORTANT
img4lib and kerneldiff MUST BE COMPILED and placed in bin2boot, and bin for this to work!!


---

## Features

This tool only supports iOS 7.0.6 through 7.1.2.
Versions below iOS 7.0.6 and above iOS 7.1.2 are not supported.
* Supports iPhone 5s GSM (iPhone6,1 / n51ap)
* Supports iPhone 5s CDMA (iPhone6,2 / n53ap)
* Supports:

  * iOS 7.0.6
  * iOS 7.1
  * iOS 7.1.1
  * iOS 7.1.2
* Automatic IPSW extraction
* Automatic root filesystem replacement
* Automatic iBSS patching
* Automatic iBEC patching
* Automatic DeviceTree patching
* Automatic kernelcache patching
* Automatic restore ramdisk replacement
* Automatic IPSW rebuilding
* Automated restore workflow
* Automated tethered boot workflow

---

## Compatibility

### Confirmed Working

* GSM (iPhone6,1 / n51ap) → iOS 7.1.2

### Very Likely Working

The following configurations use the exact same workflow and patching process but have not yet been personally tested:

* GSM (iPhone6,1 / n51ap) → iOS 7.0.6
* GSM (iPhone6,1 / n51ap) → iOS 7.1
* GSM (iPhone6,1 / n51ap) → iOS 7.1.1

### Untested

The following configurations have not been tested:

* CDMA (iPhone6,2 / n53ap) → iOS 7.0.6
* CDMA (iPhone6,2 / n53ap) → iOS 7.1
* CDMA (iPhone6,2 / n53ap) → iOS 7.1.1
* CDMA (iPhone6,2 / n53ap) → iOS 7.1.2

---

## Supported Platforms

### Confirmed Working

* Intel Macs (x86_64)
* macOS Monterey

### Untested

* Apple Silicon (M1, M2, M3, M4)
* macOS versions other than Monterey

Apple Silicon compatibility is currently unknown.

---

## Requirements

You must provide:

* Target iOS 7 IPSW
* iOS 12.5.8 IPSW 
* SHSH2 blob for iOS 12.5.8 (The SHSH2 blob used must correspond to the device being restored and must be for iOS 12.5.8.)

No Apple firmware files are included in this repository.

---

## Dependencies

The following tools are included, all dependencies for these tools must be installed if any are needed:

* gaster
* idevicerestore (must have the necessary dependencies in /usr/local/lib for it to work)
* ipatcher
* Kernel64Patcher
* img4tool
* lzfse
* libirecovery
* libusbmuxd

### Additional Required Tools

The following tools are NOT included:

* img4 (img4lib)
* kerneldiff

These tools must be obtained and compiled separately, then the binaries placed in bin and bin2boot.

They are not bundled with this project due to licensing uncertainty.

---

## What This Project Does Not Include

This repository does not contain:

* Apple IPSWs
* Apple firmware files
* Extracted IPSW contents
* Decrypted firmware components
* Patched firmware components
* Prebuilt downgrade IPSWs

Users must supply their own IPSWs.

---

## Disclaimer

This software is provided as-is with no warranty of any kind.

Use this software entirely at your own risk.

The author is not responsible for:

* Bricked devices
* Boot loops
* Failed restores
* Data loss
* Activation issues
* Hardware damage
* Software damage
* Unsupported configurations
* Any other consequences resulting from the use of this software

By using this project, you accept full responsibility for any modifications made to your device.

---

## Credits

This project relies on the work of many developers in the iOS research and jailbreak community.

Credit goes to the developers of:

* gaster
* idevicerestore
* ipatcher
* Kernel64Patcher
* img4tool
* img4lib
* kerneldiff
* libirecovery
* libusbmuxd
* lzfse
* user pwnerblu

as well as the developers whose research made tethered downgrades possible.

## License

The 5sd7 project itself is licensed under the MIT License.

Third-party software included with this project is licensed under its respective license. See the THIRD_PARTY_LICENSES directory for additional information.


