# 5sd7 Tethered Downgrade Tool for iPhone 5s (iOS 7.0.6 – 12.5.8)

> [!IMPORTANT]
> Some third-party tools are **downloaded automatically** by 5sd7 when required.
>
> These tools are **not distributed with this project** and remain the property of their respective authors.
>
> Depending on the selected downgrade target, 5sd7 may automatically download tools such as:
>
> * img4 (img4lib)
> * kerneldiff
> * kairos
> * Kernel64Patcher2
> * dsc64patcher
> * SSHRD
> * hfsplus
> * dmg
> * ldid
> * asr64_patcher
> * ipx_restored_patcher (when required)
> * idevicerestore (version depends on selected iOS)
>
> These tools are downloaded directly from their respective upstream projects. They are **not bundled** with 5sd7.

**5sd7 (5s Downgrade 7)** is a utility for creating, restoring, and tether-booting iOS 7, iOS 8, and iOS 9 on the iPhone 5s.

The goal of this project is to automate the tethered downgrade process while preserving the workflows used by the iOS research community.

Third-party licenses included with the project can be found in the `THIRD_PARTY_LICENSES` directory.

---

# Features

Supported firmware:

* iOS 7.0.6
* iOS 7.1
* iOS 7.1.1
* iOS 7.1.2
* iOS 8.0
* iOS 8.4
* iOS 9.3.2
* iOS 9.3.4
* iOS 10.2.1
* iOS 10.3.3

Features include:

* Automatic IPSW extraction
* Automatic root filesystem rebuilding
* Automatic iBSS patching
* Automatic iBEC patching
* Automatic DeviceTree patching
* Automatic kernelcache patching
* Automatic ASR patching (iOS 9)
* Automatic restore ramdisk rebuilding
* Automatic IPSW rebuilding
* Automated restore workflow
* Automated tethered boot workflow
* Automatic dyld shared cache patching (iOS 8)
* Automatic download of required third-party utilities
* Separate restore tool profiles for legacy (iOS 7/8) and iOS 9 restores

---

# Compatibility

## Confirmed Working

* GSM (iPhone6,1 / n51ap) → iOS 7.1.2
* GSM (iPhone6,1 / n51ap) → iOS 8.0
* GSM (iPhone6,1 / n51ap) → iOS 9.3.4
* GSM (iPhone6,1 / n51ap) → iOS 9.3.2
* GSM (iPhone6,1 / n51ap) → iOS 10.2.1
* GSM (iPhone6,1 / n51ap) → iOS 10.3.3
* CDMA (iPhone6,2 / n53ap) → iOS 7.1.2

## Very Likely Working

Because the patching workflow is identical:

### GSM

* iOS 7.0.6
* iOS 7.1
* iOS 7.1.1
* iOS 8.4

### CDMA

* iOS 7.0.6
* iOS 7.1
* iOS 7.1.1
* iOS 8.0
* iOS 8.4
* iOS 9.3.2
* iOS 9.3.4
* iOS 10.2.1
* iOS 10.3.3

---

# Requirements

You must provide:

* Target iOS IPSW
* iOS 12.5.8 IPSW
* Matching iOS 12.5.8 SHSH2 blob

No Apple firmware is included with this repository.

---

# Dependencies

## Included

* gaster
* ipatcher
* Kernel64Patcher
* img4tool
* libirecovery
* libusbmuxd
* lzfse

## Downloaded Automatically

Depending on the selected firmware version:

* img4 (img4lib)
* kerneldiff
* kairos
* Kernel64Patcher2
* idevicerestore
* hfsplus
* dmg
* ldid
* dsc64patcher
* SSHRD
* asr64_patcher
* ipx_restored_patcher (when required)

---

# Credits

This project would not be possible without the work of the iOS research and jailbreak community.

Special thanks to the developers and maintainers of:

* gaster
* idevicerestore
* ipatcher
* kairos
* Kernel64Patcher
* Kernel64Patcher2
* img4tool
* img4 (img4lib)
* kerneldiff
* hfsplus
* dmg
* ldid
* dsc64patcher
* SSHRD
* asr64_patcher
* ipx_restored_patcher
* libirecovery
* libusbmuxd
* lzfse

Additional thanks to:

* **LukeZGD** (Legacy-iOS-Kit and Semaphorin)
* **Mineek** (restored patching research)
* **pwnerblu** (iPhone 5s iOS 9 downgrade research and documentation)

Finally, thanks to the many developers and researchers whose work on checkm8, Image4, SecureROM, and legacy iOS restoration made projects like this possible.

---

# License

5sd7 itself is licensed under the MIT License.

Third-party software remains under the licenses provided by its respective authors. Automatic downloading of third-party tools does **not** transfer ownership or change the original licensing of those projects.
